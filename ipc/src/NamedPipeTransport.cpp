#include "azookey/ipc/NamedPipeTransport.h"

#include <algorithm>
#include <atomic>
#include <chrono>
#include <cstdint>
#include <memory>
#include <mutex>
#include <string>
#include <thread>
#include <utility>
#include <vector>

#ifdef _WIN32

#define WIN32_LEAN_AND_MEAN
#include <Windows.h>
#include <sddl.h>

#endif

namespace azookey::ipc {

#ifdef _WIN32

namespace {

constexpr DWORD kPipeBufferSize = 64 * 1024;
constexpr uint32_t kMaxFrameSize = 16 * 1024 * 1024;

std::wstring Utf8ToWide(const std::string& value) {
  if (value.empty()) return {};
  const int size = MultiByteToWideChar(CP_UTF8, 0, value.data(),
                                       static_cast<int>(value.size()), nullptr, 0);
  if (size <= 0) return {};
  std::wstring wide(static_cast<size_t>(size), L'\0');
  MultiByteToWideChar(CP_UTF8, 0, value.data(), static_cast<int>(value.size()),
                      wide.data(), size);
  return wide;
}

std::string WideToUtf8(const std::wstring& value) {
  if (value.empty()) return {};
  const int size = WideCharToMultiByte(CP_UTF8, 0, value.data(),
                                       static_cast<int>(value.size()), nullptr, 0,
                                       nullptr, nullptr);
  if (size <= 0) return {};
  std::string utf8(static_cast<size_t>(size), '\0');
  WideCharToMultiByte(CP_UTF8, 0, value.data(), static_cast<int>(value.size()),
                      utf8.data(), size, nullptr, nullptr);
  return utf8;
}

std::wstring CurrentUserSidString() {
  HANDLE token = nullptr;
  if (!OpenProcessToken(GetCurrentProcess(), TOKEN_QUERY, &token)) {
    return {};
  }

  DWORD size = 0;
  GetTokenInformation(token, TokenUser, nullptr, 0, &size);
  if (GetLastError() != ERROR_INSUFFICIENT_BUFFER) {
    CloseHandle(token);
    return {};
  }

  std::vector<uint8_t> buffer(size);
  if (!GetTokenInformation(token, TokenUser, buffer.data(), size, &size)) {
    CloseHandle(token);
    return {};
  }
  CloseHandle(token);

  auto* user = reinterpret_cast<TOKEN_USER*>(buffer.data());
  LPWSTR sid_text = nullptr;
  if (!ConvertSidToStringSidW(user->User.Sid, &sid_text)) {
    return {};
  }
  std::wstring result(sid_text);
  LocalFree(sid_text);
  return result;
}

struct SecurityDescriptor {
  PSECURITY_DESCRIPTOR descriptor{nullptr};

  SecurityDescriptor() = default;
  SecurityDescriptor(const SecurityDescriptor&) = delete;
  SecurityDescriptor& operator=(const SecurityDescriptor&) = delete;
  SecurityDescriptor(SecurityDescriptor&& other) noexcept : descriptor(other.descriptor) {
    other.descriptor = nullptr;
  }
  SecurityDescriptor& operator=(SecurityDescriptor&& other) noexcept {
    if (this != &other) {
      if (descriptor) {
        LocalFree(descriptor);
      }
      descriptor = other.descriptor;
      other.descriptor = nullptr;
    }
    return *this;
  }

  ~SecurityDescriptor() {
    if (descriptor) {
      LocalFree(descriptor);
    }
  }
};

SecurityDescriptor BuildCurrentUserSecurityDescriptor() {
  SecurityDescriptor result;
  const auto sid = CurrentUserSidString();
  if (sid.empty()) return result;

  // Protected DACL: only the current user can connect to the per-user pipe.
  const std::wstring sddl = L"D:P(A;;GA;;;" + sid + L")";
  ConvertStringSecurityDescriptorToSecurityDescriptorW(
      sddl.c_str(), SDDL_REVISION_1, &result.descriptor, nullptr);
  return result;
}

HANDLE CreatePipeInstance(const std::string& pipe_name) {
  const auto wide_name = Utf8ToWide(pipe_name);
  if (wide_name.empty()) return INVALID_HANDLE_VALUE;

  auto security = BuildCurrentUserSecurityDescriptor();
  if (!security.descriptor) {
    return INVALID_HANDLE_VALUE;
  }

  SECURITY_ATTRIBUTES attrs;
  attrs.nLength = sizeof(attrs);
  attrs.lpSecurityDescriptor = security.descriptor;
  attrs.bInheritHandle = FALSE;

  return CreateNamedPipeW(
      wide_name.c_str(), PIPE_ACCESS_DUPLEX,
      PIPE_TYPE_MESSAGE | PIPE_READMODE_MESSAGE | PIPE_NOWAIT,
      PIPE_UNLIMITED_INSTANCES, kPipeBufferSize, kPipeBufferSize, 0, &attrs);
}

bool ReadBytes(HANDLE pipe, uint8_t* data, size_t size) {
  size_t offset = 0;
  while (offset < size) {
    DWORD read = 0;
    const DWORD chunk = static_cast<DWORD>(
        std::min<size_t>(size - offset, static_cast<size_t>(kPipeBufferSize)));
    const BOOL ok = ReadFile(pipe, data + offset, chunk, &read, nullptr);
    if (!ok) {
      const auto err = GetLastError();
      if (err != ERROR_MORE_DATA || read == 0) {
        return false;
      }
    }
    if (read == 0) {
      return false;
    }
    offset += read;
  }
  return true;
}

bool WriteBytes(HANDLE pipe, const uint8_t* data, size_t size) {
  size_t offset = 0;
  while (offset < size) {
    DWORD written = 0;
    const DWORD chunk = static_cast<DWORD>(
        std::min<size_t>(size - offset, static_cast<size_t>(kPipeBufferSize)));
    if (!WriteFile(pipe, data + offset, chunk, &written, nullptr) || written == 0) {
      return false;
    }
    offset += written;
  }
  FlushFileBuffers(pipe);
  return true;
}

std::optional<Envelope> ReadEnvelope(HANDLE pipe) {
  uint8_t header[4]{};
  if (!ReadBytes(pipe, header, sizeof(header))) {
    return std::nullopt;
  }

  const uint32_t size = static_cast<uint32_t>(header[0]) |
                        (static_cast<uint32_t>(header[1]) << 8) |
                        (static_cast<uint32_t>(header[2]) << 16) |
                        (static_cast<uint32_t>(header[3]) << 24);
  if (size == 0 || size > kMaxFrameSize) {
    return std::nullopt;
  }

  std::vector<uint8_t> payload(size);
  if (!ReadBytes(pipe, payload.data(), payload.size())) {
    return std::nullopt;
  }

  const std::string json(payload.begin(), payload.end());
  return Deserialize(json);
}

bool WriteEnvelope(HANDLE pipe, const Envelope& envelope) {
  const auto json = Serialize(envelope);
  const auto frame = EncodeLengthPrefixed(json);
  return WriteBytes(pipe, frame.data(), frame.size());
}

struct ClientState {
  explicit ClientState(HANDLE handle) : pipe(handle) {}

  std::mutex mutex;
  HANDLE pipe{INVALID_HANDLE_VALUE};
  bool closed{false};
};

void CloseClientPipe(const std::shared_ptr<ClientState>& client) {
  std::lock_guard<std::mutex> lock(client->mutex);
  if (!client->closed && client->pipe != INVALID_HANDLE_VALUE) {
    CloseHandle(client->pipe);
    client->closed = true;
    client->pipe = INVALID_HANDLE_VALUE;
  }
}

}  // namespace

struct NamedPipeServer::Impl {
  std::atomic<bool> running{false};
  std::string pipe_name;
  MessageHandler handler;
  std::thread accept_thread;

  mutable std::mutex mutex;
  HANDLE listen_pipe{INVALID_HANDLE_VALUE};
  std::vector<std::shared_ptr<ClientState>> clients;
  std::vector<std::thread> client_threads;

  void AcceptLoop(HANDLE first_pipe) {
    HANDLE current = first_pipe;
    while (running.load()) {
      const BOOL ok = ConnectNamedPipe(current, nullptr);
      const DWORD err = ok ? ERROR_SUCCESS : GetLastError();
      const bool connected = ok || err == ERROR_PIPE_CONNECTED;

      if (!connected && (err == ERROR_PIPE_LISTENING || err == ERROR_NO_DATA)) {
        Sleep(25);
        continue;
      }

      {
        std::lock_guard<std::mutex> lock(mutex);
        if (listen_pipe == current) {
          listen_pipe = INVALID_HANDLE_VALUE;
        }
      }

      if (!running.load()) {
        CloseHandle(current);
        break;
      }

      if (connected) {
        DWORD mode = PIPE_READMODE_MESSAGE | PIPE_WAIT;
        SetNamedPipeHandleState(current, &mode, nullptr, nullptr);

        auto client = std::make_shared<ClientState>(current);
        {
          std::lock_guard<std::mutex> lock(mutex);
          clients.push_back(client);
          client_threads.emplace_back([this, client]() { ClientLoop(client); });
        }
      } else {
        CloseHandle(current);
      }

      current = CreatePipeInstance(pipe_name);
      if (current == INVALID_HANDLE_VALUE) {
        running.store(false);
        break;
      }

      {
        std::lock_guard<std::mutex> lock(mutex);
        if (!running.load()) {
          CloseHandle(current);
          break;
        }
        listen_pipe = current;
      }
    }
  }

  void ClientLoop(std::shared_ptr<ClientState> client) {
    while (running.load()) {
      HANDLE pipe = INVALID_HANDLE_VALUE;
      {
        std::lock_guard<std::mutex> lock(client->mutex);
        if (client->closed) break;
        pipe = client->pipe;
      }

      auto request = ReadEnvelope(pipe);
      if (!request) break;

      std::optional<Envelope> response;
      try {
        response = handler ? handler(*request) : std::nullopt;
      } catch (...) {
        break;
      }

      if (response && !WriteEnvelope(pipe, *response)) {
        break;
      }
    }

    HANDLE pipe = INVALID_HANDLE_VALUE;
    {
      std::lock_guard<std::mutex> lock(client->mutex);
      pipe = client->pipe;
    }
    if (pipe != INVALID_HANDLE_VALUE) {
      DisconnectNamedPipe(pipe);
    }
    CloseClientPipe(client);
  }
};

struct NamedPipeClient::Impl {
  std::mutex mutex;
  HANDLE pipe{INVALID_HANDLE_VALUE};
  bool connected{false};
};

NamedPipeServer::NamedPipeServer() : impl_(std::make_unique<Impl>()) {}
NamedPipeServer::~NamedPipeServer() { Stop(); }

bool NamedPipeServer::Start(const std::string& pipe_name, MessageHandler handler) {
  if (pipe_name.empty() || !handler) {
    return false;
  }

  std::lock_guard<std::mutex> lock(impl_->mutex);
  if (impl_->running.load()) {
    return false;
  }

  HANDLE first_pipe = CreatePipeInstance(pipe_name);
  if (first_pipe == INVALID_HANDLE_VALUE) {
    return false;
  }

  impl_->pipe_name = pipe_name;
  impl_->handler = std::move(handler);
  impl_->listen_pipe = first_pipe;
  impl_->running.store(true);
  impl_->accept_thread = std::thread([this, first_pipe]() { impl_->AcceptLoop(first_pipe); });
  return true;
}

void NamedPipeServer::Stop() {
  std::vector<std::shared_ptr<ClientState>> clients;
  {
    std::lock_guard<std::mutex> lock(impl_->mutex);
    if (!impl_->running.load() && !impl_->accept_thread.joinable()) {
      return;
    }
    impl_->running.store(false);
    clients = impl_->clients;
  }

  for (const auto& client : clients) {
    CloseClientPipe(client);
  }

  if (impl_->accept_thread.joinable()) {
    impl_->accept_thread.join();
  }

  std::vector<std::thread> threads;
  {
    std::lock_guard<std::mutex> lock(impl_->mutex);
    impl_->listen_pipe = INVALID_HANDLE_VALUE;
    threads.swap(impl_->client_threads);
    clients = impl_->clients;
    impl_->clients.clear();
  }

  for (const auto& client : clients) {
    CloseClientPipe(client);
  }
  for (auto& thread : threads) {
    if (thread.joinable()) {
      thread.join();
    }
  }
}

bool NamedPipeServer::IsRunning() const { return impl_->running.load(); }

NamedPipeClient::NamedPipeClient() : impl_(std::make_unique<Impl>()) {}
NamedPipeClient::~NamedPipeClient() { Disconnect(); }

bool NamedPipeClient::Connect(const std::string& pipe_name, uint32_t timeout_ms) {
  Disconnect();
  const auto wide_name = Utf8ToWide(pipe_name);
  if (wide_name.empty()) {
    return false;
  }

  const auto start = std::chrono::steady_clock::now();
  while (true) {
    HANDLE pipe = CreateFileW(wide_name.c_str(), GENERIC_READ | GENERIC_WRITE, 0,
                              nullptr, OPEN_EXISTING, 0, nullptr);
    if (pipe != INVALID_HANDLE_VALUE) {
      DWORD mode = PIPE_READMODE_MESSAGE;
      if (!SetNamedPipeHandleState(pipe, &mode, nullptr, nullptr)) {
        CloseHandle(pipe);
        return false;
      }
      std::lock_guard<std::mutex> lock(impl_->mutex);
      impl_->pipe = pipe;
      impl_->connected = true;
      return true;
    }

    const auto err = GetLastError();
    const auto elapsed = std::chrono::duration_cast<std::chrono::milliseconds>(
        std::chrono::steady_clock::now() - start);
    if (elapsed.count() >= timeout_ms) {
      return false;
    }

    const auto remaining = static_cast<DWORD>(timeout_ms - elapsed.count());
    if (err == ERROR_PIPE_BUSY) {
      WaitNamedPipeW(wide_name.c_str(), remaining);
    } else if (err == ERROR_FILE_NOT_FOUND) {
      Sleep(std::min<DWORD>(25, remaining));
    } else {
      return false;
    }
  }
}

void NamedPipeClient::Disconnect() {
  std::lock_guard<std::mutex> lock(impl_->mutex);
  if (impl_->pipe != INVALID_HANDLE_VALUE) {
    CloseHandle(impl_->pipe);
    impl_->pipe = INVALID_HANDLE_VALUE;
  }
  impl_->connected = false;
}

bool NamedPipeClient::IsConnected() const {
  std::lock_guard<std::mutex> lock(impl_->mutex);
  return impl_->connected;
}

bool NamedPipeClient::Send(const Envelope& envelope) {
  HANDLE pipe = INVALID_HANDLE_VALUE;
  {
    std::lock_guard<std::mutex> lock(impl_->mutex);
    if (!impl_->connected) return false;
    pipe = impl_->pipe;
  }

  if (!WriteEnvelope(pipe, envelope)) {
    Disconnect();
    return false;
  }
  return true;
}

std::optional<Envelope> NamedPipeClient::Receive() {
  HANDLE pipe = INVALID_HANDLE_VALUE;
  {
    std::lock_guard<std::mutex> lock(impl_->mutex);
    if (!impl_->connected) return std::nullopt;
    pipe = impl_->pipe;
  }

  auto envelope = ReadEnvelope(pipe);
  if (!envelope) {
    Disconnect();
  }
  return envelope;
}

std::optional<Envelope> NamedPipeClient::ReceiveWithTimeout(uint32_t timeout_ms) {
  const auto deadline =
      std::chrono::steady_clock::now() + std::chrono::milliseconds(timeout_ms);
  while (std::chrono::steady_clock::now() < deadline) {
    HANDLE pipe = INVALID_HANDLE_VALUE;
    {
      std::lock_guard<std::mutex> lock(impl_->mutex);
      if (!impl_->connected) return std::nullopt;
      pipe = impl_->pipe;
    }
    DWORD avail = 0;
    if (!PeekNamedPipe(pipe, nullptr, 0, nullptr, &avail, nullptr)) {
      Disconnect();
      return std::nullopt;
    }
    if (avail > 0) {
      return Receive();
    }
    std::this_thread::sleep_for(std::chrono::milliseconds(10));
  }
  return std::nullopt;
}

std::string DefaultPipeName() {
  const auto sid = CurrentUserSidString();
  if (sid.empty()) {
    return "\\\\.\\pipe\\azookey-default";
  }
  return "\\\\.\\pipe\\azookey-" + WideToUtf8(sid);
}

#else  // !_WIN32

struct NamedPipeServer::Impl {};
struct NamedPipeClient::Impl {};

NamedPipeServer::NamedPipeServer() : impl_(std::make_unique<Impl>()) {}
NamedPipeServer::~NamedPipeServer() = default;
bool NamedPipeServer::Start(const std::string&, MessageHandler) { return false; }
void NamedPipeServer::Stop() {}
bool NamedPipeServer::IsRunning() const { return false; }

NamedPipeClient::NamedPipeClient() : impl_(std::make_unique<Impl>()) {}
NamedPipeClient::~NamedPipeClient() = default;
bool NamedPipeClient::Connect(const std::string&, uint32_t) { return false; }
void NamedPipeClient::Disconnect() {}
bool NamedPipeClient::IsConnected() const { return false; }
bool NamedPipeClient::Send(const Envelope&) { return false; }
std::optional<Envelope> NamedPipeClient::Receive() { return std::nullopt; }
std::optional<Envelope> NamedPipeClient::ReceiveWithTimeout(uint32_t) { return std::nullopt; }

std::string DefaultPipeName() {
  return "/tmp/azookey-namedpipe-unsupported";
}

#endif

}  // namespace azookey::ipc

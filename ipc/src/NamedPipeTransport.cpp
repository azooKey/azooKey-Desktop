#include "azookey/ipc/NamedPipeTransport.h"

#include <atomic>
#include <chrono>
#include <future>
#include <limits>
#include <memory>
#include <mutex>
#include <string>
#include <thread>
#include <vector>

#ifdef _WIN32
#ifndef NOMINMAX
#define NOMINMAX
#endif
#include <Windows.h>
#include <sddl.h>
#endif

namespace azookey::ipc {

#ifdef _WIN32

namespace {

constexpr DWORD kPipeBufferSize = 64 * 1024;
constexpr size_t kMaxFrameBytes = 4 * 1024 * 1024;

std::wstring Utf8ToWide(const std::string& input) {
  if (input.empty()) return std::wstring();
  const int size = MultiByteToWideChar(CP_UTF8, MB_ERR_INVALID_CHARS,
                                       input.data(), static_cast<int>(input.size()),
                                       nullptr, 0);
  if (size <= 0) return std::wstring();
  std::wstring output(static_cast<size_t>(size), L'\0');
  MultiByteToWideChar(CP_UTF8, MB_ERR_INVALID_CHARS, input.data(),
                      static_cast<int>(input.size()), output.data(), size);
  return output;
}

std::string WideToUtf8(const std::wstring& input) {
  if (input.empty()) return std::string();
  const int size = WideCharToMultiByte(CP_UTF8, 0, input.data(),
                                       static_cast<int>(input.size()), nullptr, 0,
                                       nullptr, nullptr);
  if (size <= 0) return std::string();
  std::string output(static_cast<size_t>(size), '\0');
  WideCharToMultiByte(CP_UTF8, 0, input.data(), static_cast<int>(input.size()),
                      output.data(), size, nullptr, nullptr);
  return output;
}

struct HandleGuard {
  HANDLE handle{INVALID_HANDLE_VALUE};

  ~HandleGuard() {
    if (handle != INVALID_HANDLE_VALUE && handle != nullptr) {
      CloseHandle(handle);
    }
  }

  HANDLE Release() {
    HANDLE result = handle;
    handle = INVALID_HANDLE_VALUE;
    return result;
  }
};

std::optional<std::wstring> CurrentUserSidString() {
  HandleGuard token;
  if (!OpenProcessToken(GetCurrentProcess(), TOKEN_QUERY, &token.handle)) {
    return std::nullopt;
  }

  DWORD size = 0;
  GetTokenInformation(token.handle, TokenUser, nullptr, 0, &size);
  if (GetLastError() != ERROR_INSUFFICIENT_BUFFER || size == 0) {
    return std::nullopt;
  }

  std::vector<BYTE> buffer(size);
  if (!GetTokenInformation(token.handle, TokenUser, buffer.data(), size, &size)) {
    return std::nullopt;
  }

  auto* token_user = reinterpret_cast<TOKEN_USER*>(buffer.data());
  LPWSTR sid_text = nullptr;
  if (!ConvertSidToStringSidW(token_user->User.Sid, &sid_text)) {
    return std::nullopt;
  }

  std::wstring result(sid_text);
  LocalFree(sid_text);
  return result;
}

struct PipeSecurity {
  SECURITY_ATTRIBUTES attrs{};
  PSECURITY_DESCRIPTOR descriptor{nullptr};

  explicit PipeSecurity(PSECURITY_DESCRIPTOR sd) : descriptor(sd) {
    attrs.nLength = sizeof(attrs);
    attrs.lpSecurityDescriptor = descriptor;
    attrs.bInheritHandle = FALSE;
  }

  ~PipeSecurity() {
    if (descriptor) {
      LocalFree(descriptor);
    }
  }
};

std::unique_ptr<PipeSecurity> BuildPipeSecurity() {
  auto sid = CurrentUserSidString();
  if (!sid) return nullptr;

  const std::wstring sddl = L"D:P(A;;GA;;;" + *sid + L")";
  PSECURITY_DESCRIPTOR descriptor = nullptr;
  if (!ConvertStringSecurityDescriptorToSecurityDescriptorW(
          sddl.c_str(), SDDL_REVISION_1, &descriptor, nullptr)) {
    return nullptr;
  }
  return std::make_unique<PipeSecurity>(descriptor);
}

HANDLE CreateServerPipe(const std::wstring& pipe_name) {
  auto security = BuildPipeSecurity();
  DWORD open_mode = PIPE_ACCESS_DUPLEX;
  DWORD pipe_mode = PIPE_TYPE_MESSAGE | PIPE_READMODE_MESSAGE | PIPE_WAIT;
#ifdef PIPE_REJECT_REMOTE_CLIENTS
  pipe_mode |= PIPE_REJECT_REMOTE_CLIENTS;
#endif
  return CreateNamedPipeW(pipe_name.c_str(), open_mode, pipe_mode,
                          PIPE_UNLIMITED_INSTANCES, kPipeBufferSize,
                          kPipeBufferSize, 0,
                          security ? &security->attrs : nullptr);
}

std::optional<Envelope> ReadEnvelopeFromPipe(HANDLE pipe) {
  std::vector<uint8_t> frame;
  std::vector<uint8_t> chunk(4096);

  for (;;) {
    DWORD bytes_read = 0;
    const BOOL ok = ReadFile(pipe, chunk.data(), static_cast<DWORD>(chunk.size()),
                             &bytes_read, nullptr);
    if (!ok) {
      const DWORD error = GetLastError();
      if (error == ERROR_MORE_DATA) {
        frame.insert(frame.end(), chunk.begin(), chunk.begin() + bytes_read);
        if (frame.size() > kMaxFrameBytes) return std::nullopt;
        continue;
      }
      return std::nullopt;
    }

    if (bytes_read == 0) return std::nullopt;
    frame.insert(frame.end(), chunk.begin(), chunk.begin() + bytes_read);
    if (frame.size() > kMaxFrameBytes) return std::nullopt;
    break;
  }

  auto json = DecodeLengthPrefixed(frame);
  if (!json) return std::nullopt;
  return Deserialize(*json);
}

bool WriteEnvelopeToPipe(HANDLE pipe, const Envelope& envelope) {
  const auto frame = EncodeLengthPrefixed(Serialize(envelope));
  if (frame.empty() || frame.size() > kMaxFrameBytes ||
      frame.size() > static_cast<size_t>(std::numeric_limits<DWORD>::max())) {
    return false;
  }

  DWORD bytes_written = 0;
  const BOOL ok = WriteFile(pipe, frame.data(), static_cast<DWORD>(frame.size()),
                            &bytes_written, nullptr);
  return ok && bytes_written == frame.size();
}

struct ServerConnection {
  std::atomic<HANDLE> pipe{INVALID_HANDLE_VALUE};
  std::thread thread;
};

void CloseServerConnection(const std::shared_ptr<ServerConnection>& connection) {
  const HANDLE pipe = connection->pipe.exchange(INVALID_HANDLE_VALUE);
  if (pipe != INVALID_HANDLE_VALUE && pipe != nullptr) {
    CancelIoEx(pipe, nullptr);
    DisconnectNamedPipe(pipe);
    CloseHandle(pipe);
  }
}

void SignalAcceptLoop(const std::wstring& pipe_name) {
  for (int i = 0; i < 3; ++i) {
    if (!WaitNamedPipeW(pipe_name.c_str(), 10)) {
      Sleep(10);
      continue;
    }
    HANDLE pipe = CreateFileW(pipe_name.c_str(), GENERIC_READ | GENERIC_WRITE, 0,
                              nullptr, OPEN_EXISTING, 0, nullptr);
    if (pipe != INVALID_HANDLE_VALUE) {
      CloseHandle(pipe);
      return;
    }
    Sleep(10);
  }
}

}  // namespace

struct NamedPipeServer::Impl {
  std::atomic<bool> running{false};
  std::wstring pipe_name;
  MessageHandler handler;
  std::thread accept_thread;
  std::mutex clients_mutex;
  std::vector<std::shared_ptr<ServerConnection>> clients;

  void RunAcceptLoop(std::promise<bool> ready) {
    bool reported = false;
    auto report = [&](bool ok) {
      if (!reported) {
        ready.set_value(ok);
        reported = true;
      }
    };

    while (running.load()) {
      HANDLE pipe = CreateServerPipe(pipe_name);
      if (pipe == INVALID_HANDLE_VALUE) {
        report(false);
        running.store(false);
        break;
      }
      report(true);

      const BOOL connected =
          ConnectNamedPipe(pipe, nullptr) ? TRUE : (GetLastError() == ERROR_PIPE_CONNECTED);
      if (!connected) {
        CloseHandle(pipe);
        continue;
      }
      if (!running.load()) {
        DisconnectNamedPipe(pipe);
        CloseHandle(pipe);
        break;
      }

      auto connection = std::make_shared<ServerConnection>();
      connection->pipe.store(pipe);
      connection->thread = std::thread([this, connection]() { RunClient(connection); });

      std::lock_guard<std::mutex> lock(clients_mutex);
      clients.push_back(std::move(connection));
    }

    report(false);
  }

  void RunClient(const std::shared_ptr<ServerConnection>& connection) {
    while (running.load()) {
      const HANDLE pipe = connection->pipe.load();
      if (pipe == INVALID_HANDLE_VALUE || pipe == nullptr) break;

      auto request = ReadEnvelopeFromPipe(pipe);
      if (!request) break;

      std::optional<Envelope> response;
      try {
        response = handler(*request);
      } catch (...) {
        break;
      }

      if (response) {
        const HANDLE current_pipe = connection->pipe.load();
        if (current_pipe == INVALID_HANDLE_VALUE || current_pipe == nullptr ||
            !WriteEnvelopeToPipe(current_pipe, *response)) {
          break;
        }
      }
    }

    CloseServerConnection(connection);
  }
};

struct NamedPipeClient::Impl {
  HANDLE pipe{INVALID_HANDLE_VALUE};
};

NamedPipeServer::NamedPipeServer() : impl_(std::make_unique<Impl>()) {}
NamedPipeServer::~NamedPipeServer() { Stop(); }

bool NamedPipeServer::Start(const std::string& pipe_name, MessageHandler handler) {
  if (pipe_name.empty() || !handler) return false;
  if (impl_->running.exchange(true)) return false;

  impl_->pipe_name = Utf8ToWide(pipe_name);
  impl_->handler = std::move(handler);
  if (impl_->pipe_name.empty()) {
    impl_->running.store(false);
    return false;
  }

  std::promise<bool> ready;
  auto started = ready.get_future();
  impl_->accept_thread =
      std::thread([this, ready = std::move(ready)]() mutable {
        impl_->RunAcceptLoop(std::move(ready));
      });

  if (!started.get()) {
    impl_->running.store(false);
    if (impl_->accept_thread.joinable()) impl_->accept_thread.join();
    return false;
  }
  return true;
}

void NamedPipeServer::Stop() {
  if (!impl_) return;

  const bool was_running = impl_->running.exchange(false);
  if (was_running) {
    SignalAcceptLoop(impl_->pipe_name);
  }
  if (impl_->accept_thread.joinable()) {
    impl_->accept_thread.join();
  }

  std::vector<std::shared_ptr<ServerConnection>> clients;
  {
    std::lock_guard<std::mutex> lock(impl_->clients_mutex);
    clients.swap(impl_->clients);
  }
  for (auto& client : clients) {
    CloseServerConnection(client);
  }
  for (auto& client : clients) {
    if (client->thread.joinable()) client->thread.join();
  }
}

bool NamedPipeServer::IsRunning() const {
  return impl_ && impl_->running.load();
}

NamedPipeClient::NamedPipeClient() : impl_(std::make_unique<Impl>()) {}
NamedPipeClient::~NamedPipeClient() { Disconnect(); }

bool NamedPipeClient::Connect(const std::string& pipe_name, uint32_t timeout_ms) {
  Disconnect();
  const auto wide_name = Utf8ToWide(pipe_name);
  if (wide_name.empty()) return false;

  const auto deadline =
      std::chrono::steady_clock::now() + std::chrono::milliseconds(timeout_ms);
  for (;;) {
    HANDLE pipe = CreateFileW(wide_name.c_str(), GENERIC_READ | GENERIC_WRITE, 0,
                              nullptr, OPEN_EXISTING, 0, nullptr);
    if (pipe != INVALID_HANDLE_VALUE) {
      DWORD mode = PIPE_READMODE_MESSAGE;
      if (!SetNamedPipeHandleState(pipe, &mode, nullptr, nullptr)) {
        CloseHandle(pipe);
        return false;
      }
      impl_->pipe = pipe;
      return true;
    }

    const DWORD error = GetLastError();
    if (timeout_ms == 0 || std::chrono::steady_clock::now() >= deadline) {
      return false;
    }

    if (error == ERROR_PIPE_BUSY) {
      const auto remaining = std::chrono::duration_cast<std::chrono::milliseconds>(
          deadline - std::chrono::steady_clock::now());
      const DWORD wait_ms = static_cast<DWORD>(remaining.count() > 0 ? remaining.count() : 1);
      WaitNamedPipeW(wide_name.c_str(), wait_ms);
    } else if (error == ERROR_FILE_NOT_FOUND) {
      Sleep(25);
    } else {
      return false;
    }
  }
}

void NamedPipeClient::Disconnect() {
  if (!impl_) return;
  if (impl_->pipe != INVALID_HANDLE_VALUE && impl_->pipe != nullptr) {
    CloseHandle(impl_->pipe);
    impl_->pipe = INVALID_HANDLE_VALUE;
  }
}

bool NamedPipeClient::IsConnected() const {
  return impl_ && impl_->pipe != INVALID_HANDLE_VALUE && impl_->pipe != nullptr;
}

bool NamedPipeClient::Send(const Envelope& envelope) {
  if (!IsConnected()) return false;
  return WriteEnvelopeToPipe(impl_->pipe, envelope);
}

std::optional<Envelope> NamedPipeClient::Receive() {
  if (!IsConnected()) return std::nullopt;
  return ReadEnvelopeFromPipe(impl_->pipe);
}

std::string DefaultPipeName() {
  auto sid = CurrentUserSidString();
  if (!sid) return "\\\\.\\pipe\\azookey-default";
  return "\\\\.\\pipe\\azookey-" + WideToUtf8(*sid);
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

std::string DefaultPipeName() {
  return "/tmp/azookey-namedpipe-unsupported";
}

#endif

}  // namespace azookey::ipc

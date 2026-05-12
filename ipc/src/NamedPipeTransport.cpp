#include "azookey/ipc/NamedPipeTransport.h"

// The Windows implementation lives behind `_WIN32` so this translation unit
// builds on Linux/macOS for development. The real wire-level logic is added
// in milestone M1; until then, both platforms see no-op stubs that fail
// cleanly.

namespace azookey::ipc {

struct NamedPipeServer::Impl {};
struct NamedPipeClient::Impl {};

#ifdef _WIN32

// TODO(M1): real implementation
//   - CreateNamedPipeW with PIPE_TYPE_MESSAGE | PIPE_READMODE_MESSAGE
//   - OVERLAPPED I/O on a worker thread, multi-client accept loop
//   - SECURITY_ATTRIBUTES with DACL restricted to current user's SID
//     via ConvertStringSecurityDescriptorToSecurityDescriptorW
//   - EncodeLengthPrefixed framing on send, DecodeLengthPrefixed on recv
//
// The structure is left here as a placeholder so M1 only has to fill in the
// method bodies and link advapi32.

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
  // TODO(M1): SID-bearing default. For now return a generic name; main.cpp
  // accepts a --pipe override and the installer will pass an explicit value.
  return "\\\\.\\pipe\\azookey-default";
}

#else  // !_WIN32

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

#include <cstdio>
#include <stdexcept>
#include <optional>
#include <string>

#include "azookey/ipc/NamedPipeTransport.h"
#include "azookey/ipc/Payloads.h"

#ifdef _WIN32
#define WIN32_LEAN_AND_MEAN
#include <Windows.h>
#endif

static void Expect(bool cond, const char* msg) {
  if (!cond) throw std::runtime_error(msg);
}

int main() {
#ifndef _WIN32
  return 0;
#else
  try {
  const std::string pipe_name =
      "\\\\.\\pipe\\azookey-ipc-test-" + std::to_string(GetCurrentProcessId());

  azookey::ipc::NamedPipeServer server;
  const bool started = server.Start(
      pipe_name, [](const azookey::ipc::Envelope& req) -> std::optional<azookey::ipc::Envelope> {
        azookey::ipc::Envelope res;
        res.version = req.version;
        res.request_id = req.request_id;
        res.trace_id = req.trace_id;
        res.type = req.type;

        if (req.type == azookey::ipc::MessageType::Handshake) {
          auto parsed = azookey::ipc::ParseHandshakeRequest(req.payload_json);
          azookey::ipc::HandshakeResponse payload;
          payload.host_version = "test-host";
          payload.protocol_version = 1;
          payload.accepted = parsed && parsed->protocol_version == 1;
          payload.model_loaded = false;
          res.payload_json = azookey::ipc::BuildHandshakeResponse(payload);
          return res;
        }

        if (req.type == azookey::ipc::MessageType::Ping) {
          auto parsed = azookey::ipc::ParsePing(req.payload_json);
          azookey::ipc::PingPayload payload;
          payload.nonce = parsed ? parsed->nonce : 0;
          payload.t_ms = 123456789;
          res.payload_json = azookey::ipc::BuildPing(payload);
          return res;
        }

        return std::nullopt;
      });
  Expect(started, "server failed to start");

  azookey::ipc::NamedPipeClient client;
  Expect(client.Connect(pipe_name, 2000), "client failed to connect");

  azookey::ipc::HandshakeRequest handshake;
  handshake.tip_version = "test-tip";
  handshake.protocol_version = 1;
  handshake.capabilities = {"ping"};

  azookey::ipc::Envelope henv;
  henv.version = 1;
  henv.request_id = 1;
  henv.trace_id = "transport-handshake";
  henv.type = azookey::ipc::MessageType::Handshake;
  henv.payload_json = azookey::ipc::BuildHandshakeRequest(handshake);

  Expect(client.Send(henv), "failed to send handshake");
  auto hres = client.Receive();
  Expect(hres.has_value(), "missing handshake response");
  Expect(hres->request_id == 1, "handshake request id mismatch");
  auto hpayload = azookey::ipc::ParseHandshakeResponse(hres->payload_json);
  Expect(hpayload.has_value(), "handshake response parse failed");
  Expect(hpayload->accepted, "handshake not accepted");
  Expect(hpayload->host_version == "test-host", "host version mismatch");

  azookey::ipc::PingPayload ping;
  ping.nonce = 424242;
  ping.t_ms = 1;

  azookey::ipc::Envelope penv;
  penv.version = 1;
  penv.request_id = 2;
  penv.trace_id = "transport-ping";
  penv.type = azookey::ipc::MessageType::Ping;
  penv.payload_json = azookey::ipc::BuildPing(ping);

  Expect(client.Send(penv), "failed to send ping");
  auto pres = client.Receive();
  Expect(pres.has_value(), "missing ping response");
  Expect(pres->request_id == 2, "ping request id mismatch");
  auto ppayload = azookey::ipc::ParsePing(pres->payload_json);
  Expect(ppayload.has_value(), "ping response parse failed");
  Expect(ppayload->nonce == 424242, "ping nonce mismatch");

  client.Disconnect();
  server.Stop();
  return 0;
  } catch (const std::exception& e) {
    std::fprintf(stderr, "FAIL: %s\n", e.what());
    return 1;
  }
#endif
}

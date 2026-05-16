// Tests the TIP-client IPC flow that mirrors StartDebugIpcProbe in TextService.cpp.
// Verifies: connect → Handshake → Ping roundtrip, and QueryCandidates roundtrip.

#include <cstdio>
#include <optional>
#include <stdexcept>
#include <string>
#include <vector>

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
      "\\\\.\\pipe\\azookey-tip-client-test-" + std::to_string(GetCurrentProcessId());

  // Mock server that mimics inference-host behaviour needed by TIP activation.
  azookey::ipc::NamedPipeServer server;
  const bool started = server.Start(
      pipe_name,
      [](const azookey::ipc::Envelope& req) -> std::optional<azookey::ipc::Envelope> {
        azookey::ipc::Envelope res;
        res.version = req.version;
        res.request_id = req.request_id;
        res.trace_id = req.trace_id;
        res.type = req.type;

        if (req.type == azookey::ipc::MessageType::Handshake) {
          auto parsed = azookey::ipc::ParseHandshakeRequest(req.payload_json);
          azookey::ipc::HandshakeResponse payload;
          payload.host_version = "mock-host-0.1.0";
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
          payload.t_ms = GetTickCount64();
          res.payload_json = azookey::ipc::BuildPing(payload);
          return res;
        }

        if (req.type == azookey::ipc::MessageType::QueryCandidates) {
          auto parsed = azookey::ipc::ParseQueryCandidatesRequest(req.payload_json);
          azookey::ipc::QueryCandidatesResponse payload;
          if (parsed) {
            azookey::ipc::CandidateField c;
            c.surface = "mock:" + parsed->reading;
            c.reading = parsed->reading;
            c.score = 1.0;
            c.source = "mock";
            payload.candidates = {c};
          }
          payload.partial = false;
          res.payload_json = azookey::ipc::BuildQueryCandidatesResponse(payload);
          return res;
        }

        return std::nullopt;
      });
  Expect(started, "mock server failed to start");

  // --- TIP activation flow (mirrors StartDebugIpcProbe) ---
  azookey::ipc::NamedPipeClient client;
  Expect(client.Connect(pipe_name, 2000), "TIP client failed to connect");

  // Handshake
  azookey::ipc::HandshakeRequest handshake;
  handshake.tip_version = "0.1.0";
  handshake.protocol_version = 1;
  handshake.capabilities = {"ping"};

  azookey::ipc::Envelope henv;
  henv.version = 1;
  henv.request_id = 1;
  henv.trace_id = "tip-activate-handshake";
  henv.type = azookey::ipc::MessageType::Handshake;
  henv.payload_json = azookey::ipc::BuildHandshakeRequest(handshake);

  Expect(client.Send(henv), "failed to send handshake");
  auto hres = client.Receive();
  Expect(hres.has_value(), "missing handshake response");
  Expect(hres->request_id == 1, "handshake request_id mismatch");
  auto hpayload = azookey::ipc::ParseHandshakeResponse(hres->payload_json);
  Expect(hpayload.has_value(), "handshake response parse failed");
  Expect(hpayload->accepted, "handshake rejected");
  Expect(hpayload->host_version == "mock-host-0.1.0", "host_version mismatch");

  // Ping
  azookey::ipc::PingPayload ping;
  ping.nonce = 999888777;
  ping.t_ms = ping.nonce;

  azookey::ipc::Envelope penv;
  penv.version = 1;
  penv.request_id = 2;
  penv.trace_id = "tip-activate-ping";
  penv.type = azookey::ipc::MessageType::Ping;
  penv.payload_json = azookey::ipc::BuildPing(ping);

  Expect(client.Send(penv), "failed to send ping");
  auto pres = client.Receive();
  Expect(pres.has_value(), "missing ping response");
  Expect(pres->request_id == 2, "ping request_id mismatch");
  auto ppayload = azookey::ipc::ParsePing(pres->payload_json);
  Expect(ppayload.has_value(), "ping response parse failed");
  Expect(ppayload->nonce == ping.nonce, "ping nonce mismatch");

  // --- QueryCandidates roundtrip (M4 path) ---
  azookey::ipc::QueryCandidatesRequest qreq;
  qreq.reading = "にほんご";
  qreq.left_context = "";
  qreq.max_candidates = 5;
  qreq.live = true;

  azookey::ipc::Envelope qenv;
  qenv.version = 1;
  qenv.request_id = 3;
  qenv.trace_id = "tip-key-query";
  qenv.type = azookey::ipc::MessageType::QueryCandidates;
  qenv.payload_json = azookey::ipc::BuildQueryCandidatesRequest(qreq);

  Expect(client.Send(qenv), "failed to send QueryCandidates");
  auto qres = client.Receive();
  Expect(qres.has_value(), "missing QueryCandidates response");
  Expect(qres->request_id == 3, "QueryCandidates request_id mismatch");
  auto qpayload = azookey::ipc::ParseQueryCandidatesResponse(qres->payload_json);
  Expect(qpayload.has_value(), "QueryCandidates response parse failed");
  Expect(!qpayload->candidates.empty(), "expected at least one candidate");
  Expect(qpayload->candidates[0].reading == "にほんご", "candidate reading mismatch");

  client.Disconnect();
  server.Stop();
  return 0;
  } catch (const std::exception& e) {
    std::fprintf(stderr, "FAIL: %s\n", e.what());
    return 1;
  }
#endif
}

#include <stdexcept>
#include <string>

#include "azookey/ipc/NamedPipeTransport.h"
#include "azookey/ipc/Payloads.h"

#ifdef _WIN32
#ifndef NOMINMAX
#define NOMINMAX
#endif
#include <Windows.h>
#include <atomic>
#include <chrono>
#endif

static void Expect(bool cond, const char* msg) {
  if (!cond) throw std::runtime_error(msg);
}

int main() {
#ifndef _WIN32
  return 0;
#else
  const std::string pipe_name =
      azookey::ipc::DefaultPipeName() + "-test-" +
      std::to_string(GetCurrentProcessId()) + "-" +
      std::to_string(std::chrono::steady_clock::now().time_since_epoch().count());

  std::atomic<int> handled{0};
  azookey::ipc::NamedPipeServer server;
  Expect(server.Start(pipe_name, [&](const azookey::ipc::Envelope& request)
                               -> std::optional<azookey::ipc::Envelope> {
           handled.fetch_add(1);
           azookey::ipc::Envelope response;
           response.version = request.version;
           response.request_id = request.request_id;
           response.trace_id = request.trace_id;
           response.type = request.type;

           if (request.type == azookey::ipc::MessageType::Handshake) {
             auto parsed = azookey::ipc::ParseHandshakeRequest(request.payload_json);
             azookey::ipc::HandshakeResponse payload;
             payload.host_version = "test-host";
             payload.protocol_version = 1;
             payload.accepted = parsed.has_value() && parsed->protocol_version == 1;
             payload.model_loaded = false;
             response.payload_json = azookey::ipc::BuildHandshakeResponse(payload);
             return response;
           }

           if (request.type == azookey::ipc::MessageType::Ping) {
             auto parsed = azookey::ipc::ParsePing(request.payload_json);
             azookey::ipc::PingPayload payload;
             payload.nonce = parsed ? parsed->nonce : 0;
             payload.t_ms = 123456;
             response.payload_json = azookey::ipc::BuildPing(payload);
             return response;
           }

           if (request.type == azookey::ipc::MessageType::QueryCandidates) {
             auto parsed = azookey::ipc::ParseQueryCandidatesRequest(request.payload_json);
             azookey::ipc::QueryCandidatesResponse payload;
             if (parsed) {
               payload.candidates.push_back(
                   {"日本語", parsed->reading, 1.0, "named-pipe-test"});
             }
             response.payload_json = azookey::ipc::BuildQueryCandidatesResponse(payload);
             return response;
           }

           return std::nullopt;
         }),
         "server start failed");
  Expect(server.IsRunning(), "server should be running");

  azookey::ipc::NamedPipeClient client;
  Expect(client.Connect(pipe_name, 3000), "client connect failed");
  Expect(client.IsConnected(), "client should be connected");

  azookey::ipc::HandshakeRequest handshake_payload;
  handshake_payload.tip_version = "test-tip";
  handshake_payload.protocol_version = 1;
  handshake_payload.capabilities = {"ping"};

  azookey::ipc::Envelope handshake;
  handshake.request_id = 1;
  handshake.trace_id = "trace-handshake";
  handshake.type = azookey::ipc::MessageType::Handshake;
  handshake.payload_json = azookey::ipc::BuildHandshakeRequest(handshake_payload);

  Expect(client.Send(handshake), "handshake send failed");
  auto handshake_response = client.Receive();
  Expect(handshake_response.has_value(), "handshake receive failed");
  Expect(handshake_response->request_id == 1, "handshake request id mismatch");
  auto parsed_handshake =
      azookey::ipc::ParseHandshakeResponse(handshake_response->payload_json);
  Expect(parsed_handshake.has_value(), "handshake response parse failed");
  Expect(parsed_handshake->accepted, "handshake should be accepted");
  Expect(parsed_handshake->host_version == "test-host", "host version mismatch");

  azookey::ipc::PingPayload ping_payload;
  ping_payload.nonce = 98765;
  ping_payload.t_ms = 111;

  azookey::ipc::Envelope ping;
  ping.request_id = 2;
  ping.trace_id = "trace-ping";
  ping.type = azookey::ipc::MessageType::Ping;
  ping.payload_json = azookey::ipc::BuildPing(ping_payload);

  Expect(client.Send(ping), "ping send failed");
  auto ping_response = client.Receive();
  Expect(ping_response.has_value(), "ping receive failed");
  auto parsed_ping = azookey::ipc::ParsePing(ping_response->payload_json);
  Expect(parsed_ping.has_value(), "ping response parse failed");
  Expect(parsed_ping->nonce == 98765, "ping nonce mismatch");
  Expect(parsed_ping->t_ms == 123456, "ping timestamp mismatch");

  azookey::ipc::QueryCandidatesRequest query_payload;
  query_payload.reading = "にほんご";
  query_payload.max_candidates = 5;
  query_payload.live = true;

  azookey::ipc::Envelope query;
  query.request_id = 3;
  query.trace_id = "trace-query";
  query.type = azookey::ipc::MessageType::QueryCandidates;
  query.payload_json = azookey::ipc::BuildQueryCandidatesRequest(query_payload);

  Expect(client.Send(query), "query send failed");
  auto query_response = client.Receive();
  Expect(query_response.has_value(), "query receive failed");
  Expect(query_response->request_id == 3, "query request id mismatch");
  auto parsed_query =
      azookey::ipc::ParseQueryCandidatesResponse(query_response->payload_json);
  Expect(parsed_query.has_value(), "query response parse failed");
  Expect(parsed_query->candidates.size() == 1, "query candidate count mismatch");
  Expect(parsed_query->candidates.front().surface == "日本語",
         "query candidate surface mismatch");
  Expect(parsed_query->candidates.front().reading == "にほんご",
         "query candidate reading mismatch");

  client.Disconnect();
  server.Stop();
  Expect(!server.IsRunning(), "server should be stopped");
  Expect(handled.load() == 3, "handler count mismatch");
  return 0;
#endif
}

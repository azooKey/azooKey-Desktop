#include <stdexcept>
#include <string>

#include "azookey/ipc/Json.h"
#include "azookey/ipc/Payloads.h"

static void Expect(bool cond, const char* msg) {
  if (!cond) throw std::runtime_error(msg);
}

static void TestJsonEscapeAndRoundTrip() {
  const std::string src = "「\"日本\\n語\"」\t";
  const auto escaped = azookey::ipc::json::EscapeString(src);
  Expect(escaped.find("\\\"") != std::string::npos, "quote not escaped");
  Expect(escaped.find("\\n") != std::string::npos, "newline not escaped");
  Expect(escaped.find("\\u0001") != std::string::npos, "control not escaped");

  const std::string wrapped = std::string("\"") + escaped + "\"";
  auto v = azookey::ipc::json::Parse(wrapped);
  Expect(v.has_value() && v->IsString(), "parse round trip failed");
  Expect(v->AsString() == src, "escape round trip mismatch");
}

static void TestHandshake() {
  azookey::ipc::HandshakeRequest req;
  req.tip_version = "0.1.0";
  req.protocol_version = 1;
  req.capabilities = {"live_conversion", "cancel"};
  auto json = azookey::ipc::BuildHandshakeRequest(req);
  auto parsed = azookey::ipc::ParseHandshakeRequest(json);
  Expect(parsed.has_value(), "handshake req parse");
  Expect(parsed->tip_version == "0.1.0", "handshake tip_version");
  Expect(parsed->capabilities.size() == 2, "handshake caps size");
  Expect(parsed->capabilities[0] == "live_conversion", "handshake cap[0]");

  azookey::ipc::HandshakeResponse res;
  res.host_version = "0.1.0";
  res.accepted = true;
  res.model_loaded = false;
  auto json2 = azookey::ipc::BuildHandshakeResponse(res);
  auto parsed2 = azookey::ipc::ParseHandshakeResponse(json2);
  Expect(parsed2.has_value() && parsed2->accepted && !parsed2->model_loaded,
         "handshake response");
}

static void TestPing() {
  azookey::ipc::PingPayload p;
  p.nonce = 12345;
  p.t_ms = 1700000000123ULL;
  auto json = azookey::ipc::BuildPing(p);
  auto parsed = azookey::ipc::ParsePing(json);
  Expect(parsed.has_value(), "ping parse");
  Expect(parsed->nonce == 12345, "ping nonce");
  Expect(parsed->t_ms == 1700000000123ULL, "ping t_ms");
}

static void TestHealth() {
  azookey::ipc::HealthPayload p;
  p.status = "degraded";
  p.backend = "cpu";
  p.model_loaded = false;
  p.vram_mb = 0;
  p.last_error = "no cuda runtime";
  auto json = azookey::ipc::BuildHealth(p);
  auto parsed = azookey::ipc::ParseHealth(json);
  Expect(parsed.has_value(), "health parse");
  Expect(parsed->status == "degraded", "health status");
  Expect(parsed->backend == "cpu", "health backend");
  Expect(parsed->last_error.has_value(), "health last_error");
  Expect(*parsed->last_error == "no cuda runtime", "health last_error value");
}

static void TestLoadModel() {
  azookey::ipc::LoadModelRequest req;
  req.path = "C:\\models\\zenz.gguf";
  req.backend = "cuda";
  req.n_gpu_layers = 32;
  auto json = azookey::ipc::BuildLoadModelRequest(req);
  auto parsed = azookey::ipc::ParseLoadModelRequest(json);
  Expect(parsed.has_value(), "loadmodel req parse");
  Expect(parsed->path == "C:\\models\\zenz.gguf", "loadmodel path");
  Expect(parsed->n_gpu_layers.has_value() && *parsed->n_gpu_layers == 32,
         "loadmodel n_gpu_layers");

  azookey::ipc::LoadModelResponse res;
  res.ok = false;
  res.error = "file not found";
  auto json2 = azookey::ipc::BuildLoadModelResponse(res);
  auto parsed2 = azookey::ipc::ParseLoadModelResponse(json2);
  Expect(parsed2.has_value() && !parsed2->ok, "loadmodel res ok");
  Expect(parsed2->error.has_value(), "loadmodel res error");
}

static void TestQueryCandidates() {
  azookey::ipc::QueryCandidatesRequest req;
  req.reading = "にほんご";
  req.left_context = "私は";
  req.max_candidates = 5;
  req.live = true;
  auto json = azookey::ipc::BuildQueryCandidatesRequest(req);
  auto parsed = azookey::ipc::ParseQueryCandidatesRequest(json);
  Expect(parsed.has_value(), "query req parse");
  Expect(parsed->reading == "にほんご", "query reading");
  Expect(parsed->max_candidates == 5, "query max");
  Expect(parsed->live, "query live");

  azookey::ipc::QueryCandidatesResponse res;
  res.candidates = {
      {"日本語", "にほんご", 1.0, "static-dict"},
      {"日本五", "にほんご", 0.3, "fallback"},
  };
  res.partial = false;
  auto json2 = azookey::ipc::BuildQueryCandidatesResponse(res);
  auto parsed2 = azookey::ipc::ParseQueryCandidatesResponse(json2);
  Expect(parsed2.has_value(), "query res parse");
  Expect(parsed2->candidates.size() == 2, "query res size");
  Expect(parsed2->candidates[0].surface == "日本語", "query res top");
  Expect(parsed2->candidates[0].score == 1.0, "query res score");
}

static void TestCancel() {
  azookey::ipc::CancelPayload p;
  p.target_request_id = 7777;
  auto json = azookey::ipc::BuildCancel(p);
  auto parsed = azookey::ipc::ParseCancel(json);
  Expect(parsed.has_value(), "cancel parse");
  Expect(parsed->target_request_id == 7777, "cancel id");
}

static void TestCommitObservation() {
  azookey::ipc::CommitObservationRequest req;
  req.reading = "にほんご";
  req.chosen = {"日本語", "にほんご", 1.0, "user"};
  req.shown = {
      {"日本語", "にほんご", 1.0, "static-dict"},
      {"二本後", "にほんご", 0.1, "fallback"},
  };
  req.left_context = "";
  req.timestamp_ms = 1700000000123ULL;
  auto json = azookey::ipc::BuildCommitObservationRequest(req);
  auto parsed = azookey::ipc::ParseCommitObservationRequest(json);
  Expect(parsed.has_value(), "commit parse");
  Expect(parsed->chosen.surface == "日本語", "commit chosen");
  Expect(parsed->shown.size() == 2, "commit shown size");
  Expect(parsed->timestamp_ms == 1700000000123ULL, "commit timestamp");
}

static void TestUserWord() {
  azookey::ipc::AddUserWordRequest add;
  add.word = "azooKey";
  add.ruby = "あずきい";
  add.cid = 1285;
  add.value = -5.0;
  auto json = azookey::ipc::BuildAddUserWordRequest(add);
  auto parsed = azookey::ipc::ParseAddUserWordRequest(json);
  Expect(parsed.has_value(), "adduserword parse");
  Expect(parsed->word == "azooKey", "adduserword word");
  Expect(parsed->cid.has_value() && *parsed->cid == 1285, "adduserword cid");
  Expect(parsed->value.has_value(), "adduserword value");

  azookey::ipc::RemoveUserWordRequest rm;
  rm.word = "azooKey";
  rm.ruby = "あずきい";
  auto json2 = azookey::ipc::BuildRemoveUserWordRequest(rm);
  auto parsed2 = azookey::ipc::ParseRemoveUserWordRequest(json2);
  Expect(parsed2.has_value(), "removeuserword parse");
  Expect(parsed2->word == "azooKey", "removeuserword word");
}

static void TestMalformedRejection() {
  Expect(!azookey::ipc::ParseHandshakeRequest("not json").has_value(),
         "handshake malformed must reject");
  Expect(!azookey::ipc::ParseQueryCandidatesRequest("{}").has_value(),
         "query without reading must reject");
  Expect(!azookey::ipc::ParseCancel("{}").has_value(),
         "cancel without target must reject");
}

int main() {
  TestJsonEscapeAndRoundTrip();
  TestHandshake();
  TestPing();
  TestHealth();
  TestLoadModel();
  TestQueryCandidates();
  TestCancel();
  TestCommitObservation();
  TestUserWord();
  TestMalformedRejection();
  return 0;
}

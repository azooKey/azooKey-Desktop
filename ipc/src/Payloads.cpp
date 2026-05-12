#include "azookey/ipc/Payloads.h"

#include "azookey/ipc/Json.h"

namespace azookey::ipc {

namespace {

namespace j = ::azookey::ipc::json;

j::Value CandidateToJson(const CandidateField& c) {
  j::Object o;
  o.emplace("surface", j::Value(c.surface));
  o.emplace("reading", j::Value(c.reading));
  o.emplace("score", j::Value(c.score));
  o.emplace("source", j::Value(c.source));
  return j::Value(std::move(o));
}

std::optional<CandidateField> CandidateFromJson(const j::Value& v) {
  if (!v.IsObject()) return std::nullopt;
  CandidateField c;
  auto surface = v.GetString("surface");
  auto reading = v.GetString("reading");
  auto score = v.GetNumber("score");
  auto source = v.GetString("source");
  if (!surface || !reading) return std::nullopt;
  c.surface = std::move(*surface);
  c.reading = std::move(*reading);
  c.score = score.value_or(0.0);
  c.source = source.value_or(std::string());
  return c;
}

std::optional<j::Value> ParseObject(const std::string& s) {
  auto v = j::Parse(s);
  if (!v || !v->IsObject()) return std::nullopt;
  return v;
}

}  // namespace

// -------- Handshake --------

std::string BuildHandshakeRequest(const HandshakeRequest& p) {
  j::Object o;
  o.emplace("tip_version", j::Value(p.tip_version));
  o.emplace("protocol_version", j::Value(static_cast<double>(p.protocol_version)));
  j::Array caps;
  for (const auto& c : p.capabilities) caps.emplace_back(j::Value(c));
  o.emplace("capabilities", j::Value(std::move(caps)));
  return j::Stringify(j::Value(std::move(o)));
}

std::optional<HandshakeRequest> ParseHandshakeRequest(const std::string& json) {
  auto v = ParseObject(json);
  if (!v) return std::nullopt;
  HandshakeRequest p;
  auto tip = v->GetString("tip_version");
  auto pv = v->GetInt("protocol_version");
  if (!tip) return std::nullopt;
  p.tip_version = std::move(*tip);
  p.protocol_version = static_cast<int>(pv.value_or(1));
  if (const auto* caps = v->GetArray("capabilities")) {
    for (const auto& e : *caps) {
      if (e.IsString()) p.capabilities.push_back(e.AsString());
    }
  }
  return p;
}

std::string BuildHandshakeResponse(const HandshakeResponse& p) {
  j::Object o;
  o.emplace("host_version", j::Value(p.host_version));
  o.emplace("protocol_version", j::Value(static_cast<double>(p.protocol_version)));
  o.emplace("accepted", j::Value(p.accepted));
  o.emplace("model_loaded", j::Value(p.model_loaded));
  return j::Stringify(j::Value(std::move(o)));
}

std::optional<HandshakeResponse> ParseHandshakeResponse(const std::string& json) {
  auto v = ParseObject(json);
  if (!v) return std::nullopt;
  HandshakeResponse p;
  auto host = v->GetString("host_version");
  if (!host) return std::nullopt;
  p.host_version = std::move(*host);
  p.protocol_version = static_cast<int>(v->GetInt("protocol_version").value_or(1));
  p.accepted = v->GetBool("accepted").value_or(false);
  p.model_loaded = v->GetBool("model_loaded").value_or(false);
  return p;
}

// -------- Ping --------

std::string BuildPing(const PingPayload& p) {
  j::Object o;
  o.emplace("nonce", j::Value(static_cast<double>(p.nonce)));
  o.emplace("t_ms", j::Value(static_cast<double>(p.t_ms)));
  return j::Stringify(j::Value(std::move(o)));
}

std::optional<PingPayload> ParsePing(const std::string& json) {
  auto v = ParseObject(json);
  if (!v) return std::nullopt;
  PingPayload p;
  auto nonce = v->GetUInt("nonce");
  auto t_ms = v->GetUInt("t_ms");
  if (!nonce) return std::nullopt;
  p.nonce = *nonce;
  p.t_ms = t_ms.value_or(0);
  return p;
}

// -------- Health --------

std::string BuildHealth(const HealthPayload& p) {
  j::Object o;
  o.emplace("status", j::Value(p.status));
  o.emplace("backend", j::Value(p.backend));
  o.emplace("model_loaded", j::Value(p.model_loaded));
  if (p.vram_mb) o.emplace("vram_mb", j::Value(static_cast<double>(*p.vram_mb)));
  if (p.last_error) o.emplace("last_error", j::Value(*p.last_error));
  return j::Stringify(j::Value(std::move(o)));
}

std::optional<HealthPayload> ParseHealth(const std::string& json) {
  auto v = ParseObject(json);
  if (!v) return std::nullopt;
  HealthPayload p;
  auto status = v->GetString("status");
  auto backend = v->GetString("backend");
  if (!status || !backend) return std::nullopt;
  p.status = std::move(*status);
  p.backend = std::move(*backend);
  p.model_loaded = v->GetBool("model_loaded").value_or(false);
  if (auto vram = v->GetUInt("vram_mb")) p.vram_mb = static_cast<uint32_t>(*vram);
  if (auto err = v->GetString("last_error")) p.last_error = std::move(*err);
  return p;
}

// -------- LoadModel --------

std::string BuildLoadModelRequest(const LoadModelRequest& p) {
  j::Object o;
  o.emplace("path", j::Value(p.path));
  o.emplace("backend", j::Value(p.backend));
  if (p.n_gpu_layers) o.emplace("n_gpu_layers", j::Value(static_cast<double>(*p.n_gpu_layers)));
  return j::Stringify(j::Value(std::move(o)));
}

std::optional<LoadModelRequest> ParseLoadModelRequest(const std::string& json) {
  auto v = ParseObject(json);
  if (!v) return std::nullopt;
  LoadModelRequest p;
  auto path = v->GetString("path");
  auto backend = v->GetString("backend");
  if (!path || !backend) return std::nullopt;
  p.path = std::move(*path);
  p.backend = std::move(*backend);
  if (auto n = v->GetInt("n_gpu_layers")) p.n_gpu_layers = static_cast<int32_t>(*n);
  return p;
}

std::string BuildLoadModelResponse(const LoadModelResponse& p) {
  j::Object o;
  o.emplace("ok", j::Value(p.ok));
  if (p.error) o.emplace("error", j::Value(*p.error));
  return j::Stringify(j::Value(std::move(o)));
}

std::optional<LoadModelResponse> ParseLoadModelResponse(const std::string& json) {
  auto v = ParseObject(json);
  if (!v) return std::nullopt;
  LoadModelResponse p;
  auto ok = v->GetBool("ok");
  if (!ok) return std::nullopt;
  p.ok = *ok;
  if (auto err = v->GetString("error")) p.error = std::move(*err);
  return p;
}

// -------- QueryCandidates --------

std::string BuildQueryCandidatesRequest(const QueryCandidatesRequest& p) {
  j::Object o;
  o.emplace("reading", j::Value(p.reading));
  o.emplace("left_context", j::Value(p.left_context));
  o.emplace("max_candidates", j::Value(static_cast<double>(p.max_candidates)));
  o.emplace("live", j::Value(p.live));
  return j::Stringify(j::Value(std::move(o)));
}

std::optional<QueryCandidatesRequest> ParseQueryCandidatesRequest(const std::string& json) {
  auto v = ParseObject(json);
  if (!v) return std::nullopt;
  QueryCandidatesRequest p;
  auto reading = v->GetString("reading");
  if (!reading) return std::nullopt;
  p.reading = std::move(*reading);
  p.left_context = v->GetString("left_context").value_or(std::string());
  if (auto m = v->GetUInt("max_candidates")) p.max_candidates = static_cast<uint32_t>(*m);
  p.live = v->GetBool("live").value_or(false);
  return p;
}

std::string BuildQueryCandidatesResponse(const QueryCandidatesResponse& p) {
  j::Object o;
  j::Array arr;
  for (const auto& c : p.candidates) arr.push_back(CandidateToJson(c));
  o.emplace("candidates", j::Value(std::move(arr)));
  o.emplace("partial", j::Value(p.partial));
  return j::Stringify(j::Value(std::move(o)));
}

std::optional<QueryCandidatesResponse> ParseQueryCandidatesResponse(const std::string& json) {
  auto v = ParseObject(json);
  if (!v) return std::nullopt;
  QueryCandidatesResponse p;
  if (const auto* arr = v->GetArray("candidates")) {
    for (const auto& e : *arr) {
      if (auto c = CandidateFromJson(e)) p.candidates.push_back(std::move(*c));
    }
  }
  p.partial = v->GetBool("partial").value_or(false);
  return p;
}

// -------- Cancel --------

std::string BuildCancel(const CancelPayload& p) {
  j::Object o;
  o.emplace("target_request_id", j::Value(static_cast<double>(p.target_request_id)));
  return j::Stringify(j::Value(std::move(o)));
}

std::optional<CancelPayload> ParseCancel(const std::string& json) {
  auto v = ParseObject(json);
  if (!v) return std::nullopt;
  CancelPayload p;
  auto id = v->GetUInt("target_request_id");
  if (!id) return std::nullopt;
  p.target_request_id = *id;
  return p;
}

// -------- CommitObservation --------

std::string BuildCommitObservationRequest(const CommitObservationRequest& p) {
  j::Object o;
  o.emplace("reading", j::Value(p.reading));
  o.emplace("chosen", CandidateToJson(p.chosen));
  j::Array shown;
  for (const auto& c : p.shown) shown.push_back(CandidateToJson(c));
  o.emplace("shown", j::Value(std::move(shown)));
  o.emplace("left_context", j::Value(p.left_context));
  o.emplace("timestamp_ms", j::Value(static_cast<double>(p.timestamp_ms)));
  return j::Stringify(j::Value(std::move(o)));
}

std::optional<CommitObservationRequest> ParseCommitObservationRequest(const std::string& json) {
  auto v = ParseObject(json);
  if (!v) return std::nullopt;
  CommitObservationRequest p;
  auto reading = v->GetString("reading");
  if (!reading) return std::nullopt;
  p.reading = std::move(*reading);
  const auto* chosen = v->Find("chosen");
  if (!chosen) return std::nullopt;
  auto cand = CandidateFromJson(*chosen);
  if (!cand) return std::nullopt;
  p.chosen = std::move(*cand);
  if (const auto* shown = v->GetArray("shown")) {
    for (const auto& e : *shown) {
      if (auto c = CandidateFromJson(e)) p.shown.push_back(std::move(*c));
    }
  }
  p.left_context = v->GetString("left_context").value_or(std::string());
  p.timestamp_ms = v->GetUInt("timestamp_ms").value_or(0);
  return p;
}

std::string BuildCommitObservationResponse(const CommitObservationResponse& p) {
  j::Object o;
  o.emplace("ok", j::Value(p.ok));
  return j::Stringify(j::Value(std::move(o)));
}

std::optional<CommitObservationResponse> ParseCommitObservationResponse(const std::string& json) {
  auto v = ParseObject(json);
  if (!v) return std::nullopt;
  CommitObservationResponse p;
  auto ok = v->GetBool("ok");
  if (!ok) return std::nullopt;
  p.ok = *ok;
  return p;
}

// -------- AddUserWord / RemoveUserWord --------

std::string BuildAddUserWordRequest(const AddUserWordRequest& p) {
  j::Object o;
  o.emplace("word", j::Value(p.word));
  o.emplace("ruby", j::Value(p.ruby));
  if (p.cid) o.emplace("cid", j::Value(static_cast<double>(*p.cid)));
  if (p.mid) o.emplace("mid", j::Value(static_cast<double>(*p.mid)));
  if (p.value) o.emplace("value", j::Value(*p.value));
  return j::Stringify(j::Value(std::move(o)));
}

std::optional<AddUserWordRequest> ParseAddUserWordRequest(const std::string& json) {
  auto v = ParseObject(json);
  if (!v) return std::nullopt;
  AddUserWordRequest p;
  auto word = v->GetString("word");
  auto ruby = v->GetString("ruby");
  if (!word || !ruby) return std::nullopt;
  p.word = std::move(*word);
  p.ruby = std::move(*ruby);
  if (auto cid = v->GetInt("cid")) p.cid = static_cast<int32_t>(*cid);
  if (auto mid = v->GetInt("mid")) p.mid = static_cast<int32_t>(*mid);
  if (auto val = v->GetNumber("value")) p.value = *val;
  return p;
}

std::string BuildAddUserWordResponse(const AddUserWordResponse& p) {
  j::Object o;
  o.emplace("ok", j::Value(p.ok));
  if (p.generated_id) o.emplace("generated_id", j::Value(*p.generated_id));
  return j::Stringify(j::Value(std::move(o)));
}

std::optional<AddUserWordResponse> ParseAddUserWordResponse(const std::string& json) {
  auto v = ParseObject(json);
  if (!v) return std::nullopt;
  AddUserWordResponse p;
  auto ok = v->GetBool("ok");
  if (!ok) return std::nullopt;
  p.ok = *ok;
  if (auto id = v->GetString("generated_id")) p.generated_id = std::move(*id);
  return p;
}

std::string BuildRemoveUserWordRequest(const RemoveUserWordRequest& p) {
  j::Object o;
  o.emplace("word", j::Value(p.word));
  o.emplace("ruby", j::Value(p.ruby));
  return j::Stringify(j::Value(std::move(o)));
}

std::optional<RemoveUserWordRequest> ParseRemoveUserWordRequest(const std::string& json) {
  auto v = ParseObject(json);
  if (!v) return std::nullopt;
  RemoveUserWordRequest p;
  auto word = v->GetString("word");
  auto ruby = v->GetString("ruby");
  if (!word || !ruby) return std::nullopt;
  p.word = std::move(*word);
  p.ruby = std::move(*ruby);
  return p;
}

std::string BuildRemoveUserWordResponse(const RemoveUserWordResponse& p) {
  j::Object o;
  o.emplace("ok", j::Value(p.ok));
  return j::Stringify(j::Value(std::move(o)));
}

std::optional<RemoveUserWordResponse> ParseRemoveUserWordResponse(const std::string& json) {
  auto v = ParseObject(json);
  if (!v) return std::nullopt;
  RemoveUserWordResponse p;
  auto ok = v->GetBool("ok");
  if (!ok) return std::nullopt;
  p.ok = *ok;
  return p;
}

}  // namespace azookey::ipc

#include "azookey/host/Dispatcher.h"

#include <atomic>
#include <chrono>

#include "azookey/ipc/Payloads.h"

namespace azookey::host {

namespace {

uint64_t NowMs() {
  using namespace std::chrono;
  return static_cast<uint64_t>(
      duration_cast<milliseconds>(system_clock::now().time_since_epoch()).count());
}

uint64_t NowSec() {
  using namespace std::chrono;
  return static_cast<uint64_t>(
      duration_cast<seconds>(system_clock::now().time_since_epoch()).count());
}

ipc::Envelope MakeResponse(const ipc::Envelope& req, std::string payload_json) {
  ipc::Envelope r;
  r.version = req.version;
  r.request_id = req.request_id;
  r.trace_id = req.trace_id;
  r.type = req.type;
  r.payload_json = std::move(payload_json);
  return r;
}

ipc::CandidateField ToField(const core::Candidate& c) {
  ipc::CandidateField f;
  f.surface = c.surface;
  f.reading = c.reading;
  f.score = c.score;
  f.source = c.debug_info;
  return f;
}

}  // namespace

Dispatcher::Dispatcher(InferenceEngine* engine, RequestScheduler* scheduler,
                       learning::UserDictionary* user_dict, DispatcherConfig config)
    : engine_(engine), scheduler_(scheduler), user_dict_(user_dict), config_(std::move(config)) {}

std::optional<ipc::Envelope> Dispatcher::Dispatch(const ipc::Envelope& req) {
  switch (req.type) {
    case ipc::MessageType::Handshake: return HandleHandshake(req);
    case ipc::MessageType::Ping: return HandlePing(req);
    case ipc::MessageType::Health: return HandleHealth(req);
    case ipc::MessageType::LoadModel: return HandleLoadModel(req);
    case ipc::MessageType::QueryCandidates: return HandleQueryCandidates(req);
    case ipc::MessageType::Cancel: HandleCancel(req); return std::nullopt;
    case ipc::MessageType::CommitObservation: return HandleCommitObservation(req);
    case ipc::MessageType::AddUserWord: return HandleAddUserWord(req);
    case ipc::MessageType::RemoveUserWord: return HandleRemoveUserWord(req);
    default: return std::nullopt;
  }
}

std::optional<ipc::Envelope> Dispatcher::HandleHandshake(const ipc::Envelope& req) {
  ipc::HandshakeResponse res;
  res.host_version = config_.host_version;
  res.protocol_version = config_.protocol_version;
  if (auto parsed = ipc::ParseHandshakeRequest(req.payload_json)) {
    res.accepted = parsed->protocol_version == config_.protocol_version;
  } else {
    res.accepted = false;
  }
  res.model_loaded = false;  // until ZenzaiConverter lands (M8) it is mock.
  return MakeResponse(req, ipc::BuildHandshakeResponse(res));
}

std::optional<ipc::Envelope> Dispatcher::HandlePing(const ipc::Envelope& req) {
  auto parsed = ipc::ParsePing(req.payload_json);
  ipc::PingPayload res;
  res.nonce = parsed ? parsed->nonce : 0;
  res.t_ms = NowMs();
  return MakeResponse(req, ipc::BuildPing(res));
}

std::optional<ipc::Envelope> Dispatcher::HandleHealth(const ipc::Envelope& req) {
  ipc::HealthPayload p;
  p.status = "ok";
  p.backend = engine_->backend() == BackendKind::Cuda ? "cuda" : "cpu";
  p.model_loaded = false;
  return MakeResponse(req, ipc::BuildHealth(p));
}

std::optional<ipc::Envelope> Dispatcher::HandleLoadModel(const ipc::Envelope& req) {
  ipc::LoadModelResponse res;
  auto parsed = ipc::ParseLoadModelRequest(req.payload_json);
  if (!parsed) {
    res.ok = false;
    res.error = "invalid LoadModel payload";
  } else {
    res.ok = engine_->LoadModel();  // M8 で実装拡張
    if (!res.ok) res.error = "model load failed";
  }
  return MakeResponse(req, ipc::BuildLoadModelResponse(res));
}

std::optional<ipc::Envelope> Dispatcher::HandleQueryCandidates(const ipc::Envelope& req) {
  auto parsed = ipc::ParseQueryCandidatesRequest(req.payload_json);
  if (!parsed) {
    ipc::QueryCandidatesResponse res;
    res.partial = false;
    return MakeResponse(req, ipc::BuildQueryCandidatesResponse(res));
  }
  scheduler_->MarkLatest(req.request_id);
  std::atomic<bool> cancel{false};
  if (scheduler_->IsCanceled(req.request_id)) cancel.store(true);

  auto candidates = engine_->QueryCandidates(parsed->reading, parsed->left_context,
                                              NowSec(), &cancel);

  if (scheduler_->IsCanceled(req.request_id)) {
    return std::nullopt;  // don't reply to canceled requests
  }

  ipc::QueryCandidatesResponse res;
  for (auto& c : candidates) res.candidates.push_back(ToField(c));
  if (parsed->max_candidates > 0 && res.candidates.size() > parsed->max_candidates) {
    res.candidates.resize(parsed->max_candidates);
  }
  res.partial = false;
  return MakeResponse(req, ipc::BuildQueryCandidatesResponse(res));
}

void Dispatcher::HandleCancel(const ipc::Envelope& req) {
  if (auto parsed = ipc::ParseCancel(req.payload_json)) {
    scheduler_->Cancel(parsed->target_request_id);
  }
}

std::optional<ipc::Envelope> Dispatcher::HandleCommitObservation(const ipc::Envelope& req) {
  ipc::CommitObservationResponse res;
  if (auto parsed = ipc::ParseCommitObservationRequest(req.payload_json)) {
    engine_->CommitObservation(parsed->reading, parsed->chosen.surface, NowSec());
    res.ok = true;
  } else {
    res.ok = false;
  }
  return MakeResponse(req, ipc::BuildCommitObservationResponse(res));
}

std::optional<ipc::Envelope> Dispatcher::HandleAddUserWord(const ipc::Envelope& req) {
  ipc::AddUserWordResponse res;
  if (!user_dict_) {
    res.ok = false;
    return MakeResponse(req, ipc::BuildAddUserWordResponse(res));
  }
  if (auto parsed = ipc::ParseAddUserWordRequest(req.payload_json)) {
    learning::UserWord w;
    w.word = parsed->word;
    w.ruby = parsed->ruby;
    w.cid = parsed->cid;
    w.mid = parsed->mid;
    w.value = parsed->value;
    user_dict_->Add(w);
    user_dict_->Save();
    res.ok = true;
  }
  return MakeResponse(req, ipc::BuildAddUserWordResponse(res));
}

std::optional<ipc::Envelope> Dispatcher::HandleRemoveUserWord(const ipc::Envelope& req) {
  ipc::RemoveUserWordResponse res;
  if (!user_dict_) {
    res.ok = false;
    return MakeResponse(req, ipc::BuildRemoveUserWordResponse(res));
  }
  if (auto parsed = ipc::ParseRemoveUserWordRequest(req.payload_json)) {
    res.ok = user_dict_->Remove(parsed->word, parsed->ruby);
    if (res.ok) user_dict_->Save();
  }
  return MakeResponse(req, ipc::BuildRemoveUserWordResponse(res));
}

}  // namespace azookey::host

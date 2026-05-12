#pragma once

#include <cstdint>
#include <optional>
#include <string>
#include <vector>

namespace azookey::ipc {

struct HandshakeRequest {
  std::string tip_version;
  int protocol_version{1};
  std::vector<std::string> capabilities;
};

struct HandshakeResponse {
  std::string host_version;
  int protocol_version{1};
  bool accepted{false};
  bool model_loaded{false};
};

struct PingPayload {
  uint64_t nonce{};
  uint64_t t_ms{};
};

struct HealthPayload {
  std::string status;             // "ok" | "degraded" | "error"
  std::string backend;            // "cpu" | "cuda" | "directml"
  bool model_loaded{false};
  std::optional<uint32_t> vram_mb;
  std::optional<std::string> last_error;
};

struct LoadModelRequest {
  std::string path;
  std::string backend;            // "cpu" | "cuda" | "directml"
  std::optional<int32_t> n_gpu_layers;
};

struct LoadModelResponse {
  bool ok{false};
  std::optional<std::string> error;
};

struct CandidateField {
  std::string surface;
  std::string reading;
  double score{};
  std::string source;
};

struct QueryCandidatesRequest {
  std::string reading;
  std::string left_context;
  uint32_t max_candidates{10};
  bool live{false};
};

struct QueryCandidatesResponse {
  std::vector<CandidateField> candidates;
  bool partial{false};
};

struct CancelPayload {
  uint64_t target_request_id{};
};

struct CommitObservationRequest {
  std::string reading;
  CandidateField chosen;
  std::vector<CandidateField> shown;
  std::string left_context;
  uint64_t timestamp_ms{};
};

struct CommitObservationResponse {
  bool ok{false};
};

struct AddUserWordRequest {
  std::string word;
  std::string ruby;
  std::optional<int32_t> cid;
  std::optional<int32_t> mid;
  std::optional<double> value;
};

struct AddUserWordResponse {
  bool ok{false};
  std::optional<std::string> generated_id;
};

struct RemoveUserWordRequest {
  std::string word;
  std::string ruby;
};

struct RemoveUserWordResponse {
  bool ok{false};
};

// Builders return the JSON payload string (Envelope.payload_json content).
std::string BuildHandshakeRequest(const HandshakeRequest& p);
std::string BuildHandshakeResponse(const HandshakeResponse& p);
std::string BuildPing(const PingPayload& p);
std::string BuildHealth(const HealthPayload& p);
std::string BuildLoadModelRequest(const LoadModelRequest& p);
std::string BuildLoadModelResponse(const LoadModelResponse& p);
std::string BuildQueryCandidatesRequest(const QueryCandidatesRequest& p);
std::string BuildQueryCandidatesResponse(const QueryCandidatesResponse& p);
std::string BuildCancel(const CancelPayload& p);
std::string BuildCommitObservationRequest(const CommitObservationRequest& p);
std::string BuildCommitObservationResponse(const CommitObservationResponse& p);
std::string BuildAddUserWordRequest(const AddUserWordRequest& p);
std::string BuildAddUserWordResponse(const AddUserWordResponse& p);
std::string BuildRemoveUserWordRequest(const RemoveUserWordRequest& p);
std::string BuildRemoveUserWordResponse(const RemoveUserWordResponse& p);

// Parsers accept the JSON payload string (Envelope.payload_json content).
std::optional<HandshakeRequest> ParseHandshakeRequest(const std::string& json);
std::optional<HandshakeResponse> ParseHandshakeResponse(const std::string& json);
std::optional<PingPayload> ParsePing(const std::string& json);
std::optional<HealthPayload> ParseHealth(const std::string& json);
std::optional<LoadModelRequest> ParseLoadModelRequest(const std::string& json);
std::optional<LoadModelResponse> ParseLoadModelResponse(const std::string& json);
std::optional<QueryCandidatesRequest> ParseQueryCandidatesRequest(const std::string& json);
std::optional<QueryCandidatesResponse> ParseQueryCandidatesResponse(const std::string& json);
std::optional<CancelPayload> ParseCancel(const std::string& json);
std::optional<CommitObservationRequest> ParseCommitObservationRequest(const std::string& json);
std::optional<CommitObservationResponse> ParseCommitObservationResponse(const std::string& json);
std::optional<AddUserWordRequest> ParseAddUserWordRequest(const std::string& json);
std::optional<AddUserWordResponse> ParseAddUserWordResponse(const std::string& json);
std::optional<RemoveUserWordRequest> ParseRemoveUserWordRequest(const std::string& json);
std::optional<RemoveUserWordResponse> ParseRemoveUserWordResponse(const std::string& json);

}  // namespace azookey::ipc

#pragma once

#include <cstdint>
#include <optional>
#include <string>
#include <vector>

namespace azookey::ipc {

enum class MessageType {
  Handshake,
  LoadModel,
  QueryCandidates,
  Cancel,
  CommitObservation,
  AddUserWord,
  RemoveUserWord,
  Ping,
  Health,
  Unknown,
};

struct Envelope {
  int version{1};
  uint64_t request_id{};
  std::string trace_id;
  MessageType type{MessageType::Unknown};
  std::string payload_json;
};

std::string Serialize(const Envelope& env);
std::optional<Envelope> Deserialize(const std::string& json);

std::string TypeToString(MessageType type);
MessageType TypeFromString(const std::string& value);

std::vector<uint8_t> EncodeLengthPrefixed(const std::string& json);
std::optional<std::string> DecodeLengthPrefixed(const std::vector<uint8_t>& bytes);

}  // namespace azookey::ipc

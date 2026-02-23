#include "azookey/ipc/Messages.h"

#include <algorithm>
#include <cctype>
#include <sstream>

namespace azookey::ipc {
namespace {

std::optional<std::string> ExtractString(const std::string& json, const std::string& key) {
  const std::string token = "\"" + key + "\":\"";
  const auto start = json.find(token);
  if (start == std::string::npos) {
    return std::nullopt;
  }
  const auto value_start = start + token.size();
  const auto end = json.find('"', value_start);
  if (end == std::string::npos) {
    return std::nullopt;
  }
  return json.substr(value_start, end - value_start);
}

std::optional<uint64_t> ExtractU64(const std::string& json, const std::string& key) {
  const std::string token = "\"" + key + "\":";
  const auto start = json.find(token);
  if (start == std::string::npos) {
    return std::nullopt;
  }
  auto pos = start + token.size();
  auto end = pos;
  while (end < json.size() && std::isdigit(static_cast<unsigned char>(json[end])) != 0) {
    ++end;
  }
  if (end == pos) {
    return std::nullopt;
  }
  return static_cast<uint64_t>(std::stoull(json.substr(pos, end - pos)));
}

}  // namespace

std::string TypeToString(MessageType type) {
  switch (type) {
    case MessageType::Handshake: return "Handshake";
    case MessageType::LoadModel: return "LoadModel";
    case MessageType::QueryCandidates: return "QueryCandidates";
    case MessageType::Cancel: return "Cancel";
    case MessageType::CommitObservation: return "CommitObservation";
    case MessageType::AddUserWord: return "AddUserWord";
    case MessageType::RemoveUserWord: return "RemoveUserWord";
    case MessageType::Ping: return "Ping";
    case MessageType::Health: return "Health";
    default: return "Unknown";
  }
}

MessageType TypeFromString(const std::string& value) {
  if (value == "Handshake") return MessageType::Handshake;
  if (value == "LoadModel") return MessageType::LoadModel;
  if (value == "QueryCandidates") return MessageType::QueryCandidates;
  if (value == "Cancel") return MessageType::Cancel;
  if (value == "CommitObservation") return MessageType::CommitObservation;
  if (value == "AddUserWord") return MessageType::AddUserWord;
  if (value == "RemoveUserWord") return MessageType::RemoveUserWord;
  if (value == "Ping") return MessageType::Ping;
  if (value == "Health") return MessageType::Health;
  return MessageType::Unknown;
}

std::string Serialize(const Envelope& env) {
  std::ostringstream oss;
  oss << "{"
      << "\"version\":" << env.version << ","
      << "\"request_id\":" << env.request_id << ","
      << "\"trace_id\":\"" << env.trace_id << "\","
      << "\"type\":\"" << TypeToString(env.type) << "\","
      << "\"payload\":" << env.payload_json
      << "}";
  return oss.str();
}

std::optional<Envelope> Deserialize(const std::string& json) {
  auto request_id = ExtractU64(json, "request_id");
  auto type = ExtractString(json, "type");
  auto trace_id = ExtractString(json, "trace_id");
  if (!request_id || !type || !trace_id) {
    return std::nullopt;
  }
  Envelope env;
  env.request_id = *request_id;
  env.type = TypeFromString(*type);
  env.trace_id = *trace_id;
  env.payload_json = "{}";
  return env;
}

std::vector<uint8_t> EncodeLengthPrefixed(const std::string& json) {
  std::vector<uint8_t> bytes(4 + json.size());
  const uint32_t size = static_cast<uint32_t>(json.size());
  bytes[0] = static_cast<uint8_t>(size & 0xFF);
  bytes[1] = static_cast<uint8_t>((size >> 8) & 0xFF);
  bytes[2] = static_cast<uint8_t>((size >> 16) & 0xFF);
  bytes[3] = static_cast<uint8_t>((size >> 24) & 0xFF);
  std::copy(json.begin(), json.end(), bytes.begin() + 4);
  return bytes;
}

std::optional<std::string> DecodeLengthPrefixed(const std::vector<uint8_t>& bytes) {
  if (bytes.size() < 4) {
    return std::nullopt;
  }
  const uint32_t size = static_cast<uint32_t>(bytes[0]) |
                        (static_cast<uint32_t>(bytes[1]) << 8) |
                        (static_cast<uint32_t>(bytes[2]) << 16) |
                        (static_cast<uint32_t>(bytes[3]) << 24);
  if (bytes.size() != size + 4) {
    return std::nullopt;
  }
  return std::string(bytes.begin() + 4, bytes.end());
}

}  // namespace azookey::ipc

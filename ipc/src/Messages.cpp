#include "azookey/ipc/Messages.h"

#include <algorithm>

#include "azookey/ipc/Json.h"

namespace azookey::ipc {

std::string TypeToString(MessageType type) {
  switch (type) {
    case MessageType::Handshake: return "Handshake";
    case MessageType::LoadModel: return "LoadModel";
    case MessageType::QueryCandidates: return "QueryCandidates";
    case MessageType::QueryPredictions: return "QueryPredictions";
    case MessageType::QueryCorrections: return "QueryCorrections";
    case MessageType::Cancel: return "Cancel";
    case MessageType::CommitObservation: return "CommitObservation";
    case MessageType::CommitCorrection: return "CommitCorrection";
    case MessageType::AddUserWord: return "AddUserWord";
    case MessageType::UpdateUserWord: return "UpdateUserWord";
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
  if (value == "QueryPredictions") return MessageType::QueryPredictions;
  if (value == "QueryCorrections") return MessageType::QueryCorrections;
  if (value == "Cancel") return MessageType::Cancel;
  if (value == "CommitObservation") return MessageType::CommitObservation;
  if (value == "CommitCorrection") return MessageType::CommitCorrection;
  if (value == "AddUserWord") return MessageType::AddUserWord;
  if (value == "UpdateUserWord") return MessageType::UpdateUserWord;
  if (value == "RemoveUserWord") return MessageType::RemoveUserWord;
  if (value == "Ping") return MessageType::Ping;
  if (value == "Health") return MessageType::Health;
  return MessageType::Unknown;
}

std::string Serialize(const Envelope& env) {
  json::Object o;
  o.emplace("version", json::Value(static_cast<double>(env.version)));
  o.emplace("request_id", json::Value(static_cast<double>(env.request_id)));
  o.emplace("trace_id", json::Value(env.trace_id));
  o.emplace("type", json::Value(TypeToString(env.type)));
  if (env.payload_json.empty()) {
    o.emplace("payload", json::Value(json::Object{}));
  } else {
    auto parsed = json::Parse(env.payload_json);
    if (parsed) {
      o.emplace("payload", std::move(*parsed));
    } else {
      // Fallback: store the raw payload as a string so the envelope is still
      // well-formed JSON. Callers must avoid malformed payload_json values.
      o.emplace("payload", json::Value(env.payload_json));
    }
  }
  return json::Stringify(json::Value(std::move(o)));
}

std::optional<Envelope> Deserialize(const std::string& json_text) {
  auto v = json::Parse(json_text);
  if (!v || !v->IsObject()) return std::nullopt;
  Envelope env;
  if (auto x = v->GetInt("version")) env.version = static_cast<int>(*x);
  auto request_id = v->GetUInt("request_id");
  auto type = v->GetString("type");
  auto trace_id = v->GetString("trace_id");
  if (!request_id || !type || !trace_id) return std::nullopt;
  env.request_id = *request_id;
  env.type = TypeFromString(*type);
  env.trace_id = std::move(*trace_id);
  if (const auto* p = v->Find("payload")) {
    env.payload_json = json::Stringify(*p);
  } else {
    env.payload_json = "{}";
  }
  return env;
}

std::vector<uint8_t> EncodeLengthPrefixed(const std::string& json_text) {
  std::vector<uint8_t> bytes(4 + json_text.size());
  const uint32_t size = static_cast<uint32_t>(json_text.size());
  bytes[0] = static_cast<uint8_t>(size & 0xFF);
  bytes[1] = static_cast<uint8_t>((size >> 8) & 0xFF);
  bytes[2] = static_cast<uint8_t>((size >> 16) & 0xFF);
  bytes[3] = static_cast<uint8_t>((size >> 24) & 0xFF);
  std::copy(json_text.begin(), json_text.end(), bytes.begin() + 4);
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

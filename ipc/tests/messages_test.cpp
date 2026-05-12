#include <stdexcept>
#include <string>

#include "azookey/ipc/Messages.h"

static void Expect(bool cond, const char* msg) {
  if (!cond) throw std::runtime_error(msg);
}

int main() {
  // Envelope round trip preserves request_id, type, trace_id and the parsed
  // payload subtree.
  azookey::ipc::Envelope env;
  env.request_id = 42;
  env.trace_id = "t1";
  env.type = azookey::ipc::MessageType::QueryCandidates;
  env.payload_json = "{\"reading\":\"にほん\",\"max_candidates\":7}";

  const auto json = azookey::ipc::Serialize(env);
  auto decoded = azookey::ipc::Deserialize(json);
  Expect(decoded.has_value(), "deserialize failed");
  Expect(decoded->request_id == 42, "request id mismatch");
  Expect(decoded->trace_id == "t1", "trace id mismatch");
  Expect(decoded->type == azookey::ipc::MessageType::QueryCandidates, "type mismatch");
  Expect(decoded->payload_json.find("にほん") != std::string::npos,
         "payload reading not preserved");
  Expect(decoded->payload_json.find("max_candidates") != std::string::npos,
         "payload max_candidates not preserved");

  // Re-serializing the decoded envelope must remain decodable.
  const auto rejson = azookey::ipc::Serialize(*decoded);
  auto redecoded = azookey::ipc::Deserialize(rejson);
  Expect(redecoded.has_value(), "second deserialize failed");
  Expect(redecoded->payload_json == decoded->payload_json,
         "payload not stable across re-serialize");

  // Length-prefixed framing round trip.
  auto lp = azookey::ipc::EncodeLengthPrefixed(json);
  auto restored = azookey::ipc::DecodeLengthPrefixed(lp);
  Expect(restored.has_value(), "length-prefix decode failed");
  Expect(*restored == json, "length-prefix roundtrip failed");

  // Malformed JSON must return nullopt instead of crashing.
  Expect(!azookey::ipc::Deserialize("not json").has_value(),
         "malformed input should fail to deserialize");
  return 0;
}

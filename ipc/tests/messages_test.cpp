#include <stdexcept>

#include "azookey/ipc/Messages.h"

static void Expect(bool cond, const char* msg) {
  if (!cond) throw std::runtime_error(msg);
}

int main() {
  azookey::ipc::Envelope env;
  env.request_id = 42;
  env.trace_id = "t1";
  env.type = azookey::ipc::MessageType::QueryCandidates;
  env.payload_json = "{}";

  const auto json = azookey::ipc::Serialize(env);
  auto decoded = azookey::ipc::Deserialize(json);
  Expect(decoded.has_value(), "deserialize failed");
  Expect(decoded->request_id == 42, "request id mismatch");

  auto lp = azookey::ipc::EncodeLengthPrefixed(json);
  auto restored = azookey::ipc::DecodeLengthPrefixed(lp);
  Expect(restored.has_value(), "length-prefix decode failed");
  Expect(*restored == json, "length-prefix roundtrip failed");
  return 0;
}

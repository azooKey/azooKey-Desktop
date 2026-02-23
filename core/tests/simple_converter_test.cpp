#include <stdexcept>
#include <string>

#include "azookey/core/SimpleConverter.h"

int RunRomajiTests();

void Expect(bool cond, const char* message) {
  if (!cond) {
    throw std::runtime_error(message);
  }
}

int main() {
  RunRomajiTests();

  azookey::core::SimpleConverter converter;
  const auto candidates = converter.Convert("にほん", "");
  Expect(candidates.size() >= 3, "expected 3+ candidates");
  Expect(candidates.front().surface == "日本", "expected 日本 as top candidate");

  converter.Learn("二本", "にほん");
  const auto relearned = converter.Convert("にほん", "");
  Expect(relearned.size() >= 3, "expected candidates after learning");

  return 0;
}

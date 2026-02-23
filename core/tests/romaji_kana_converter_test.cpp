#include <stdexcept>
#include <string>

#include "azookey/core/RomajiKanaConverter.h"

void ExpectEq(const std::string& actual, const std::string& expected, const char* message) {
  if (actual != expected) {
    throw std::runtime_error(std::string(message) + " expected='" + expected + "' actual='" + actual + "'");
  }
}

int main();

int RunRomajiTests() {
  azookey::core::RomajiKanaConverter converter;

  std::string out;
  for (char c : std::string("konnichiha")) {
    out += converter.Feed(c);
  }
  out += converter.Flush();
  ExpectEq(out, "こんにちは", "konnichiha");

  converter.Reset();
  out.clear();
  for (char c : std::string("gakkou")) {
    out += converter.Feed(c);
  }
  out += converter.Flush();
  ExpectEq(out, "がっこう", "gakkou");

  return 0;
}

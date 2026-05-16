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
  for (char c : std::string("nani")) {
    out += converter.Feed(c);
  }
  out += converter.Flush();
  ExpectEq(out, "なに", "nani");

  converter.Reset();
  out.clear();
  for (char c : std::string("gakkou")) {
    out += converter.Feed(c);
  }
  out += converter.Flush();
  ExpectEq(out, "がっこう", "gakkou");

  converter.Reset();
  out.clear();
  for (char c : std::string("konn")) {
    out += converter.Feed(c);
  }
  out += converter.Flush();
  ExpectEq(out, "こん", "konn flush");

  ExpectEq(azookey::core::RomajiKanaConverter::Preview("k"), "k", "preview k");
  ExpectEq(azookey::core::RomajiKanaConverter::Preview("ka"), "か", "preview ka");
  ExpectEq(azookey::core::RomajiKanaConverter::Preview("kan"), "かn", "preview kan");
  ExpectEq(azookey::core::RomajiKanaConverter::Preview("na"), "な", "preview na");
  ExpectEq(azookey::core::RomajiKanaConverter::Preview("konn"), "こん", "preview konn");
  ExpectEq(azookey::core::RomajiKanaConverter::Preview("konnichiha"), "こんにちは",
           "preview konnichiha");
  ExpectEq(azookey::core::RomajiKanaConverter::Preview("gakkou"), "がっこう",
           "preview gakkou");

  ExpectEq(azookey::core::RomajiKanaConverter::ConvertForCommit("kan"), "かん",
           "commit kan");
  ExpectEq(azookey::core::RomajiKanaConverter::ConvertForCommit("na"), "な",
           "commit na");
  ExpectEq(azookey::core::RomajiKanaConverter::ConvertForCommit("konn"), "こん",
           "commit konn");

  return 0;
}

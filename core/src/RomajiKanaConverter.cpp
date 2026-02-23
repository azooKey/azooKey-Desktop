#include "azookey/core/RomajiKanaConverter.h"

#include <algorithm>
#include <cctype>
#include <string>
#include <unordered_map>

namespace azookey::core {
namespace {

const std::unordered_map<std::string, std::string> kRomajiMap = {
    {"a", "あ"},   {"i", "い"},   {"u", "う"},    {"e", "え"},   {"o", "お"},
    {"ka", "か"},  {"ki", "き"},  {"ku", "く"},   {"ke", "け"},  {"ko", "こ"},
    {"sa", "さ"},  {"shi", "し"}, {"su", "す"},   {"se", "せ"},  {"so", "そ"},
    {"ta", "た"},  {"chi", "ち"}, {"tsu", "つ"},  {"te", "て"},  {"to", "と"},
    {"na", "な"},  {"ni", "に"},  {"nu", "ぬ"},   {"ne", "ね"},  {"no", "の"},
    {"ha", "は"},  {"hi", "ひ"},  {"fu", "ふ"},   {"he", "へ"},  {"ho", "ほ"},
    {"ma", "ま"},  {"mi", "み"},  {"mu", "む"},   {"me", "め"},  {"mo", "も"},
    {"ya", "や"},  {"yu", "ゆ"},  {"yo", "よ"},
    {"ra", "ら"},  {"ri", "り"},  {"ru", "る"},   {"re", "れ"},  {"ro", "ろ"},
    {"wa", "わ"},  {"wo", "を"},
    {"ga", "が"},  {"gi", "ぎ"},  {"gu", "ぐ"},   {"ge", "げ"},  {"go", "ご"},
    {"za", "ざ"},  {"ji", "じ"},  {"zu", "ず"},   {"ze", "ぜ"},  {"zo", "ぞ"},
    {"da", "だ"},  {"de", "で"},  {"do", "ど"},
    {"ba", "ば"},  {"bi", "び"},  {"bu", "ぶ"},   {"be", "べ"},  {"bo", "ぼ"},
    {"pa", "ぱ"},  {"pi", "ぴ"},  {"pu", "ぷ"},   {"pe", "ぺ"},  {"po", "ぽ"},
    {"kya", "きゃ"}, {"kyu", "きゅ"}, {"kyo", "きょ"},
    {"sha", "しゃ"}, {"shu", "しゅ"}, {"sho", "しょ"},
    {"cha", "ちゃ"}, {"chu", "ちゅ"}, {"cho", "ちょ"},
    {"nya", "にゃ"}, {"nyu", "にゅ"}, {"nyo", "にょ"},
    {"hya", "ひゃ"}, {"hyu", "ひゅ"}, {"hyo", "ひょ"},
    {"mya", "みゃ"}, {"myu", "みゅ"}, {"myo", "みょ"},
    {"rya", "りゃ"}, {"ryu", "りゅ"}, {"ryo", "りょ"},
    {"gya", "ぎゃ"}, {"gyu", "ぎゅ"}, {"gyo", "ぎょ"},
    {"bya", "びゃ"}, {"byu", "びゅ"}, {"byo", "びょ"},
    {"pya", "ぴゃ"}, {"pyu", "ぴゅ"}, {"pyo", "ぴょ"}};

bool IsConsonant(char c) {
  const std::string vowels = "aeiou";
  return std::isalpha(static_cast<unsigned char>(c)) != 0 && vowels.find(c) == std::string::npos;
}

bool IsVowelOrY(char c) {
  const std::string set = "aeiouy";
  return set.find(c) != std::string::npos;
}

}  // namespace

std::string RomajiKanaConverter::Feed(char ascii) {
  const char lower = static_cast<char>(std::tolower(static_cast<unsigned char>(ascii)));
  if (!std::isalpha(static_cast<unsigned char>(lower))) {
    std::string out = ConvertPending(true);
    out.push_back(ascii);
    return out;
  }

  if (pending_ == "nn") {
    pending_.clear();
    if (IsVowelOrY(lower)) {
      pending_.push_back('n');
    }
    pending_.push_back(lower);
    return "ん" + ConvertPending(false);
  }

  if (pending_.size() == 1 && pending_[0] == 'n' && lower != 'y' && lower != 'n') {
    std::string out = "ん";
    pending_.clear();
    pending_.push_back(lower);
    out += ConvertPending(false);
    return out;
  }

  if (pending_.size() == 1 && pending_[0] == lower && IsConsonant(lower) && lower != 'n') {
    return "っ";
  }

  pending_.push_back(lower);
  return ConvertPending(false);
}

std::string RomajiKanaConverter::Flush() { return ConvertPending(true); }

void RomajiKanaConverter::Reset() { pending_.clear(); }

std::string RomajiKanaConverter::ConvertPending(bool force_flush) {
  std::string output;
  while (!pending_.empty()) {
    bool matched = false;
    const size_t n = std::min<size_t>(3, pending_.size());
    for (size_t len = n; len > 0; --len) {
      const std::string chunk = pending_.substr(0, len);
      auto it = kRomajiMap.find(chunk);
      if (it != kRomajiMap.end()) {
        output += it->second;
        pending_.erase(0, len);
        matched = true;
        break;
      }
    }
    if (!matched) {
      if (force_flush && pending_ == "n") {
        output += "ん";
        pending_.clear();
        continue;
      }
      if (force_flush || pending_.size() >= 3) {
        output.push_back(pending_.front());
        pending_.erase(0, 1);
      } else {
        break;
      }
    }
  }
  return output;
}

}  // namespace azookey::core

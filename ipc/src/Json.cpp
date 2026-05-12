#include "azookey/ipc/Json.h"

#include <cctype>
#include <cmath>
#include <cstdio>
#include <sstream>

namespace azookey::ipc::json {

namespace {

class Parser {
 public:
  explicit Parser(std::string_view text) : text_(text), pos_(0) {}

  std::optional<Value> ParseDocument() {
    SkipWhitespace();
    auto v = ParseValue();
    if (!v) return std::nullopt;
    SkipWhitespace();
    if (pos_ != text_.size()) return std::nullopt;
    return v;
  }

 private:
  void SkipWhitespace() {
    while (pos_ < text_.size()) {
      char c = text_[pos_];
      if (c == ' ' || c == '\t' || c == '\n' || c == '\r') {
        ++pos_;
      } else {
        break;
      }
    }
  }

  std::optional<Value> ParseValue() {
    SkipWhitespace();
    if (pos_ >= text_.size()) return std::nullopt;
    char c = text_[pos_];
    if (c == '{') return ParseObject();
    if (c == '[') return ParseArray();
    if (c == '"') {
      auto s = ParseString();
      if (!s) return std::nullopt;
      return Value(std::move(*s));
    }
    if (c == 't' || c == 'f') return ParseBool();
    if (c == 'n') return ParseNull();
    if (c == '-' || (c >= '0' && c <= '9')) return ParseNumber();
    return std::nullopt;
  }

  std::optional<Value> ParseObject() {
    if (text_[pos_] != '{') return std::nullopt;
    ++pos_;
    Object obj;
    SkipWhitespace();
    if (pos_ < text_.size() && text_[pos_] == '}') {
      ++pos_;
      return Value(std::move(obj));
    }
    while (true) {
      SkipWhitespace();
      auto key = ParseString();
      if (!key) return std::nullopt;
      SkipWhitespace();
      if (pos_ >= text_.size() || text_[pos_] != ':') return std::nullopt;
      ++pos_;
      auto val = ParseValue();
      if (!val) return std::nullopt;
      obj.emplace(std::move(*key), std::move(*val));
      SkipWhitespace();
      if (pos_ >= text_.size()) return std::nullopt;
      if (text_[pos_] == ',') {
        ++pos_;
        continue;
      }
      if (text_[pos_] == '}') {
        ++pos_;
        return Value(std::move(obj));
      }
      return std::nullopt;
    }
  }

  std::optional<Value> ParseArray() {
    if (text_[pos_] != '[') return std::nullopt;
    ++pos_;
    Array arr;
    SkipWhitespace();
    if (pos_ < text_.size() && text_[pos_] == ']') {
      ++pos_;
      return Value(std::move(arr));
    }
    while (true) {
      auto val = ParseValue();
      if (!val) return std::nullopt;
      arr.push_back(std::move(*val));
      SkipWhitespace();
      if (pos_ >= text_.size()) return std::nullopt;
      if (text_[pos_] == ',') {
        ++pos_;
        continue;
      }
      if (text_[pos_] == ']') {
        ++pos_;
        return Value(std::move(arr));
      }
      return std::nullopt;
    }
  }

  std::optional<std::string> ParseString() {
    if (pos_ >= text_.size() || text_[pos_] != '"') return std::nullopt;
    ++pos_;
    std::string out;
    while (pos_ < text_.size()) {
      char c = text_[pos_++];
      if (c == '"') return out;
      if (c == '\\') {
        if (pos_ >= text_.size()) return std::nullopt;
        char esc = text_[pos_++];
        switch (esc) {
          case '"': out.push_back('"'); break;
          case '\\': out.push_back('\\'); break;
          case '/': out.push_back('/'); break;
          case 'b': out.push_back('\b'); break;
          case 'f': out.push_back('\f'); break;
          case 'n': out.push_back('\n'); break;
          case 'r': out.push_back('\r'); break;
          case 't': out.push_back('\t'); break;
          case 'u': {
            if (pos_ + 4 > text_.size()) return std::nullopt;
            unsigned codepoint = 0;
            for (int i = 0; i < 4; ++i) {
              char h = text_[pos_++];
              codepoint <<= 4;
              if (h >= '0' && h <= '9') codepoint |= static_cast<unsigned>(h - '0');
              else if (h >= 'a' && h <= 'f') codepoint |= static_cast<unsigned>(h - 'a' + 10);
              else if (h >= 'A' && h <= 'F') codepoint |= static_cast<unsigned>(h - 'A' + 10);
              else return std::nullopt;
            }
            // Encode UTF-8 (BMP only; no surrogate-pair join).
            if (codepoint < 0x80) {
              out.push_back(static_cast<char>(codepoint));
            } else if (codepoint < 0x800) {
              out.push_back(static_cast<char>(0xC0 | (codepoint >> 6)));
              out.push_back(static_cast<char>(0x80 | (codepoint & 0x3F)));
            } else {
              out.push_back(static_cast<char>(0xE0 | (codepoint >> 12)));
              out.push_back(static_cast<char>(0x80 | ((codepoint >> 6) & 0x3F)));
              out.push_back(static_cast<char>(0x80 | (codepoint & 0x3F)));
            }
            break;
          }
          default: return std::nullopt;
        }
      } else {
        out.push_back(c);
      }
    }
    return std::nullopt;
  }

  std::optional<Value> ParseBool() {
    if (text_.compare(pos_, 4, "true") == 0) {
      pos_ += 4;
      return Value(true);
    }
    if (text_.compare(pos_, 5, "false") == 0) {
      pos_ += 5;
      return Value(false);
    }
    return std::nullopt;
  }

  std::optional<Value> ParseNull() {
    if (text_.compare(pos_, 4, "null") == 0) {
      pos_ += 4;
      return Value(Null{});
    }
    return std::nullopt;
  }

  std::optional<Value> ParseNumber() {
    size_t start = pos_;
    if (text_[pos_] == '-') ++pos_;
    while (pos_ < text_.size() && std::isdigit(static_cast<unsigned char>(text_[pos_]))) ++pos_;
    if (pos_ < text_.size() && text_[pos_] == '.') {
      ++pos_;
      while (pos_ < text_.size() && std::isdigit(static_cast<unsigned char>(text_[pos_]))) ++pos_;
    }
    if (pos_ < text_.size() && (text_[pos_] == 'e' || text_[pos_] == 'E')) {
      ++pos_;
      if (pos_ < text_.size() && (text_[pos_] == '+' || text_[pos_] == '-')) ++pos_;
      while (pos_ < text_.size() && std::isdigit(static_cast<unsigned char>(text_[pos_]))) ++pos_;
    }
    if (pos_ == start) return std::nullopt;
    try {
      return Value(std::stod(std::string(text_.substr(start, pos_ - start))));
    } catch (...) {
      return std::nullopt;
    }
  }

  std::string_view text_;
  size_t pos_;
};

}  // namespace

const Value* Value::Find(std::string_view key) const {
  if (!IsObject()) return nullptr;
  const auto& obj = AsObject();
  auto it = obj.find(std::string(key));
  if (it == obj.end()) return nullptr;
  return &it->second;
}

std::optional<std::string> Value::GetString(std::string_view key) const {
  const auto* v = Find(key);
  if (!v || !v->IsString()) return std::nullopt;
  return v->AsString();
}

std::optional<double> Value::GetNumber(std::string_view key) const {
  const auto* v = Find(key);
  if (!v || !v->IsNumber()) return std::nullopt;
  return v->AsNumber();
}

std::optional<int64_t> Value::GetInt(std::string_view key) const {
  const auto* v = Find(key);
  if (!v || !v->IsNumber()) return std::nullopt;
  return static_cast<int64_t>(v->AsNumber());
}

std::optional<uint64_t> Value::GetUInt(std::string_view key) const {
  const auto* v = Find(key);
  if (!v || !v->IsNumber()) return std::nullopt;
  double d = v->AsNumber();
  if (d < 0.0) return std::nullopt;
  return static_cast<uint64_t>(d);
}

std::optional<bool> Value::GetBool(std::string_view key) const {
  const auto* v = Find(key);
  if (!v || !v->IsBool()) return std::nullopt;
  return v->AsBool();
}

const Array* Value::GetArray(std::string_view key) const {
  const auto* v = Find(key);
  if (!v || !v->IsArray()) return nullptr;
  return &v->AsArray();
}

const Object* Value::GetObject(std::string_view key) const {
  const auto* v = Find(key);
  if (!v || !v->IsObject()) return nullptr;
  return &v->AsObject();
}

std::optional<Value> Parse(std::string_view text) {
  Parser p(text);
  return p.ParseDocument();
}

std::string EscapeString(std::string_view s) {
  std::string out;
  out.reserve(s.size() + 2);
  for (unsigned char c : s) {
    switch (c) {
      case '"': out += "\\\""; break;
      case '\\': out += "\\\\"; break;
      case '\b': out += "\\b"; break;
      case '\f': out += "\\f"; break;
      case '\n': out += "\\n"; break;
      case '\r': out += "\\r"; break;
      case '\t': out += "\\t"; break;
      default:
        if (c < 0x20) {
          char buf[8];
          std::snprintf(buf, sizeof(buf), "\\u%04x", c);
          out += buf;
        } else {
          out.push_back(static_cast<char>(c));
        }
    }
  }
  return out;
}

std::string Stringify(const Value& v) {
  std::ostringstream oss;
  if (v.IsNull()) {
    oss << "null";
  } else if (v.IsBool()) {
    oss << (v.AsBool() ? "true" : "false");
  } else if (v.IsNumber()) {
    double d = v.AsNumber();
    double intpart = 0;
    if (std::modf(d, &intpart) == 0.0 &&
        d >= -9.2233720368547758e18 && d <= 9.2233720368547758e18) {
      oss << static_cast<int64_t>(d);
    } else {
      oss << d;
    }
  } else if (v.IsString()) {
    oss << '"' << EscapeString(v.AsString()) << '"';
  } else if (v.IsArray()) {
    oss << '[';
    bool first = true;
    for (const auto& e : v.AsArray()) {
      if (!first) oss << ',';
      oss << Stringify(e);
      first = false;
    }
    oss << ']';
  } else if (v.IsObject()) {
    oss << '{';
    bool first = true;
    for (const auto& [k, val] : v.AsObject()) {
      if (!first) oss << ',';
      oss << '"' << EscapeString(k) << "\":" << Stringify(val);
      first = false;
    }
    oss << '}';
  }
  return oss.str();
}

}  // namespace azookey::ipc::json

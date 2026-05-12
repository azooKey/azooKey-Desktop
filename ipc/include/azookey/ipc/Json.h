#pragma once

#include <cstdint>
#include <map>
#include <optional>
#include <string>
#include <string_view>
#include <variant>
#include <vector>

namespace azookey::ipc::json {

struct Value;
using Object = std::map<std::string, Value>;
using Array = std::vector<Value>;
struct Null {};

struct Value {
  std::variant<Null, bool, double, std::string, Array, Object> data;

  Value() : data(Null{}) {}
  Value(Null v) : data(v) {}
  Value(bool v) : data(v) {}
  Value(double v) : data(v) {}
  Value(int v) : data(static_cast<double>(v)) {}
  Value(int64_t v) : data(static_cast<double>(v)) {}
  Value(uint64_t v) : data(static_cast<double>(v)) {}
  Value(const char* v) : data(std::string(v)) {}
  Value(std::string v) : data(std::move(v)) {}
  Value(Array v) : data(std::move(v)) {}
  Value(Object v) : data(std::move(v)) {}

  bool IsNull() const noexcept { return std::holds_alternative<Null>(data); }
  bool IsBool() const noexcept { return std::holds_alternative<bool>(data); }
  bool IsNumber() const noexcept { return std::holds_alternative<double>(data); }
  bool IsString() const noexcept { return std::holds_alternative<std::string>(data); }
  bool IsArray() const noexcept { return std::holds_alternative<Array>(data); }
  bool IsObject() const noexcept { return std::holds_alternative<Object>(data); }

  bool AsBool() const { return std::get<bool>(data); }
  double AsNumber() const { return std::get<double>(data); }
  const std::string& AsString() const { return std::get<std::string>(data); }
  const Array& AsArray() const { return std::get<Array>(data); }
  const Object& AsObject() const { return std::get<Object>(data); }

  const Value* Find(std::string_view key) const;
  std::optional<std::string> GetString(std::string_view key) const;
  std::optional<double> GetNumber(std::string_view key) const;
  std::optional<int64_t> GetInt(std::string_view key) const;
  std::optional<uint64_t> GetUInt(std::string_view key) const;
  std::optional<bool> GetBool(std::string_view key) const;
  const Array* GetArray(std::string_view key) const;
  const Object* GetObject(std::string_view key) const;
};

std::optional<Value> Parse(std::string_view text);
std::string EscapeString(std::string_view s);
std::string Stringify(const Value& v);

}  // namespace azookey::ipc::json

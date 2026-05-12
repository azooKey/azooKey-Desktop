#include "azookey/learning/UserDictionary.h"

#include <algorithm>
#include <fstream>
#include <sstream>

#include "azookey/ipc/Json.h"

namespace azookey::learning {

namespace j = ::azookey::ipc::json;

namespace {

j::Value WordToJson(const UserWord& w) {
  j::Object o;
  o.emplace("word", j::Value(w.word));
  o.emplace("ruby", j::Value(w.ruby));
  if (w.cid) o.emplace("cid", j::Value(static_cast<double>(*w.cid)));
  if (w.mid) o.emplace("mid", j::Value(static_cast<double>(*w.mid)));
  if (w.value) o.emplace("value", j::Value(*w.value));
  return j::Value(std::move(o));
}

std::optional<UserWord> WordFromJson(const j::Value& v) {
  if (!v.IsObject()) return std::nullopt;
  UserWord w;
  auto word = v.GetString("word");
  auto ruby = v.GetString("ruby");
  if (!word || !ruby) return std::nullopt;
  w.word = std::move(*word);
  w.ruby = std::move(*ruby);
  if (auto cid = v.GetInt("cid")) w.cid = static_cast<int32_t>(*cid);
  if (auto mid = v.GetInt("mid")) w.mid = static_cast<int32_t>(*mid);
  if (auto val = v.GetNumber("value")) w.value = *val;
  return w;
}

}  // namespace

UserDictionary::UserDictionary(std::string path) : path_(std::move(path)) {}

bool UserDictionary::Load() {
  by_ruby_.clear();
  std::ifstream ifs(path_);
  if (!ifs.is_open()) {
    return true;  // missing file is fine
  }
  std::ostringstream oss;
  oss << ifs.rdbuf();
  auto v = j::Parse(oss.str());
  if (!v || !v->IsObject()) {
    return false;
  }
  const auto* entries = v->GetArray("entries");
  if (!entries) {
    return false;
  }
  for (const auto& e : *entries) {
    if (auto w = WordFromJson(e)) {
      by_ruby_[w->ruby].push_back(std::move(*w));
    }
  }
  return true;
}

bool UserDictionary::Save() const {
  std::ofstream ofs(path_, std::ios::trunc);
  if (!ofs.is_open()) {
    return false;
  }
  j::Object root;
  root.emplace("version", j::Value(1));
  j::Array entries;
  for (const auto& [ruby, bucket] : by_ruby_) {
    for (const auto& w : bucket) {
      entries.push_back(WordToJson(w));
    }
  }
  root.emplace("entries", j::Value(std::move(entries)));
  ofs << j::Stringify(j::Value(std::move(root)));
  return ofs.good();
}

bool UserDictionary::Add(const UserWord& w) {
  auto& bucket = by_ruby_[w.ruby];
  auto it = std::find_if(bucket.begin(), bucket.end(), [&](const UserWord& x) {
    return x.word == w.word;
  });
  if (it != bucket.end()) {
    *it = w;
    return false;
  }
  bucket.push_back(w);
  return true;
}

bool UserDictionary::Remove(const std::string& word, const std::string& ruby) {
  auto bit = by_ruby_.find(ruby);
  if (bit == by_ruby_.end()) return false;
  auto& bucket = bit->second;
  auto it = std::find_if(bucket.begin(), bucket.end(), [&](const UserWord& x) {
    return x.word == word;
  });
  if (it == bucket.end()) return false;
  bucket.erase(it);
  if (bucket.empty()) by_ruby_.erase(bit);
  return true;
}

std::vector<UserWord> UserDictionary::Lookup(const std::string& ruby) const {
  auto it = by_ruby_.find(ruby);
  if (it == by_ruby_.end()) return {};
  return it->second;
}

std::vector<UserWord> UserDictionary::All() const {
  std::vector<UserWord> out;
  for (const auto& [ruby, bucket] : by_ruby_) {
    for (const auto& w : bucket) out.push_back(w);
  }
  return out;
}

size_t UserDictionary::Size() const {
  size_t n = 0;
  for (const auto& [ruby, bucket] : by_ruby_) n += bucket.size();
  return n;
}

void UserDictionary::Clear() {
  by_ruby_.clear();
}

}  // namespace azookey::learning

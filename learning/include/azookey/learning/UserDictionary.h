#pragma once

#include <cstdint>
#include <map>
#include <optional>
#include <string>
#include <vector>

namespace azookey::learning {

struct UserWord {
  std::string word;
  std::string ruby;
  std::optional<int32_t> cid;
  std::optional<int32_t> mid;
  std::optional<double> value;

  bool operator==(const UserWord& other) const noexcept {
    return word == other.word && ruby == other.ruby && cid == other.cid &&
           mid == other.mid && value == other.value;
  }
};

// User-managed dictionary of words. Backed by a JSON file on disk.
//
// File schema (version 1):
//   { "version": 1, "entries": [
//       { "word": "azooKey", "ruby": "あずきい",
//         "cid": 1285, "mid": 501, "value": -5.0 }, ...
//   ] }
//
// Optional fields (cid, mid, value) are omitted from JSON when absent.
class UserDictionary {
 public:
  explicit UserDictionary(std::string path);

  // Load entries from disk. Missing file -> empty dictionary, returns true.
  // Malformed file -> dictionary becomes empty, returns false.
  bool Load();

  // Persist current state to disk. Returns false if the file cannot be opened.
  bool Save() const;

  // Insert a new entry, or replace the existing entry that has the same
  // (word, ruby) pair. Returns true when a new entry was added (false on
  // in-place replacement).
  bool Add(const UserWord& w);

  // Remove the entry matching (word, ruby). Returns true if removed.
  bool Remove(const std::string& word, const std::string& ruby);

  // Look up all entries by reading. Returns empty vector if unknown.
  std::vector<UserWord> Lookup(const std::string& ruby) const;

  // All entries flattened.
  std::vector<UserWord> All() const;

  size_t Size() const;
  void Clear();

  const std::string& path() const { return path_; }

 private:
  std::string path_;
  std::map<std::string, std::vector<UserWord>> by_ruby_;
};

}  // namespace azookey::learning

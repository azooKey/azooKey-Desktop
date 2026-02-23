#pragma once

#include <cstdint>
#include <string>
#include <unordered_map>

namespace azookey::learning {

struct LearningRecord {
  double weight{};
  uint64_t last_updated_epoch_sec{};
};

class LearningStore {
 public:
  explicit LearningStore(std::string path);

  bool Load();
  bool Save() const;
  void Reset();

  void Observe(const std::string& reading, const std::string& surface, double alpha, uint64_t now_epoch_sec);
  double Score(const std::string& reading, const std::string& surface, uint64_t now_epoch_sec) const;

 private:
  std::string Key(const std::string& reading, const std::string& surface) const;

  std::string path_;
  std::unordered_map<std::string, LearningRecord> table_;
};

}  // namespace azookey::learning

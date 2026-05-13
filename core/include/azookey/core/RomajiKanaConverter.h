#pragma once

#include <string>

namespace azookey::core {

class RomajiKanaConverter {
 public:
  std::string Feed(char ascii);
  std::string Flush();
  void Reset();
  bool HasPending() const { return !pending_.empty(); }
  void PopPending() { if (!pending_.empty()) pending_.pop_back(); }

 private:
  std::string pending_;
  std::string ConvertPending(bool force_flush);
};

}  // namespace azookey::core

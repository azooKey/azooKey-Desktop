#pragma once

#include <unordered_map>

#include "azookey/core/IConverter.h"

namespace azookey::core {

class SimpleConverter final : public IConverter {
 public:
  SimpleConverter();

  // Load additional dictionary entries from a TSV file. Each non-blank,
  // non-'#'-prefixed line must contain:  reading \t surface \t score [\t source]
  // Returns true if at least one row was loaded. Missing or unreadable files
  // return false without throwing; rows that fail to parse are skipped.
  bool LoadFromTsv(const std::string& path);

  std::vector<Candidate> Convert(const std::string& kana, const std::string& context) override;
  std::vector<Candidate> PredictNext(const std::string& kana, const std::string& context) override;
  void Learn(const std::string& committed_surface, const std::string& committed_reading) override;

 private:
  std::unordered_map<std::string, std::vector<Candidate>> dictionary_;
};

}  // namespace azookey::core

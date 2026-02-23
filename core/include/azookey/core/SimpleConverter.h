#pragma once

#include <unordered_map>

#include "azookey/core/IConverter.h"

namespace azookey::core {

class SimpleConverter final : public IConverter {
 public:
  SimpleConverter();

  std::vector<Candidate> Convert(const std::string& kana, const std::string& context) override;
  std::vector<Candidate> PredictNext(const std::string& kana, const std::string& context) override;
  void Learn(const std::string& committed_surface, const std::string& committed_reading) override;

 private:
  std::unordered_map<std::string, std::vector<Candidate>> dictionary_;
};

}  // namespace azookey::core

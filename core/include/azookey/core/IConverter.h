#pragma once

#include <string>
#include <vector>

#include "azookey/core/Candidate.h"

namespace azookey::core {

class IConverter {
 public:
  virtual ~IConverter() = default;

  virtual std::vector<Candidate> Convert(const std::string& kana, const std::string& context) = 0;
  virtual std::vector<Candidate> PredictNext(const std::string& kana, const std::string& context) = 0;
  virtual void Learn(const std::string& committed_surface, const std::string& committed_reading) = 0;
};

}  // namespace azookey::core

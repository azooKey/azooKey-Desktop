#pragma once

#include <string>
#include <vector>

#include "azookey/core/Candidate.h"

namespace azookey::core {

struct ConversionContext {
  std::string preceding_text;
  std::string preedit_text;
  std::vector<std::string> rejected_surfaces;
};

struct CorrectionHint {
  std::string rejected_surface;
  std::string intent;
};

class IConverter {
 public:
  virtual ~IConverter() = default;

  virtual std::vector<Candidate> Convert(const std::string& kana, const ConversionContext& context) = 0;
  virtual std::vector<Candidate> PredictNext(const std::string& kana, const ConversionContext& context) = 0;
  virtual std::vector<Candidate> Correct(const std::string& kana,
                                         const CorrectionHint& hint,
                                         const ConversionContext& context) = 0;
  virtual void Commit(const Candidate& selected_candidate, const ConversionContext& context) = 0;
  virtual void Learn(const std::string& committed_surface, const std::string& committed_reading) = 0;
};

}  // namespace azookey::core

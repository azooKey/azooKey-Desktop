#pragma once

#include <string>

namespace azookey::core {

enum class CandidateSource {
  SystemDictionary,
  UserDictionary,
  Model,
  Llm,
  Heuristic,
};

struct Candidate {
  std::string surface;
  std::string reading;
  double score{};
  CandidateSource source{CandidateSource::Heuristic};
  std::string debug_info;
};

}  // namespace azookey::core

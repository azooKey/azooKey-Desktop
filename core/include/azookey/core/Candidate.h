#pragma once

#include <string>

namespace azookey::core {

struct Candidate {
  std::string surface;
  std::string reading;
  double score{};
  std::string debug_info;
};

}  // namespace azookey::core

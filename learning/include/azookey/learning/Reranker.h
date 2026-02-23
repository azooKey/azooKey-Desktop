#pragma once

#include <vector>

#include "azookey/core/Candidate.h"
#include "azookey/learning/LearningStore.h"

namespace azookey::learning {

class Reranker {
 public:
  explicit Reranker(LearningStore* store) : store_(store) {}

  std::vector<azookey::core::Candidate> Apply(const std::string& reading,
                                              std::vector<azookey::core::Candidate> candidates,
                                              uint64_t now_epoch_sec) const;

 private:
  LearningStore* store_;
};

}  // namespace azookey::learning

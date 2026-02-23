#include "azookey/learning/Reranker.h"

#include <algorithm>

namespace azookey::learning {

std::vector<azookey::core::Candidate> Reranker::Apply(const std::string& reading,
                                                       std::vector<azookey::core::Candidate> candidates,
                                                       uint64_t now_epoch_sec) const {
  if (!store_) {
    return candidates;
  }

  for (auto& c : candidates) {
    c.score += store_->Score(reading, c.surface, now_epoch_sec);
  }

  std::stable_sort(candidates.begin(), candidates.end(), [](const auto& l, const auto& r) {
    return l.score > r.score;
  });
  return candidates;
}

}  // namespace azookey::learning

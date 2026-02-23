#include "azookey/core/SimpleConverter.h"

#include <algorithm>

namespace azookey::core {

SimpleConverter::SimpleConverter() {
  dictionary_["わたし"] = {
      Candidate{"私", "わたし", 1.0, "static-dict"},
      Candidate{"わたし", "わたし", 0.8, "identity"},
      Candidate{"渡し", "わたし", 0.3, "fallback"},
  };
  dictionary_["にほん"] = {
      Candidate{"日本", "にほん", 1.0, "static-dict"},
      Candidate{"にほん", "にほん", 0.7, "identity"},
      Candidate{"二本", "にほん", 0.4, "fallback"},
  };
  dictionary_["とうきょう"] = {
      Candidate{"東京", "とうきょう", 1.0, "static-dict"},
      Candidate{"とうきょう", "とうきょう", 0.8, "identity"},
      Candidate{"投棄用", "とうきょう", 0.1, "fallback"},
  };
}

std::vector<Candidate> SimpleConverter::Convert(const std::string& kana, const std::string& context) {
  auto it = dictionary_.find(kana);
  if (it != dictionary_.end()) {
    return it->second;
  }

  return {
      Candidate{kana, kana, 0.6, "identity"},
      Candidate{kana + "ー", kana, 0.2, "heuristic-long-vowel"},
      Candidate{"「" + kana + "」", kana, 0.1, "heuristic-quote"},
  };
}

std::vector<Candidate> SimpleConverter::PredictNext(const std::string& kana, const std::string& context) {
  std::vector<Candidate> candidates = Convert(kana, context);
  for (auto& c : candidates) {
    c.debug_info += ";predict";
    c.score *= 0.8;
  }
  return candidates;
}

void SimpleConverter::Learn(const std::string& committed_surface, const std::string& committed_reading) {
  auto& bucket = dictionary_[committed_reading];
  auto found = std::find_if(bucket.begin(), bucket.end(), [&](const Candidate& c) {
    return c.surface == committed_surface;
  });
  if (found != bucket.end()) {
    found->score += 0.2;
    found->debug_info = "learned";
    return;
  }
  bucket.insert(bucket.begin(), Candidate{committed_surface, committed_reading, 1.2, "learned-new"});
}

}  // namespace azookey::core

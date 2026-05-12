#include "azookey/core/SimpleConverter.h"

#include <algorithm>
#include <fstream>
#include <sstream>
#include <string>

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

bool SimpleConverter::LoadFromTsv(const std::string& path) {
  std::ifstream f(path);
  if (!f.is_open()) return false;
  std::string line;
  bool any = false;
  while (std::getline(f, line)) {
    if (line.empty() || line[0] == '#') continue;
    std::istringstream iss(line);
    std::string reading, surface, score_str, source;
    if (!std::getline(iss, reading, '\t')) continue;
    if (!std::getline(iss, surface, '\t')) continue;
    if (!std::getline(iss, score_str, '\t')) continue;
    std::getline(iss, source);
    if (reading.empty() || surface.empty()) continue;
    double score = 0.0;
    try {
      score = std::stod(score_str);
    } catch (...) {
      continue;
    }
    Candidate c;
    c.surface = std::move(surface);
    c.reading = reading;
    c.score = score;
    c.debug_info = source.empty() ? "tsv" : source;
    dictionary_[reading].push_back(std::move(c));
    any = true;
  }
  return any;
}

std::vector<Candidate> SimpleConverter::Convert(const std::string& kana, const std::string& context) {
  auto it = dictionary_.find(kana);
  if (it != dictionary_.end()) {
    return it->second;
  }

  // Prefix fallback: any dictionary entry whose reading starts with kana is
  // surfaced with a damped score, so partial typing still produces results.
  std::vector<Candidate> prefix_hits;
  for (const auto& [reading, candidates] : dictionary_) {
    if (reading.size() > kana.size() && reading.compare(0, kana.size(), kana) == 0) {
      for (const auto& c : candidates) {
        Candidate copy = c;
        copy.score *= 0.5;
        copy.debug_info = copy.debug_info.empty() ? "prefix" : copy.debug_info + ";prefix";
        prefix_hits.push_back(std::move(copy));
      }
    }
  }
  if (!prefix_hits.empty()) {
    std::sort(prefix_hits.begin(), prefix_hits.end(),
              [](const Candidate& a, const Candidate& b) { return a.score > b.score; });
    if (prefix_hits.size() > 10) prefix_hits.resize(10);
    return prefix_hits;
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

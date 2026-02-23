#include <cstdio>
#include <stdexcept>

#include "azookey/core/Candidate.h"
#include "azookey/learning/LearningStore.h"
#include "azookey/learning/Reranker.h"

static void Expect(bool cond, const char* msg) {
  if (!cond) throw std::runtime_error(msg);
}

int main() {
  const char* path = "/tmp/azookey_learning_test.tsv";
  std::remove(path);

  azookey::learning::LearningStore store(path);
  store.Observe("にほん", "二本", 1.5, 1000);
  store.Save();

  azookey::learning::LearningStore loaded(path);
  loaded.Load();
  azookey::learning::Reranker reranker(&loaded);

  std::vector<azookey::core::Candidate> cands = {
      {"日本", "にほん", 1.0, "base"},
      {"二本", "にほん", 0.4, "base"},
  };

  auto reranked = reranker.Apply("にほん", std::move(cands), 1001);
  Expect(reranked.front().surface == "二本", "learned candidate should be boosted");
  std::remove(path);
  return 0;
}

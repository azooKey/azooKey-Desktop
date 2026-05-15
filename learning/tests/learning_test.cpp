#include <cstdio>
#include <filesystem>
#include <stdexcept>
#include <string>

#include "azookey/core/Candidate.h"
#include "azookey/learning/LearningStore.h"
#include "azookey/learning/Reranker.h"

static void Expect(bool cond, const char* msg) {
  if (!cond) throw std::runtime_error(msg);
}

int main() {
  try {
    const std::string path =
        (std::filesystem::temp_directory_path() / "azookey_learning_test.tsv").string();
    std::remove(path.c_str());

    azookey::learning::LearningStore store(path);
    store.Observe("にほん", "日本", 1.0, 100);
    store.ObserveCorrection("にほん", "日本", "二本", 0.5, 120);
    store.Save();

    azookey::learning::LearningStore loaded(path);
    loaded.Load();
    azookey::learning::Reranker reranker(&loaded);

    std::vector<azookey::core::Candidate> cands = {
        {"日本", "にほん", 0.9, azookey::core::CandidateSource::SystemDictionary, "base"},
        {"二本", "にほん", 0.9, azookey::core::CandidateSource::SystemDictionary, "base"},
    };

    auto ranked = reranker.Apply("にほん", std::move(cands), 120);
    (void)ranked;
    Expect(loaded.Score("にほん", "日本", 120) <= loaded.Score("にほん", "二本", 120),
           "rejected candidate should be down-weighted");
    std::remove(path.c_str());
    return 0;
  } catch (const std::exception& e) {
    std::fprintf(stderr, "FAIL: %s\n", e.what());
    return 1;
  }
}

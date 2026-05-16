// Direct unit tests for Reranker. Previously the reranker was only exercised
// indirectly through LearningStore round trips in learning_test.cpp; these
// tests pin down the behaviors that callers (InferenceEngine, TIP) rely on:
//   - null-store passthrough
//   - empty / single-candidate handling
//   - stable sort preserves input order when scores tie
//   - time decay matches exp(-0.15 * days) in LearningStore::Score
//   - learning boost flips top candidate
//
// All tests are platform-neutral (no Windows headers, no IPC).

#include <cmath>
#include <cstdio>
#include <filesystem>
#include <stdexcept>
#include <string>
#include <vector>

#include "azookey/core/Candidate.h"
#include "azookey/learning/LearningStore.h"
#include "azookey/learning/Reranker.h"

static void Expect(bool cond, const char* msg) {
  if (!cond) throw std::runtime_error(msg);
}

namespace core = azookey::core;
namespace learn = azookey::learning;

static std::vector<core::Candidate> MakeCandidates(
    std::initializer_list<std::pair<const char*, double>> entries,
    const char* reading) {
  std::vector<core::Candidate> out;
  for (const auto& [surface, score] : entries) {
    out.push_back({surface, reading, score,
                   core::CandidateSource::SystemDictionary, "test"});
  }
  return out;
}

static void TestNullStorePassthrough() {
  learn::Reranker reranker(nullptr);
  auto cands = MakeCandidates({{"日本", 0.9}, {"二本", 0.5}}, "にほん");
  auto out = reranker.Apply("にほん", std::move(cands), /*now=*/1000);
  Expect(out.size() == 2, "null store keeps all entries");
  Expect(out[0].surface == "日本", "null store preserves input order [0]");
  Expect(out[1].surface == "二本", "null store preserves input order [1]");
}

static void TestEmptyCandidates() {
  const std::string path =
      (std::filesystem::temp_directory_path() / "azookey_reranker_empty.tsv").string();
  std::remove(path.c_str());
  learn::LearningStore store(path);
  learn::Reranker reranker(&store);

  auto out = reranker.Apply("にほん", {}, /*now=*/100);
  Expect(out.empty(), "empty input yields empty output");
}

static void TestStableSortOnTie() {
  const std::string path =
      (std::filesystem::temp_directory_path() / "azookey_reranker_tie.tsv").string();
  std::remove(path.c_str());
  learn::LearningStore store(path);
  learn::Reranker reranker(&store);

  // No learning records → store contributes 0 to every candidate, so input
  // order must be preserved for equal scores.
  auto cands = MakeCandidates(
      {{"A", 1.0}, {"B", 1.0}, {"C", 1.0}}, "x");
  auto out = reranker.Apply("x", std::move(cands), /*now=*/100);
  Expect(out.size() == 3, "tie preserves all 3 entries");
  Expect(out[0].surface == "A", "stable sort keeps A first on tie");
  Expect(out[1].surface == "B", "stable sort keeps B second on tie");
  Expect(out[2].surface == "C", "stable sort keeps C third on tie");
}

static void TestLearningBoostFlipsTop() {
  const std::string path =
      (std::filesystem::temp_directory_path() / "azookey_reranker_boost.tsv").string();
  std::remove(path.c_str());
  learn::LearningStore store(path);
  learn::Reranker reranker(&store);

  // Initial top = 日本 (score 1.0 > 0.9).
  auto cands1 = MakeCandidates({{"日本", 1.0}, {"二本", 0.9}}, "にほん");
  auto out1 = reranker.Apply("にほん", std::move(cands1), /*now=*/100);
  Expect(out1.front().surface == "日本", "before learning 日本 is top");

  // After 2 commits of 二本, boost should flip the top (alpha=1.0 each → +2.0).
  store.Observe("にほん", "二本", /*alpha=*/1.0, /*now=*/100);
  store.Observe("にほん", "二本", /*alpha=*/1.0, /*now=*/100);

  auto cands2 = MakeCandidates({{"日本", 1.0}, {"二本", 0.9}}, "にほん");
  auto out2 = reranker.Apply("にほん", std::move(cands2), /*now=*/100);
  Expect(out2.front().surface == "二本", "after learning 二本 is top");

  std::remove(path.c_str());
}

static void TestTimeDecay() {
  const std::string path =
      (std::filesystem::temp_directory_path() / "azookey_reranker_decay.tsv").string();
  std::remove(path.c_str());
  learn::LearningStore store(path);
  learn::Reranker reranker(&store);

  // Observe at t=0 (epoch seconds 1700000000).
  constexpr uint64_t kT0 = 1'700'000'000ULL;
  constexpr uint64_t kOneDay = 60 * 60 * 24;
  store.Observe("にほん", "二本", /*alpha=*/5.0, /*now=*/kT0);

  // Same instant: full weight.
  const double s0 = store.Score("にほん", "二本", kT0);
  Expect(std::abs(s0 - 5.0) < 1e-9, "no-decay score equals weight");

  // 10 days later: decay = exp(-0.15 * 10) ≈ 0.22313.
  const double s10 = store.Score("にほん", "二本", kT0 + 10 * kOneDay);
  const double expected_s10 = 5.0 * std::exp(-0.15 * 10);
  Expect(std::abs(s10 - expected_s10) < 1e-6,
         "decay at 10 days matches exp(-0.15 * days)");

  // Score is monotonically non-increasing with time.
  const double s1 = store.Score("にほん", "二本", kT0 + 1 * kOneDay);
  const double s5 = store.Score("にほん", "二本", kT0 + 5 * kOneDay);
  Expect(s0 >= s1 && s1 >= s5 && s5 >= s10, "decay monotonic");

  // After very long time the decayed score should be ~0 (smaller than a 0.5
  // gap), so the reranker should NOT flip the top candidate anymore.
  auto cands = MakeCandidates({{"日本", 1.0}, {"二本", 0.5}}, "にほん");
  auto out = reranker.Apply("にほん", std::move(cands),
                            /*now=*/kT0 + 365 * kOneDay);
  Expect(out.front().surface == "日本",
         "after 1 year of decay original top must return");

  std::remove(path.c_str());
}

static void TestCorrectionDownweightsRejected() {
  const std::string path =
      (std::filesystem::temp_directory_path() / "azookey_reranker_correction.tsv").string();
  std::remove(path.c_str());
  learn::LearningStore store(path);
  learn::Reranker reranker(&store);

  // Observe rejected once, then ObserveCorrection: rejected weight should
  // clamp to 0 (max(0, weight - alpha)) and selected should be boosted.
  store.Observe("にほん", "日本", /*alpha=*/1.0, /*now=*/100);
  store.ObserveCorrection("にほん", "日本", "二本", /*alpha=*/1.0, /*now=*/100);

  Expect(store.Score("にほん", "日本", 100) <= store.Score("にほん", "二本", 100),
         "rejected candidate must not score above selected after correction");

  std::remove(path.c_str());
}

int main() {
  try {
    TestNullStorePassthrough();
    TestEmptyCandidates();
    TestStableSortOnTie();
    TestLearningBoostFlipsTop();
    TestTimeDecay();
    TestCorrectionDownweightsRejected();
    return 0;
  } catch (const std::exception& e) {
    std::fprintf(stderr, "FAIL: %s\n", e.what());
    return 1;
  }
}

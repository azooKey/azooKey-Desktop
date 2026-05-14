#include <atomic>
#include <cstdio>
#include <filesystem>
#include <memory>
#include <stdexcept>
#include <string>

#include "azookey/core/SimpleConverter.h"
#include "azookey/host/InferenceEngine.h"
#include "azookey/learning/LearningStore.h"
#include "azookey/learning/UserDictionary.h"

static void Expect(bool cond, const char* msg) {
  if (!cond) throw std::runtime_error(msg);
}

namespace {

constexpr uint64_t kNowBase = 1'700'000'000ULL;

std::unique_ptr<azookey::host::InferenceEngine> MakeEngine(
    azookey::learning::LearningStore& store) {
  azookey::host::EngineConfig cfg;
  cfg.learning_alpha = 0.8;
  return std::make_unique<azookey::host::InferenceEngine>(
      std::make_unique<azookey::core::SimpleConverter>(), &store, cfg);
}

}  // namespace

static void TestQueryWithLearningBoost() {
  const char* path = "azookey_host_engine_learning.tsv";
  std::remove(path);
  azookey::learning::LearningStore store(path);

  auto engine = MakeEngine(store);

  // First conversion - 日本 is the static top.
  auto first = engine->QueryCandidates("にほん", "", kNowBase);
  Expect(!first.empty(), "first query non-empty");
  Expect(first.front().surface == "日本", "before learning 日本 is top");

  // Commit 二本 three times to outweigh the static gap.
  engine->CommitObservation("にほん", "二本", kNowBase + 1);
  engine->CommitObservation("にほん", "二本", kNowBase + 2);
  engine->CommitObservation("にほん", "二本", kNowBase + 3);

  auto fourth = engine->QueryCandidates("にほん", "", kNowBase + 4);
  Expect(!fourth.empty(), "fourth query non-empty");
  Expect(fourth.front().surface == "二本",
         "after 3 commits 二本 must move to top");

  std::remove(path);
}

static void TestUserDictionaryInjection() {
  const char* lpath = "azookey_host_engine_user_dict_learn.tsv";
  std::remove(lpath);
  azookey::learning::LearningStore store(lpath);
  auto engine = MakeEngine(store);

  const std::string udict_path =
      (std::filesystem::temp_directory_path() / "azookey_host_engine_user.json").string();
  azookey::learning::UserDictionary dict(udict_path);
  azookey::learning::UserWord w;
  w.word = "azooKey";
  w.ruby = "あずきい";
  dict.Add(w);
  engine->SetUserDictionary(&dict);

  auto cands = engine->QueryCandidates("あずきい", "", kNowBase);
  Expect(!cands.empty(), "user-dict query non-empty");
  Expect(cands.front().surface == "azooKey",
         "user-dictionary entry must appear at top");
  Expect(cands.front().debug_info.find("user-dict") != std::string::npos,
         "user-dictionary entry tagged");

  // Removing the user word makes it disappear from results.
  Expect(dict.Remove("azooKey", "あずきい"), "remove user word");
  auto cands2 = engine->QueryCandidates("あずきい", "", kNowBase);
  for (const auto& c : cands2) {
    Expect(c.surface != "azooKey", "removed entry must not appear");
  }

  std::remove(lpath);
}

static void TestCancelEarlyReturn() {
  const char* lpath = "azookey_host_engine_cancel.tsv";
  std::remove(lpath);
  azookey::learning::LearningStore store(lpath);
  auto engine = MakeEngine(store);

  std::atomic<bool> cancel{true};
  auto cands = engine->QueryCandidates("にほん", "", kNowBase, &cancel);
  Expect(cands.empty(), "canceled query must return empty");

  cancel.store(false);
  auto cands2 = engine->QueryCandidates("にほん", "", kNowBase, &cancel);
  Expect(!cands2.empty(), "non-canceled query returns candidates");

  std::remove(lpath);
}

static void TestLegacyOverloadStillWorks() {
  const char* lpath = "azookey_host_engine_legacy.tsv";
  std::remove(lpath);
  azookey::learning::LearningStore store(lpath);
  auto engine = MakeEngine(store);

  // Three-argument overload exists for backwards compatibility with main.cpp
  // and the existing bench harness.
  auto cands = engine->QueryCandidates("わたし", "", kNowBase);
  Expect(!cands.empty(), "legacy overload returns candidates");
  std::remove(lpath);
}

int main() {
  TestQueryWithLearningBoost();
  TestUserDictionaryInjection();
  TestCancelEarlyReturn();
  TestLegacyOverloadStillWorks();
  return 0;
}

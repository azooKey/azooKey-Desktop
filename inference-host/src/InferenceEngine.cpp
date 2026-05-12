#include "azookey/host/InferenceEngine.h"

namespace azookey::host {

InferenceEngine::InferenceEngine(std::unique_ptr<core::IConverter> converter,
                                 learning::LearningStore* store,
                                 EngineConfig config)
    : converter_(std::move(converter)),
      store_(store),
      reranker_(store),
      config_(std::move(config)) {}

void InferenceEngine::SetUserDictionary(learning::UserDictionary* dict) {
  user_dict_ = dict;
}

bool InferenceEngine::LoadModel() {
  // MVP: model loading is delegated to the converter backend. Zenzai
  // integration (M8) replaces converter_ with a llama.cpp-backed converter.
  return true;
}

std::vector<core::Candidate> InferenceEngine::QueryCandidates(const std::string& kana,
                                                              const std::string& context,
                                                              uint64_t now_epoch_sec) {
  return QueryCandidates(kana, context, now_epoch_sec, nullptr);
}

std::vector<core::Candidate> InferenceEngine::QueryCandidates(const std::string& kana,
                                                              const std::string& context,
                                                              uint64_t now_epoch_sec,
                                                              const std::atomic<bool>* cancel) {
  auto canceled = [cancel]() {
    return cancel && cancel->load(std::memory_order_relaxed);
  };

  if (canceled()) return {};

  std::vector<core::Candidate> merged;
  if (user_dict_) {
    auto words = user_dict_->Lookup(kana);
    merged.reserve(words.size());
    for (const auto& w : words) {
      core::Candidate c;
      c.surface = w.word;
      c.reading = w.ruby;
      c.score = w.value.value_or(config_.user_word_default_score);
      c.debug_info = "user-dict";
      merged.push_back(std::move(c));
    }
  }

  if (canceled()) return {};

  auto converted = converter_->Convert(kana, context);
  merged.insert(merged.end(),
                std::make_move_iterator(converted.begin()),
                std::make_move_iterator(converted.end()));

  if (canceled()) return {};

  return reranker_.Apply(kana, std::move(merged), now_epoch_sec);
}

void InferenceEngine::CommitObservation(const std::string& reading, const std::string& surface, uint64_t now_epoch_sec) {
  if (store_) {
    store_->Observe(reading, surface, config_.learning_alpha, now_epoch_sec);
    store_->Save();
  }
  converter_->Learn(surface, reading);
}

}  // namespace azookey::host

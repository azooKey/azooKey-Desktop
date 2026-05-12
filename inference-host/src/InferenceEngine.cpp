#include "azookey/host/InferenceEngine.h"

namespace azookey::host {

namespace {
core::ConversionContext BuildContext(const std::string& kana, const std::string& context) {
  core::ConversionContext conversion_context;
  conversion_context.preceding_text = context;
  conversion_context.preedit_text = kana;
  return conversion_context;
}
}  // namespace

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

  auto converted = converter_->Convert(kana, BuildContext(kana, context));
  merged.insert(merged.end(),
                std::make_move_iterator(converted.begin()),
                std::make_move_iterator(converted.end()));

  if (canceled()) return {};

  return reranker_.Apply(kana, std::move(merged), now_epoch_sec);
}

std::vector<core::Candidate> InferenceEngine::QueryPredictions(const std::string& kana,
                                                               const std::string& context,
                                                               uint64_t now_epoch_sec) {
  auto candidates = converter_->PredictNext(kana, BuildContext(kana, context));
  return reranker_.Apply(kana, std::move(candidates), now_epoch_sec);
}

std::vector<core::Candidate> InferenceEngine::QueryCorrections(const std::string& kana,
                                                               const std::string& context,
                                                               const std::string& rejected_surface,
                                                               uint64_t now_epoch_sec) {
  auto conversion_context = BuildContext(kana, context);
  conversion_context.rejected_surfaces.push_back(rejected_surface);
  core::CorrectionHint hint;
  hint.rejected_surface = rejected_surface;
  hint.intent = "user_rejection";
  auto candidates = converter_->Correct(kana, hint, conversion_context);
  return reranker_.Apply(kana, std::move(candidates), now_epoch_sec);
}

void InferenceEngine::CommitObservation(const std::string& reading, const std::string& surface, uint64_t now_epoch_sec) {
  if (store_) {
    store_->Observe(reading, surface, config_.learning_alpha, now_epoch_sec);
    store_->Save();
  }
  converter_->Commit(core::Candidate{surface, reading, 1.0, core::CandidateSource::UserDictionary, "commit"},
                     core::ConversionContext{});
}


void InferenceEngine::CommitCorrection(const std::string& reading,
                                       const std::string& rejected_surface,
                                       const std::string& selected_surface,
                                       uint64_t now_epoch_sec) {
  if (store_) {
    store_->ObserveCorrection(reading, rejected_surface, selected_surface, config_.learning_alpha, now_epoch_sec);
    store_->Save();
  }

  core::ConversionContext context;
  context.rejected_surfaces.push_back(rejected_surface);
  converter_->Commit(core::Candidate{selected_surface, reading, 1.0, core::CandidateSource::UserDictionary, "correction-commit"},
                     context);
}

}  // namespace azookey::host

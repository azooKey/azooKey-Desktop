#include "azookey/host/InferenceEngine.h"

namespace azookey::host {

InferenceEngine::InferenceEngine(std::unique_ptr<core::IConverter> converter,
                                 learning::LearningStore* store,
                                 EngineConfig config)
    : converter_(std::move(converter)), store_(store), reranker_(store), config_(std::move(config)) {}

bool InferenceEngine::LoadModel() {
  // MVP: model loading is delegated to converter backend in future.
  // Backend selection is still exposed for CPU/CUDA compatibility contract.
  return true;
}

std::vector<core::Candidate> InferenceEngine::QueryCandidates(const std::string& kana,
                                                              const std::string& context,
                                                              uint64_t now_epoch_sec) {
  auto candidates = converter_->Convert(kana, context);
  return reranker_.Apply(kana, std::move(candidates), now_epoch_sec);
}

void InferenceEngine::CommitObservation(const std::string& reading, const std::string& surface, uint64_t now_epoch_sec) {
  if (store_) {
    store_->Observe(reading, surface, config_.learning_alpha, now_epoch_sec);
    store_->Save();
  }
  converter_->Learn(surface, reading);
}

}  // namespace azookey::host

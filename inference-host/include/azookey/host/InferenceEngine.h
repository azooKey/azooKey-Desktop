#pragma once

#include <memory>
#include <string>
#include <vector>

#include "azookey/core/IConverter.h"
#include "azookey/learning/LearningStore.h"
#include "azookey/learning/Reranker.h"

namespace azookey::host {

enum class BackendKind {
  Cpu,
  Cuda,
};

struct EngineConfig {
  BackendKind backend{BackendKind::Cpu};
  std::string model_path;
  bool enable_live_conversion{true};
  double learning_alpha{0.8};
};

class InferenceEngine {
 public:
  InferenceEngine(std::unique_ptr<core::IConverter> converter, learning::LearningStore* store, EngineConfig config);

  bool LoadModel();
  std::vector<core::Candidate> QueryCandidates(const std::string& kana, const std::string& context, uint64_t now_epoch_sec);
  void CommitObservation(const std::string& reading, const std::string& surface, uint64_t now_epoch_sec);

  BackendKind backend() const { return config_.backend; }

 private:
  std::unique_ptr<core::IConverter> converter_;
  learning::LearningStore* store_;
  learning::Reranker reranker_;
  EngineConfig config_;
};

}  // namespace azookey::host

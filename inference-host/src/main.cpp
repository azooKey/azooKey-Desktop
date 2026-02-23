#include <chrono>
#include <iostream>

#include "azookey/core/SimpleConverter.h"
#include "azookey/host/InferenceEngine.h"

int main(int argc, char** argv) {
  azookey::host::EngineConfig config;
  if (argc > 1 && std::string(argv[1]) == "--cuda") {
    config.backend = azookey::host::BackendKind::Cuda;
  }

  azookey::learning::LearningStore store("azookey_learning.tsv");
  store.Load();

  azookey::host::InferenceEngine engine(std::make_unique<azookey::core::SimpleConverter>(), &store, config);
  if (!engine.LoadModel()) {
    std::cerr << "failed to load model" << std::endl;
    return 1;
  }

  std::cout << "azookey inference-host started. backend="
            << (engine.backend() == azookey::host::BackendKind::Cuda ? "cuda" : "cpu") << std::endl;

  std::string kana;
  while (std::getline(std::cin, kana)) {
    auto now = static_cast<uint64_t>(std::chrono::system_clock::to_time_t(std::chrono::system_clock::now()));
    const auto cands = engine.QueryCandidates(kana, "", now);
    if (!cands.empty()) {
      std::cout << cands.front().surface << std::endl;
      engine.CommitObservation(kana, cands.front().surface, now);
    }
  }
  return 0;
}

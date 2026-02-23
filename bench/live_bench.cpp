#include <algorithm>
#include <chrono>
#include <iostream>
#include <vector>

#include "azookey/core/SimpleConverter.h"
#include "azookey/host/InferenceEngine.h"

int main() {
  azookey::learning::LearningStore store("/tmp/azookey_bench_learning.tsv");
  azookey::host::InferenceEngine engine(std::make_unique<azookey::core::SimpleConverter>(), &store, {});
  engine.LoadModel();

  const std::vector<std::string> inputs = {"わたし", "にほん", "とうきょう", "かなへんかん", "にほん"};
  std::vector<double> lat_ms;
  for (int i = 0; i < 200; ++i) {
    const auto& kana = inputs[static_cast<size_t>(i) % inputs.size()];
    auto t0 = std::chrono::steady_clock::now();
    auto now = static_cast<uint64_t>(std::chrono::system_clock::to_time_t(std::chrono::system_clock::now()));
    (void)engine.QueryCandidates(kana, "", now);
    auto t1 = std::chrono::steady_clock::now();
    lat_ms.push_back(std::chrono::duration<double, std::milli>(t1 - t0).count());
  }

  std::sort(lat_ms.begin(), lat_ms.end());
  auto pct = [&](double p) {
    size_t idx = static_cast<size_t>((p / 100.0) * (lat_ms.size() - 1));
    return lat_ms[idx];
  };

  std::cout << "p50_ms=" << pct(50) << " p95_ms=" << pct(95) << " p99_ms=" << pct(99) << std::endl;
  return 0;
}

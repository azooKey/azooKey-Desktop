#include <iostream>
#include <memory>
#include <string>

#include "azookey/core/SimpleConverter.h"
#include "azookey/host/Dispatcher.h"
#include "azookey/host/InferenceEngine.h"
#include "azookey/host/RequestScheduler.h"
#include "azookey/ipc/Messages.h"
#include "azookey/learning/LearningStore.h"
#include "azookey/learning/UserDictionary.h"

namespace {

constexpr const char* kHostVersion = "0.1.0";

}  // namespace

int main(int argc, char** argv) {
  azookey::host::EngineConfig config;
  std::string learning_path = "azookey_learning.tsv";
  std::string user_dict_path = "azookey_user_dict.json";
  std::string mock_dict_path;

  for (int i = 1; i < argc; ++i) {
    std::string a = argv[i];
    if (a == "--cuda") {
      config.backend = azookey::host::BackendKind::Cuda;
    } else if (a == "--learning" && i + 1 < argc) {
      learning_path = argv[++i];
    } else if (a == "--user-dict" && i + 1 < argc) {
      user_dict_path = argv[++i];
    } else if (a == "--mock-dict" && i + 1 < argc) {
      mock_dict_path = argv[++i];
    }
  }

  azookey::learning::LearningStore store(learning_path);
  store.Load();

  azookey::learning::UserDictionary user_dict(user_dict_path);
  user_dict.Load();

  auto converter = std::make_unique<azookey::core::SimpleConverter>();
  if (!mock_dict_path.empty()) {
    converter->LoadFromTsv(mock_dict_path);
  }

  azookey::host::InferenceEngine engine(std::move(converter), &store, config);
  engine.SetUserDictionary(&user_dict);
  engine.LoadModel();

  azookey::host::RequestScheduler scheduler;
  azookey::host::DispatcherConfig dconf;
  dconf.host_version = kHostVersion;
  dconf.protocol_version = 1;
  azookey::host::Dispatcher dispatcher(&engine, &scheduler, &user_dict, dconf);

  std::cerr << "azookey inference-host started. backend="
            << (engine.backend() == azookey::host::BackendKind::Cuda ? "cuda" : "cpu")
            << " learning=" << learning_path << " user_dict=" << user_dict_path
            << std::endl;

  std::string line;
  while (std::getline(std::cin, line)) {
    if (line.empty()) continue;
    auto env = azookey::ipc::Deserialize(line);
    if (!env) {
      std::cerr << "warn: failed to parse envelope" << std::endl;
      continue;
    }
    auto resp = dispatcher.Dispatch(*env);
    if (resp) {
      std::cout << azookey::ipc::Serialize(*resp) << std::endl;
      std::cout.flush();
    }
  }
  return 0;
}

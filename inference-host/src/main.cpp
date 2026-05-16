#include <atomic>
#include <chrono>
#include <csignal>
#include <iostream>
#include <memory>
#include <string>
#include <thread>

#include "azookey/core/SimpleConverter.h"
#include "azookey/host/Dispatcher.h"
#include "azookey/host/InferenceEngine.h"
#include "azookey/host/RequestScheduler.h"
#include "azookey/ipc/Messages.h"
#include "azookey/ipc/NamedPipeTransport.h"
#include "azookey/learning/LearningStore.h"
#include "azookey/learning/UserDictionary.h"

namespace {

constexpr const char* kHostVersion = "0.1.0";
std::atomic<bool> g_stop_requested{false};

void RequestStop(int) {
  g_stop_requested.store(true);
}

}  // namespace

int main(int argc, char** argv) {
  azookey::host::EngineConfig config;
  std::string learning_path = "azookey_learning.tsv";
  std::string user_dict_path = "azookey_user_dict.json";
  std::string mock_dict_path;
  std::string pipe_name;

  for (int i = 1; i < argc; ++i) {
    const std::string arg = argv[i];
    if (arg == "--cuda") {
      config.backend = azookey::host::BackendKind::Cuda;
    } else if (arg == "--cpu") {
      config.backend = azookey::host::BackendKind::Cpu;
    } else if (arg == "--backend" && i + 1 < argc) {
      const std::string value = argv[++i];
      if (value == "cuda") {
        config.backend = azookey::host::BackendKind::Cuda;
      } else if (value == "cpu") {
        config.backend = azookey::host::BackendKind::Cpu;
      }
    } else if (arg == "--learning" && i + 1 < argc) {
      learning_path = argv[++i];
    } else if (arg == "--user-dict" && i + 1 < argc) {
      user_dict_path = argv[++i];
    } else if (arg == "--mock-dict" && i + 1 < argc) {
      mock_dict_path = argv[++i];
    } else if (arg == "--pipe") {
      if (i + 1 < argc && argv[i + 1][0] != '-') {
        pipe_name = argv[++i];
      } else {
        pipe_name = azookey::ipc::DefaultPipeName();
      }
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

  if (!pipe_name.empty()) {
    if (pipe_name == "default") {
      pipe_name = azookey::ipc::DefaultPipeName();
    }

    azookey::ipc::NamedPipeServer server;
    if (!server.Start(pipe_name, [&](const azookey::ipc::Envelope& request) {
          return dispatcher.Dispatch(request);
        })) {
      std::cerr << "error: failed to listen on pipe " << pipe_name << std::endl;
      return 2;
    }

    std::signal(SIGINT, RequestStop);
#ifdef SIGTERM
    std::signal(SIGTERM, RequestStop);
#endif
    std::cerr << "listening on " << pipe_name << " (Ctrl+C to stop)" << std::endl;
    while (!g_stop_requested.load()) {
      std::this_thread::sleep_for(std::chrono::milliseconds(200));
    }
    server.Stop();
    return 0;
  }

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

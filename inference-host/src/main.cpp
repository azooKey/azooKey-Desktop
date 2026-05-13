#include <iostream>
#include <memory>
#include <csignal>
#include <chrono>
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
volatile std::sig_atomic_t g_stop_requested = 0;

void HandleSignal(int) { g_stop_requested = 1; }

}  // namespace

int main(int argc, char** argv) {
  azookey::host::EngineConfig config;
  std::string learning_path = "azookey_learning.tsv";
  std::string user_dict_path = "azookey_user_dict.json";
  std::string mock_dict_path;
  bool pipe_mode = false;
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
      pipe_mode = true;
      if (i + 1 < argc && std::string(argv[i + 1]).rfind("--", 0) != 0) {
        pipe_name = argv[++i];
      }
    } else if (arg == "--pipe-name" && i + 1 < argc) {
      pipe_mode = true;
      pipe_name = argv[++i];
    } else if (arg == "--stdio") {
      pipe_mode = false;
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

  if (pipe_mode) {
    if (pipe_name.empty()) {
      pipe_name = azookey::ipc::DefaultPipeName();
    }

    azookey::ipc::NamedPipeServer server;
    if (!server.Start(pipe_name, [&dispatcher](const azookey::ipc::Envelope& env) {
          return dispatcher.Dispatch(env);
        })) {
      std::cerr << "error: failed to start named pipe server: " << pipe_name << std::endl;
      return 2;
    }

    std::signal(SIGINT, HandleSignal);
    std::signal(SIGTERM, HandleSignal);
    std::cerr << "named pipe listening: " << pipe_name << std::endl;
    while (!g_stop_requested) {
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

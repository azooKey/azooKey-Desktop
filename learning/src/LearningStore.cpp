#include "azookey/learning/LearningStore.h"

#include <cmath>
#include <fstream>
#include <sstream>

namespace azookey::learning {

LearningStore::LearningStore(std::string path) : path_(std::move(path)) {}

std::string LearningStore::Key(const std::string& reading, const std::string& surface) const {
  return reading + "\t" + surface;
}

bool LearningStore::Load() {
  table_.clear();
  std::ifstream ifs(path_);
  if (!ifs.is_open()) {
    return false;
  }
  std::string line;
  while (std::getline(ifs, line)) {
    std::istringstream iss(line);
    std::string reading;
    std::string surface;
    LearningRecord rec;
    if (!(std::getline(iss, reading, '\t') && std::getline(iss, surface, '\t') && (iss >> rec.weight) && (iss >> rec.last_updated_epoch_sec))) {
      continue;
    }
    table_.emplace(Key(reading, surface), rec);
  }
  return true;
}

bool LearningStore::Save() const {
  std::ofstream ofs(path_, std::ios::trunc);
  if (!ofs.is_open()) {
    return false;
  }
  for (const auto& [key, rec] : table_) {
    const auto tab = key.find('\t');
    if (tab == std::string::npos) {
      continue;
    }
    ofs << key.substr(0, tab) << '\t' << key.substr(tab + 1) << '\t' << rec.weight << ' ' << rec.last_updated_epoch_sec << '\n';
  }
  return true;
}

void LearningStore::Reset() { table_.clear(); }

void LearningStore::Observe(const std::string& reading, const std::string& surface, double alpha, uint64_t now_epoch_sec) {
  auto& rec = table_[Key(reading, surface)];
  rec.weight += alpha;
  rec.last_updated_epoch_sec = now_epoch_sec;
}


void LearningStore::ObserveCorrection(const std::string& reading,
                                      const std::string& rejected_surface,
                                      const std::string& selected_surface,
                                      double alpha,
                                      uint64_t now_epoch_sec) {
  Observe(reading, selected_surface, alpha, now_epoch_sec);

  auto& rejected = table_[Key(reading, rejected_surface)];
  rejected.weight = std::max(0.0, rejected.weight - alpha);
  rejected.last_updated_epoch_sec = now_epoch_sec;
}

double LearningStore::Score(const std::string& reading, const std::string& surface, uint64_t now_epoch_sec) const {
  const auto it = table_.find(Key(reading, surface));
  if (it == table_.end()) {
    return 0.0;
  }
  const auto& rec = it->second;
  const double days = static_cast<double>(now_epoch_sec - rec.last_updated_epoch_sec) / (60.0 * 60.0 * 24.0);
  const double decay = std::exp(-0.15 * std::max(0.0, days));
  return rec.weight * decay;
}

}  // namespace azookey::learning

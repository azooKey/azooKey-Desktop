#include "azookey/host/RequestScheduler.h"

namespace azookey::host {

uint64_t RequestScheduler::NextRequestId() { return ++request_id_; }

void RequestScheduler::Cancel(uint64_t request_id) {
  std::lock_guard<std::mutex> lock(mutex_);
  canceled_.insert(request_id);
}

bool RequestScheduler::IsCanceled(uint64_t request_id) const {
  std::lock_guard<std::mutex> lock(mutex_);
  return canceled_.find(request_id) != canceled_.end();
}

void RequestScheduler::MarkLatest(uint64_t request_id) {
  std::lock_guard<std::mutex> lock(mutex_);
  latest_ = request_id;
}

bool RequestScheduler::IsLatest(uint64_t request_id) const {
  std::lock_guard<std::mutex> lock(mutex_);
  return latest_ == request_id;
}

}  // namespace azookey::host

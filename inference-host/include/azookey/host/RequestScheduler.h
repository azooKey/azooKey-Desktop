#pragma once

#include <atomic>
#include <mutex>
#include <optional>
#include <string>
#include <unordered_set>

namespace azookey::host {

class RequestScheduler {
 public:
  uint64_t NextRequestId();
  void Cancel(uint64_t request_id);
  bool IsCanceled(uint64_t request_id) const;
  void MarkLatest(uint64_t request_id);
  bool IsLatest(uint64_t request_id) const;

 private:
  std::atomic<uint64_t> request_id_{0};
  mutable std::mutex mutex_;
  uint64_t latest_{};
  std::unordered_set<uint64_t> canceled_;
};

}  // namespace azookey::host

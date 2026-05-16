// Direct unit tests for RequestScheduler. Previously this class was exercised
// only indirectly via Dispatcher tests (TestQueryCancelBeforeReply,
// TestCancelMessageNoReply). These tests pin down the primitives the TIP
// staleness check and Host early-return code paths rely on:
//   - NextRequestId monotonic and non-zero starting at 1
//   - Cancel/IsCanceled set semantics with multiple ids
//   - MarkLatest/IsLatest single-id semantics (latest one wins)
//   - thread-safety smoke (two threads bumping NextRequestId)
//
// Platform-neutral.

#include <atomic>
#include <cstdio>
#include <stdexcept>
#include <thread>
#include <unordered_set>
#include <vector>

#include "azookey/host/RequestScheduler.h"

static void Expect(bool cond, const char* msg) {
  if (!cond) throw std::runtime_error(msg);
}

namespace host = azookey::host;

static void TestNextRequestIdMonotonic() {
  host::RequestScheduler s;
  const uint64_t a = s.NextRequestId();
  const uint64_t b = s.NextRequestId();
  const uint64_t c = s.NextRequestId();
  Expect(a == 1, "first id is 1 (++ on zero-initialized atomic)");
  Expect(b == 2, "second id is 2");
  Expect(c == 3, "third id is 3");
}

static void TestCancelMultiple() {
  host::RequestScheduler s;
  Expect(!s.IsCanceled(1), "fresh: id 1 not canceled");

  s.Cancel(1);
  s.Cancel(5);
  s.Cancel(100);

  Expect(s.IsCanceled(1), "1 marked canceled");
  Expect(s.IsCanceled(5), "5 marked canceled");
  Expect(s.IsCanceled(100), "100 marked canceled");
  Expect(!s.IsCanceled(2), "2 not canceled (not requested)");
  Expect(!s.IsCanceled(99), "99 not canceled (not requested)");

  // Cancel is idempotent — second Cancel does not error or unset.
  s.Cancel(1);
  Expect(s.IsCanceled(1), "Cancel is idempotent for already-canceled id");
}

static void TestLatestSingleId() {
  host::RequestScheduler s;
  // Default-initialized: latest_ == 0, so IsLatest(0) is true. This is fine —
  // callers always MarkLatest(NextRequestId()) before checking.
  s.MarkLatest(7);
  Expect(s.IsLatest(7), "after MarkLatest(7), 7 is latest");
  Expect(!s.IsLatest(6), "6 is not latest");
  Expect(!s.IsLatest(8), "8 is not latest");

  s.MarkLatest(9);
  Expect(s.IsLatest(9), "after MarkLatest(9), 9 is latest");
  Expect(!s.IsLatest(7), "7 is no longer latest");

  // MarkLatest with a smaller id replaces — this is by design; callers must
  // pass the freshest id and the scheduler trusts it.
  s.MarkLatest(3);
  Expect(s.IsLatest(3), "MarkLatest(3) replaces even if smaller");
  Expect(!s.IsLatest(9), "9 no longer latest after MarkLatest(3)");
}

static void TestCancelDoesNotAffectLatest() {
  host::RequestScheduler s;
  s.MarkLatest(42);
  s.Cancel(42);
  // Canceling the latest must NOT clear "latest" flag — the dispatcher
  // shouldn't accidentally treat an unrelated id as latest because the real
  // latest was canceled.
  Expect(s.IsLatest(42), "Cancel does not clear MarkLatest");
  Expect(s.IsCanceled(42), "and 42 is also canceled");
}

static void TestNextRequestIdThreadSafety() {
  host::RequestScheduler s;
  constexpr int kPerThread = 1000;
  constexpr int kThreads = 4;
  std::vector<std::thread> threads;
  std::vector<std::vector<uint64_t>> results(kThreads);

  for (int t = 0; t < kThreads; ++t) {
    threads.emplace_back([&, t] {
      results[t].reserve(kPerThread);
      for (int i = 0; i < kPerThread; ++i) {
        results[t].push_back(s.NextRequestId());
      }
    });
  }
  for (auto& th : threads) th.join();

  // Every id must be unique across threads, and the total count matches.
  std::unordered_set<uint64_t> seen;
  for (const auto& vec : results) {
    for (uint64_t id : vec) {
      Expect(seen.insert(id).second, "NextRequestId must produce unique ids");
    }
  }
  Expect(seen.size() == static_cast<size_t>(kThreads * kPerThread),
         "total count matches");
  // Ids are dense from 1..N.
  for (uint64_t i = 1; i <= static_cast<uint64_t>(kThreads * kPerThread); ++i) {
    Expect(seen.count(i) == 1, "ids form contiguous 1..N range");
  }
}

int main() {
  try {
    TestNextRequestIdMonotonic();
    TestCancelMultiple();
    TestLatestSingleId();
    TestCancelDoesNotAffectLatest();
    TestNextRequestIdThreadSafety();
    return 0;
  } catch (const std::exception& e) {
    std::fprintf(stderr, "FAIL: %s\n", e.what());
    return 1;
  }
}

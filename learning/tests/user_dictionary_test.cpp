#include <cstdio>
#include <filesystem>
#include <stdexcept>
#include <string>

#include "azookey/learning/UserDictionary.h"

static void Expect(bool cond, const char* msg) {
  if (!cond) throw std::runtime_error(msg);
}

static void TestAddLookupRemove() {
  const std::string p1 =
      (std::filesystem::temp_directory_path() / "azookey_user_dict_t_ignored.json").string();
  azookey::learning::UserDictionary dict(p1);
  azookey::learning::UserWord w1;
  w1.word = "azooKey";
  w1.ruby = "あずきい";
  w1.cid = 1285;
  w1.value = -5.0;

  azookey::learning::UserWord w2;
  w2.word = "azooKey社";
  w2.ruby = "あずきい";

  Expect(dict.Add(w1), "first add must return true");
  Expect(dict.Add(w2), "second add must return true");
  Expect(dict.Size() == 2, "size after two adds");

  const auto hits = dict.Lookup("あずきい");
  Expect(hits.size() == 2, "lookup returns 2");

  // Adding same (word, ruby) replaces in place rather than duplicating.
  azookey::learning::UserWord w1b = w1;
  w1b.value = -10.0;
  Expect(!dict.Add(w1b), "replace returns false");
  Expect(dict.Size() == 2, "replace does not change size");
  auto hits2 = dict.Lookup("あずきい");
  bool found = false;
  for (const auto& h : hits2) {
    if (h.word == "azooKey") {
      Expect(h.value.has_value() && *h.value == -10.0, "value was replaced");
      found = true;
    }
  }
  Expect(found, "replaced entry visible");

  Expect(dict.Remove("azooKey", "あずきい"), "remove existing returns true");
  Expect(dict.Size() == 1, "size after one remove");
  Expect(!dict.Remove("azooKey", "あずきい"), "remove again returns false");
  Expect(dict.Lookup("あずきい").size() == 1, "lookup after remove");
}

static void TestSaveLoadRoundTrip() {
  const char* path = "azookey_user_dict_roundtrip.json";
  std::remove(path);

  {
    azookey::learning::UserDictionary dict(path);
    azookey::learning::UserWord w;
    w.word = "日本語";
    w.ruby = "にほんご";
    w.cid = 1;
    w.mid = 2;
    w.value = 0.5;
    dict.Add(w);

    azookey::learning::UserWord w2;
    w2.word = "プログラム";
    w2.ruby = "ぷろぐらむ";
    dict.Add(w2);
    Expect(dict.Save(), "save must succeed");
  }

  azookey::learning::UserDictionary loaded(path);
  Expect(loaded.Load(), "load must succeed");
  Expect(loaded.Size() == 2, "loaded size matches");

  auto hits = loaded.Lookup("にほんご");
  Expect(hits.size() == 1, "loaded by ruby");
  Expect(hits[0].word == "日本語", "loaded word");
  Expect(hits[0].cid.has_value() && *hits[0].cid == 1, "loaded cid");
  Expect(hits[0].value.has_value() && *hits[0].value == 0.5, "loaded value");

  auto hits2 = loaded.Lookup("ぷろぐらむ");
  Expect(hits2.size() == 1, "loaded second entry");
  Expect(!hits2[0].cid.has_value(), "optional cid stays absent");
  Expect(!hits2[0].value.has_value(), "optional value stays absent");

  std::remove(path);
}

static void TestLoadMissingFileIsOk() {
  const std::string p2 =
      (std::filesystem::temp_directory_path() / "azookey_user_dict_definitely_missing.json").string();
  azookey::learning::UserDictionary dict(p2);
  Expect(dict.Load(), "missing file load returns true with empty dict");
  Expect(dict.Size() == 0, "empty after missing-file load");
}

static void TestLoadMalformedRejects() {
  const char* path = "azookey_user_dict_malformed.json";
  {
    FILE* f = std::fopen(path, "w");
    if (!f) return;
    std::fputs("not json at all", f);
    std::fclose(f);
  }
  azookey::learning::UserDictionary dict(path);
  Expect(!dict.Load(), "malformed file must return false");
  std::remove(path);
}

int main() {
  TestAddLookupRemove();
  TestSaveLoadRoundTrip();
  TestLoadMissingFileIsOk();
  TestLoadMalformedRejects();
  return 0;
}

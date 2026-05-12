#include <cstdio>
#include <fstream>
#include <stdexcept>
#include <string>

#include "azookey/core/SimpleConverter.h"

int RunRomajiTests();

void Expect(bool cond, const char* message) {
  if (!cond) {
    throw std::runtime_error(message);
  }
}

static void TestBuiltinDictionary() {
  azookey::core::SimpleConverter converter;
  const auto candidates = converter.Convert("にほん", "");
  Expect(candidates.size() >= 3, "expected 3+ candidates");
  Expect(candidates.front().surface == "日本", "expected 日本 as top candidate");

  converter.Learn("二本", "にほん");
  const auto relearned = converter.Convert("にほん", "");
  Expect(relearned.size() >= 3, "expected candidates after learning");
}

static void TestTsvLoad() {
  const char* path = "simple_converter_tsv_fixture.tsv";
  {
    std::ofstream f(path);
    f << "# comment line\n";
    f << "\n";
    f << "あずきい\tazooKey\t1.0\tuser\n";
    f << "あずきい\tあずきい\t0.4\tidentity\n";
    f << "malformed line without tabs\n";
    f << "てすと\tテスト\tnotanumber\tuser\n";  // dropped (bad score)
  }

  azookey::core::SimpleConverter converter;
  Expect(converter.LoadFromTsv(path), "LoadFromTsv must report some rows loaded");

  const auto candidates = converter.Convert("あずきい", "");
  Expect(candidates.size() == 2, "expected exactly 2 tsv rows for あずきい");
  Expect(candidates.front().surface == "azooKey", "tsv first row surface");
  Expect(candidates.front().score == 1.0, "tsv first row score");

  // Built-in entry is preserved alongside TSV entries.
  const auto nihon = converter.Convert("にほん", "");
  Expect(!nihon.empty(), "built-in entry must remain after LoadFromTsv");

  // Missing file returns false but does not throw.
  Expect(!converter.LoadFromTsv("/nonexistent/azookey_no_such_file.tsv"),
         "missing tsv must return false");

  std::remove(path);
}

static void TestPrefixFallback() {
  azookey::core::SimpleConverter converter;
  // "にほんご" is not in the built-in dictionary; "にほん" is.
  const auto candidates = converter.Convert("にほん", "");
  Expect(!candidates.empty(), "にほん should hit built-in");

  // Prefix of an existing reading: convert with shorter kana hits prefix path
  // through unrelated keys when no exact match exists. Use a reading that is
  // a clean prefix only of the built-in "とうきょう".
  const auto cands = converter.Convert("とうきょ", "");
  Expect(!cands.empty(), "prefix fallback must return at least one candidate");
}

int main() {
  RunRomajiTests();
  TestBuiltinDictionary();
  TestTsvLoad();
  TestPrefixFallback();
  return 0;
}

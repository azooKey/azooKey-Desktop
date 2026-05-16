# Windows TSF + Inference Host デバッグ

## Build

Windows (推奨):

```powershell
cmake -S . -B build -G Ninja -DCMAKE_BUILD_TYPE=Debug
cmake --build build
ctest --test-dir build --output-on-failure
```

または Visual Studio Generator:

```powershell
cmake -S . -B build -G "Visual Studio 17 2022" -A x64
cmake --build build --config Debug
ctest --test-dir build -C Debug --output-on-failure
```

Linux/macOS では `tsf-tip/` 配下は自動スキップ。`core/` `ipc/` `learning/`
`inference-host/` `bench/` のみ単体検証可能。

## Bench

```powershell
./build/bench/azookey_bench.exe
```

出力例: `p50_ms=... p95_ms=... p99_ms=...`

## 手動確認（Windows）

1. `build/inference-host/azookey_inference_host.exe --pipe` で Host を起動。
   - `--cpu` / `--backend cpu` を明示すれば CPU バックエンド（既定）。
   - `--mock-dict <path.tsv>` で固定辞書を追加可能。
2. **登録方法は 2 通り**:
   - `regsvr32 build/tsf-tip/azookey_tsf_tip.dll` だけで `DllRegisterServer`
     により CLSID + Profile + DisplayAttribute Provider まで HKCU に登録される。
   - `scripts/register.ps1` は上記 `regsvr32` 呼び出しに加えて Host EXE の
     Run キー登録（自動起動）まで行う。MSIX 化までは PS1 経由を推奨。
3. Notepad でローマ字入力しプレエディット表示を確認（アンダーライン付き）。
4. Space で候補、↑↓ で選択、Enter or 1〜9 で確定、Esc でキャンセル。
5. 候補確定後、同じ reading を再変換し、確定済み候補が上位に来る（学習効果）。
6. Chrome / VSCode / Office でも基本操作確認。

## ログ収集

現状:

- TIP 側: `OutputDebugStringA`（DebugView または WinDbg で観測）。
  - `[azooKey TIP] IPC: <msg>` フォーマット。
- Host 側: stderr。`--pipe` 起動時は `named pipe listening: <name>` 表示後に
  Dispatcher 経路を待ち受け。

予定 (Phase D / M11):

- TIP/Host とも `%LOCALAPPDATA%\azooKey\logs\tip.log` / `host.log` に
  JSON Lines 形式で出力。

## CI

`.github/workflows/windows.yml` で windows-latest + msvc-dev-cmd + Ninja:

1. configure（log を tee）
2. build（log を tee）
3. 各 `*_tests.exe` を個別実行し、失敗時 `::error::` annotation
4. PR には `configure.log` / `build.log` / `test_report.md` の tail を
   github-script で自動コメント
5. `test_report.md` artifact を常時アップロード

ローカルで CI と同じ流れを再現:

```powershell
cmake -S . -B build -G Ninja -DCMAKE_BUILD_TYPE=Debug
cmake --build build
Get-ChildItem -Path build -Recurse -Filter "*_tests.exe" | ForEach-Object { & $_.FullName }
```

## 典型トラブル

- **TIP は動くが候補が遅延**: Host 未起動 / 名前付きパイプ接続失敗を疑う。
  TIP は Activate 後 5 秒間（250ms slice）リトライする。
  Host stderr に `named pipe listening: \\.\pipe\azookey-host` が出ているか確認。
- **候補が反転する（古い候補が上書きされる）**: `ipc_pending_id_` の比較で
  staleness check しているはず（`tsf-tip/src/TextService.cpp:717`）。
  DebugView で `IPC: stale response for req_id=N, discarding` が出るか確認。
- **確定時に空文字が入る**: `shown_candidates_` がスナップショットされる前に
  TSF EditSession が拒否（lock denial）された可能性。
  DebugView で `[azooKey TIP]` のフォローログ確認。
- **`DllRegisterServer` 失敗（`SELFREG_E_CLASS`）**: HKCU 書き込み権限を確認。
  `regsvr32` は HKCU 配下のみ書くので elevation 不要。
- **学習が反映されない**: `azookey_learning.tsv` の生成パス（Host CWD）と
  permission を確認。CommitObservation 受信は Host stderr / Dispatcher テストで確認。
- **学習暴走**: `learning_alpha` を下げる（既定 0.8）。`LearningStore::Reset` または
  TSV を削除して再起動。

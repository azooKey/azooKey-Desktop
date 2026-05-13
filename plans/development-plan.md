# azooKey-Desktop Windows 版 v1.0 開発プラン

## Context

azooKey-Desktop の Windows 版は `plans/windows-port-roadmap.md` で M0〜M12 が
定義されている。表記上は「M0 完了・M1 進行中・M2〜M12 未着手」となっているが、
実装の実態を 2026-05 時点で再点検したところ、バックエンド側（IPC・推論ホスト・
学習機構・ローマ字かな変換コア）はすでに完成水準にあり、クリティカルパスは
TIP 側の Composition・候補 UI・登録周りと、M8 (Zenzai)・M11 (パッケージング)
に集中していることが判明した。

本プランは Windows 版 v1.0（MSIX 配布可能な最小 IME）リリースまでの実行順を
再構築する。macOS 版（Issue #181）は本プランの対象外。

詳細なマイルストーン定義と実装現状は `plans/windows-port-roadmap.md` を参照。
**本ファイルはフェーズ実行計画のみを管理する。各マイルストーンのステータスは `plans/windows-port-roadmap.md` を正典とする。**

## 実装実態の再評価サマリ（2026-05 時点のスナップショット）

> 最新ステータスは `plans/windows-port-roadmap.md` を参照。以下は本プラン策定時点の状況。

| MS | 表記 | 実態 | 残作業 |
|---|---|---|---|
| M0 | 完了 | ✅ 完了 | なし |
| M1 IPC 疎通 | 進行中 | ✅ ほぼ完了 | TIP 側 NamedPipeClient テストを CTest に統合 |
| M2 TIP 登録 | 未着手 | ⚠️ 部分実装 | `DllRegisterServer`/`DllUnregisterServer` 本実装、register.ps1 強化 |
| M3 Composition 表示 | 未着手 | ⚠️ 基盤完成・本体未実装 | `EditSession::DoEditSession` の本実装（TODO @ `tsf-tip/src/TextService.cpp:241`） |
| M4 モック候補生成 | 未着手 | ✅ Host 完成 | TIP→Host の `QueryCandidates` 配線 |
| M5 候補 UI | 未着手 | ❌ 未着手 | 方式決定（`ITfCandidateListUIElement` vs 自前 HWND）+ 実装 |
| M6 Commit/Observation | 未着手 | ⚠️ Host 完成 | TIP からの送信処理 |
| M7 再ランキング学習 | 未着手 | ✅ ほぼ完成 | 実機検証のみ |
| M8 Zenzai ロード | 未着手 | ⚠️ スケルトン | llama.cpp バインディング選定 + 本実装 |
| M9 ユーザー辞書 | 未着手 | ✅ バックエンド完成 | M11 で UI 接続 |
| M10 Cancel | 未着手 | ⚠️ Host 完成 | TIP 側 `request_id` ガード |
| M11 設定 UI/パッケージング | 未着手 | ❌ 未着手 | フレームワーク選定 + MSIX |
| M12 CI と署名配布 | 未着手 | ❌ 未着手 | Windows ランナー + 署名 |

## フェーズ計画

### Phase A: TIP 基盤完成 — 「タイプしたら候補が往復する」(2〜3 週、M3 は 1〜2 週かかる場合あり)

目的: Windows 上で実機 IME としてローマ字を打鍵し、Host から候補を取得して
ログで往復確認できる体験を成立させる。

**前提条件（Phase A 着手前に完了させること）**:
- Win11 VM (Hyper-V または UTM) の構築
- DebugView または WinDbg のインストール
- `cmake -S . -B build && cmake --build build && ctest --test-dir build` の通過確認

1. **M1 仕上げ** — `tsf-tip/` 向けに NamedPipeClient ラウンドトリップの自動
   テストを `ipc/tests/` パターンで追加し、CTest に統合。`StartDebugIpcProbe`
   の手動確認から回帰可能なテストに昇格。
2. **M2 完了** — `tsf-tip/src/DllMain.cpp` の `DllRegisterServer` /
   `DllUnregisterServer` を実装。CLSID `{71EE04FA-B35D-4EB8-87A1-582D44A9A58C}`、
   Profile GUID `{A8F74D91-8DF3-4DA1-B80B-01F7C73D4A90}`、Lang `0x0411` を
   `scripts/register.ps1` と整合。register.ps1 のエラー処理強化。
3. **M3 完了**（TSF EditSession に慣れていない場合は 1〜2 週を見込む）—
   `tsf-tip/src/TextService.cpp:241` の TODO を解消。
   `ITfContext::RequestEditSession` 経由で `ITfComposition` を保持し、
   `preedit_kana_` を `SetText` で挿入。`EnumDisplayAttributeInfo` /
   `GetDisplayAttributeInfo` を本実装し、アンダーラインを表示。
4. **M4 配線** — `OnKeyDown` から条件を満たした時点で
   `Envelope{type=QueryCandidates, payload=QueryCandidatesRequest{kana, context}}`
   を NamedPipeClient で送信し、応答を保持。Host 側 `Dispatcher` は完成済み。

検証: クリーン Win11 VM で `regsvr32` + `scripts/register.ps1` + `inference-host.exe --pipe` を起動し、メモ帳で `nihongo` を打鍵してアンダーライン付き preedit が表示され、Host の stderr に `QueryCandidates` 受信が記録されること。

### Phase B: 候補選択と確定動線 — 「候補から日本語を選んで確定できる」(2〜3 週)

5. **M5 候補 UI** — Phase A 最終週にプロトタイピングで
   `ITfCandidateListUIElement` 方式と自前 HWND popup 方式を 2〜3 日比較し決定。
   Caret 追従、↑↓選択、Enter 確定、Esc キャンセルを満たす。
6. **M6 Commit/Observation 配線** — `TextService` で確定時に
   `CommitObservationRequest` を送る。Host 側 `Dispatcher::HandleCommitObservation`
   (実装済み) が `LearningStore::Observe` を呼ぶ。
7. **M10 Cancel 配線** — `TextService` 側で最新 `request_id` のみ EditSession
   に反映するガードと、古い preedit 確定時の `Cancel` メッセージ送信を実装。
   Host 側 `RequestScheduler::Cancel` (実装済み) と接続。

検証: 早打ちで候補が逆転しない、確定直後に同 reading で再変換すると上位順位
が変動（M7 効果）、`learning.db` 相当の TSV に観測行が増える。

### Phase C: 実 Zenzai と辞書 UI のつなぎ込み (3〜5 週)

8. **M8 Zenzai 統合** — `inference-host/src/InferenceEngine.cpp::LoadModel`
   の本実装。llama.cpp の C-API バインディングを採用、CMake オプションで
   `AZOOKEY_BACKEND=cpu|cuda` を切替。配布サイズと初回起動時間を `bench/` で
   計測。モデル未配置時は `SimpleConverter` フォールバックを維持。
   `docs/zenzai-gpu-route.md` を実装と整合させる。
9. **M9 ユーザー辞書ランタイム反映** — `AddUserWord`/`RemoveUserWord`
   （Host 側完成済み）を TIP もしくは設定 UI から呼べる経路を作る。
   今フェーズではコマンドラインまたはデバッグ UI で十分。

検証: gguf 配置で `LoadModel` 成功、未配置で起動継続、CPU/GPU 切替が
`--backend` で効く、ユーザー辞書追加が次の `QueryCandidates` で即反映。

### Phase D: 配布可能化 — v1.0 リリースゲート (4〜6 週)

10. **M11 設定 UI とインストーラ** — フレームワークは WinUI 3 を第一候補とし、
    Phase C 中に 1〜2 日のスパイクで WPF/Tauri と比較してから着手。設定アプリ
    は TIP/Host と別プロセス、IPC 経由で Host 設定（Zenzai ON/OFF、
    ユーザー辞書）を変更。配布は MSIX（ユーザースコープ自動登録、
    アンインストールでの登録解除）。
11. **M12 CI と署名配布** — `.github/workflows/` に Windows ランナーを追加
    （M1〜M10 のテストを Windows でも実行）、署名ステップ、タグ push で MSIX
    を Release に上げる。

検証: クリーン Win11 VM での MSIX インストール → IME 選択 → 入力 → 確定 →
アンインストールでクリーン状態に戻る。CI 緑、タグ push 時に署名済み MSIX が
自動公開。

## 直近 (Phase A) で触るファイル

- `tsf-tip/src/TextService.cpp` — `EditSession::DoEditSession` の本実装
  （現状 241 行目に TODO）、`OnKeyDown` に `QueryCandidates` 送信を追加
- `tsf-tip/src/DllMain.cpp` — `DllRegisterServer` / `DllUnregisterServer`
- `ipc/tests/` — TIP クライアント側ハンドシェイクの自動テスト追加
- `scripts/register.ps1` / `scripts/unregister.ps1` — エラー処理強化と
  `DllRegisterServer` との整合
- `plans/windows-port-roadmap.md` — 本プランの結果を反映（本コミットで適用済み）

## 再利用すべき既存実装

- `ipc/src/NamedPipeTransport.cpp` の `NamedPipeClient::Connect` —
  TIP 側で `StartDebugIpcProbe` (`tsf-tip/src/TextService.cpp:21-81`) と同じ
  呼び出し方を本処理にも適用
- `ipc/src/Payloads.cpp` の `Build*Request` / `Parse*Response` 群 —
  メッセージ構築を再実装しない
- `core/src/RomajiKanaConverter.cpp` — `OnKeyDown` の文字蓄積はすでに
  `romaji_.Feed()` を通している。M3 ではこの結果をそのまま EditSession に流す
- `inference-host/src/Dispatcher.cpp::HandleQueryCandidates`（実装済み）—
  TIP 側追加実装で即座に往復可能

## 検証手順（Phase A 完了時点で実施）

1. **ビルド**: `cmake -S . -B build -DAZOOKEY_BUILD_TESTS=ON && cmake --build build`
2. **ユニットテスト**: `ctest --test-dir build --output-on-failure` で
   IPC/Core/Learning/Host のテストが緑であること
3. **Windows 実機テスト**（Win11 VM 推奨）:
   - `scripts/register.ps1` で TIP DLL を登録
   - `inference-host.exe --pipe` を別プロセスで起動
   - メモ帳で azooKey を選択し、`nihongo` 等を入力して preedit が表示される
   - Host の stderr ログに `QueryCandidates` 受信が記録される
   - `scripts/unregister.ps1` でクリーンに解除される
4. **ログ確認**: TIP は `OutputDebugStringA`（DebugView で確認）、Host は
   stderr — Phase D で `%LOCALAPPDATA%\azooKey\logs\` への JSON Lines 出力に切替

## リスクと対応

| リスク | 影響 | 対応 |
|---|---|---|
| Windows 実機/VM デバッグ環境が未整備 | Phase A 全工程の検証が滞る | 最優先で Win11 VM (Hyper-V or UTM) と DebugView を整備 |
| llama.cpp バインディング選定 (M8) | 配布サイズ・初回起動時間に直結 | Phase B 中に 2〜3 日の PoC で確定 (`docs/zenzai-gpu-route.md` 更新) |
| 候補 UI 方式選定 (M5) | Phase B 着手のブロッカー | Phase A 最終週にスパイクで決定 |
| MSIX 配布 (M11) のユーザースコープ登録 | アンインストール後にレジストリが残る | スパイク段階で register.ps1 の登録項目を一覧化し、MSIX manifest 化 |

## このプランの範囲外

- macOS 版 v1.0（Issue #181 で別管理）
- `plans/segment_edit.md` の文節エディット機能（現状 macOS 向けの上流計画、Windows MVP 後）
- `Core/Sources/Core/InputUtils/InputState.swift:271,336` の FIXME（macOS 側）
- Linux 版（コミュニティフォーク `fcitx5-hazkey` で対応）

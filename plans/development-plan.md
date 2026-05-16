# azooKey-Desktop Windows 版 v1.0 開発プラン

## Context

azooKey-Desktop の Windows 版は `plans/windows-port-roadmap.md` で M0〜M12 が
定義されている。2026-05 時点の実装実態を再点検したところ、**Phase A / Phase B
が完了** し、`tsf-tip/` 側の COM 登録・Composition・候補 UI・確定・観測送信・
Cancel・staleness ガードまで動作する MVP に到達した。残るクリティカルパスは
**M8 (Zenzai 実機統合) と M11 (設定 UI + MSIX パッケージング) と
M12 (CI 強化 + 署名配布)** の 3 つに集中している。

本プランは Windows 版 v1.0（MSIX 配布可能な最小 IME）リリースまでの実行順を
再構築する。macOS 版（Issue #181）は本プランの対象外。

詳細なマイルストーン定義と実装現状は `plans/windows-port-roadmap.md` を参照。
**本ファイルはフェーズ実行計画のみを管理する。各マイルストーンのステータスは `plans/windows-port-roadmap.md` を正典とする。**

## 実装実態の再評価サマリ（2026-05 時点のスナップショット）

> 最新ステータスは `plans/windows-port-roadmap.md` を参照。以下は本プラン策定時点の状況。

| MS | 表記 | 実態 | 残作業 |
|---|---|---|---|
| M0 廃止資産削除 | 完了 | ✅ 完了 | なし |
| M1 IPC 疎通 | 完了 | ✅ 完了 | なし（`ipc/tests/tip_client_ipc_test.cpp` で回帰保護） |
| M2 TIP 登録 | 完了 | ✅ 完了 | なし（`DllRegisterServer/DllUnregisterServer` 実装済み） |
| M3 Composition 表示 | 完了 | ✅ 完了 | なし（`DoEditSession` 本実装＋display attribute） |
| M4 モック候補生成 | 完了 | ✅ 完了 | なし（IPC worker thread で配線） |
| M5 候補 UI | 完了 | ✅ 完了 | なし（`CandidateWindow` 実装済み） |
| M6 Commit/Observation | 完了 | ✅ 完了 | なし（`PostCommitObservation` 配線） |
| M7 再ランキング学習 | 完了 | ✅ ほぼ完成 | 実機長期運用での挙動確認 |
| M8 Zenzai ロード | 未着手 | ⚠️ スケルトン | llama.cpp バインディング選定 + 本実装 |
| M9 ユーザー辞書 | バックエンド完了 | ⚠️ UI 未接続 | M11 で設定 UI から接続 |
| M10 Cancel | 完了 | ✅ 完了 | なし（in-flight cancel + staleness check） |
| M11 設定 UI/パッケージング | 未着手 | ❌ 未着手 | フレームワーク選定 + MSIX |
| M12 CI と署名配布 | 部分着手 | ⚠️ build/test のみ | 署名・MSIX アーティファクト・タグ release 自動化 |

## フェーズ計画

### Phase A: TIP 基盤完成 ✅ 完了（mainマージ済み: `603cd1d`）

実機 IME としてローマ字を打鍵し、Host から候補を取得して候補ウィンドウに表示するまで動作。

### Phase B: 候補選択と確定動線 ✅ 完了（mainマージ済み: `603cd1d`）

候補選択・確定・観測送信・早打ち耐性（in-flight cancel + staleness）まで動作。

### Phase C: 実 Zenzai と辞書 UI のつなぎ込み (3〜5 週) 🚧 着手対象

1. **M8 Zenzai 統合** — `inference-host/src/InferenceEngine.cpp::LoadModel`
   の本実装。llama.cpp の C-API バインディングを採用、CMake オプションで
   `AZOOKEY_BACKEND=cpu|cuda` を切替。配布サイズと初回起動時間を `bench/` で
   計測。モデル未配置時は `SimpleConverter` フォールバックを維持。
   `docs/zenzai-gpu-route.md` を実装と整合させる。
2. **M9 ユーザー辞書ランタイム反映** — `AddUserWord`/`RemoveUserWord`
   （Host 側完成済み）を TIP もしくは設定 UI から呼べる経路を作る。
   今フェーズではコマンドラインまたはデバッグ UI で十分。

**Phase C 着手前タスク**:
- llama.cpp バインディング選定スパイク（2〜3 日、配布サイズ・初回起動時間を `bench/` で計測）
- `core/IConverter` 抽象は既に存在 — Zenzai converter は `IConverter` 実装として差し替え

検証: gguf 配置で `LoadModel` 成功、未配置で起動継続（`SimpleConverter` フォールバック）、CPU/GPU 切替が `--backend` で効く、ユーザー辞書追加が次の `QueryCandidates` で即反映。

### Phase D: 配布可能化 — v1.0 リリースゲート (4〜6 週)

3. **M11 設定 UI とインストーラ** — フレームワークは WinUI 3 を第一候補とし、
   Phase C 中に 1〜2 日のスパイクで WPF/Tauri と比較してから着手。設定アプリ
   は TIP/Host と別プロセス、IPC 経由で Host 設定（Zenzai ON/OFF、
   ユーザー辞書）を変更。配布は MSIX（ユーザースコープ自動登録、
   アンインストールでの登録解除）。
4. **M12 CI 完成と署名配布** — 現状 `.github/workflows/windows.yml` で Windows
   ランナーで build/test まで実施中。残: コード署名ステップ、タグ push 時の
   MSIX 自動 Release 公開、submodule 配信ポリシー確定。

検証: クリーン Win11 VM での MSIX インストール → IME 選択 → 入力 → 確定 →
アンインストールでクリーン状態に戻る。CI 緑、タグ push 時に署名済み MSIX が
自動公開。

## 直近 (Phase C) で触るファイル

- `inference-host/src/InferenceEngine.cpp` — `LoadModel` の本実装、Zenzai converter 配線
- `inference-host/include/azookey/host/InferenceEngine.h` — モデル状態の保持・解放API
- `core/include/azookey/core/IConverter.h` — Zenzai 実装が嵌まることを確認（変更不要が望ましい）
- `bench/` — Zenzai ロード時間・推論レイテンシを計測
- `CMakeLists.txt` — `AZOOKEY_BACKEND=cpu|cuda` オプション
- `docs/zenzai-gpu-route.md` — 実装結果と整合
- `inference-host/tests/` — Zenzai converter のモック実装でテスト追加

## 再利用すべき既存実装

- `core/include/azookey/core/IConverter.h` — Zenzai は `IConverter` 実装として
  `SimpleConverter` と差し替え可能
- `inference-host/src/InferenceEngine.cpp` の reranker・user_dict 経由パイプライン —
  Zenzai 出力にもそのまま適用可能
- `ipc/src/Payloads.cpp` の `LoadModelRequest/Response` — 既に CMake オプション
  `--backend cuda|cpu` をリクエストで指定する設計

## 検証手順（Phase C 完了時点で実施）

1. **ビルド**: `cmake -S . -B build -DAZOOKEY_BUILD_TESTS=ON -DAZOOKEY_BACKEND=cpu && cmake --build build`
2. **ユニットテスト**: `ctest --test-dir build --output-on-failure` で
   IPC/Core/Learning/Host/TSF-TIP の全テストが緑であること
3. **Windows 実機テスト**（Win11 VM 推奨）:
   - `scripts/register.ps1` で TIP DLL を登録（`DllRegisterServer` 経由）
   - `azookey_inference_host.exe --pipe --backend cpu` で起動
   - gguf を `%LOCALAPPDATA%\azooKey\models\` に配置し、`LoadModel` が成功すること
   - gguf を削除し起動した場合に `SimpleConverter` にフォールバックすること
   - メモ帳で `nihongo` 等を入力し、Zenzai 候補が出ること
4. **GPU 経路**: `--backend cuda` で起動し、CUDA 初期化失敗時は CPU にフォールバック
5. **ベンチ**: `./build/bench/azookey_bench.exe` の p50/p95 が CPU/GPU で許容内か
6. **`unregister.ps1`**: クリーン解除確認

## リスクと対応

| リスク | 影響 | 対応 |
|---|---|---|
| llama.cpp バインディング選定 (M8) | 配布サイズ・初回起動時間に直結 | Phase C 着手スパイクで確定 (`docs/zenzai-gpu-route.md` 更新)、`bench/` で計測 |
| CUDA SDK の配布制約 | MSIX のサイズ膨張・GPU なし PC でのフォールバック品質 | バックエンドは optional payload、CPU を default に、ggml-cuda は別 MSIX オプションパッケージで検討 |
| MSIX 配布 (M11) のユーザースコープ登録 | アンインストール後にレジストリが残る | 既に `DllRegisterServer` で HKCU 登録に統一済み。MSIX manifest で `comServer` を宣言し、アンインストール時に確実に消えることを VM テストで確認 |
| 設定 UI フレームワーク選定 (M11) | 配布サイズ・依存ランタイム | Phase C 中に WinUI 3 / WPF / Tauri を 1〜2 日比較スパイク |
| 署名証明書の調達 (M12) | リリース日に直結 | Phase D 着手前に EV/OV 証明書の手当てを並行 |

## このプランの範囲外

- macOS 版 v1.0（Issue #181 で別管理、`legacy/` 配下に保全）
- `plans/segment_edit.md` の文節エディット機能（現状 macOS 向けの上流計画、Windows MVP 後）
- `legacy/Core/Sources/Core/InputUtils/InputState.swift:271,336` の FIXME（macOS 側）
- Linux 版（コミュニティフォーク `fcitx5-hazkey` で対応）

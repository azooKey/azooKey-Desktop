# azooKey-Desktop Windows ポート: マイルストーン・ロードマップ

本書は Windows 版 azooKey-Desktop の段階的開発計画。前提となる方針・構成は
以下を参照:

- `docs/windows-port-asset-audit.md`: 既存 macOS 資産の流用可否棚卸し
- `docs/windows-tsf-host-architecture.md`: TSF TIP + Inference Host 分離設計

本書はそれらを前提に、「いつ何をどの順で」「何をもって完了とするか」を定める。

## 全体目標

- **MVP**: Windows 10/11 上で TSF 経由のローマ字入力 → かな漢字変換 → 確定までの
  最小フローが動作する IME。
- **配布形態**: ユーザーごとインストールの MSIX または MSI。
- **コア方針**: TIP (in-proc COM DLL) はキー処理と UI のみ担当し、推論・学習は
  Named Pipe 経由で `inference-host` (per-user 常駐 EXE) に委譲する。

## 現在のソース構成（M0 時点）

| ディレクトリ        | 役割                                                     | 現状                                        |
|---------------------|----------------------------------------------------------|---------------------------------------------|
| `core/`             | OS 非依存の変換コア（C++）                               | スケルトン + tests あり                     |
| `ipc/`              | Named Pipe 上の JSON + length-prefix プロトコル          | `Messages.cpp` あり、tests あり             |
| `learning/`         | 頻度 + 時間減衰の再ランキング永続化                      | `LearningStore.cpp` / `Reranker.cpp` あり   |
| `inference-host/`   | 常駐 EXE。モデル推論・候補生成・学習集約                 | `InferenceEngine.cpp` / `RequestScheduler.cpp` / `main.cpp` あり |
| `tsf-tip/`          | TIP 本体 (COM DLL)                                       | `DllMain.cpp` / `TextService.cpp` / `TextServiceFactory.cpp` あり |
| `bench/`            | パフォーマンス計測                                       | 別途                                        |
| `Core/` (Swift)     | macOS 側の仕様参照源                                     | 移植対象ではなく仕様参照のみ                |

## マイルストーン

依存関係: 矢印は「→ が前提」。並行可能なものは並列に記載。

```
M0 ─→ M1 ─→ M2 ─→ M3 ─→ M4 ─→ M5 ─→ M6 ─→ M11 ─→ M12
              └→ M7 (並行)
              └→ M8 (M4 完了後に並行)
              └→ M9 (M6 完了後に並行)
              └→ M10 (M5 完了後に並行)
```

### M0: 廃止資産の削除 ✅ 完了

- **目的**: 旧 `ime-tsf/` ディレクトリを削除し、現行の `tsf-tip/` のみが
  ビルド対象になっている状態を明示化。
- **変更**: `ime-tsf/` 8 ファイルを削除（コミット `6a3dd7f`）。
- **受け入れ条件**:
  - `ime-tsf` への参照がリポジトリ全体に残らない
  - ルート `CMakeLists.txt` のサブディレクトリが現行構成と一致

### M1: IPC ハンドシェイク疎通 ✅ ほぼ完了（仕上げのみ残）

- **目的**: TIP と Host 間で Named Pipe を確立し `Handshake` + `Ping` が
  往復するところまで到達。
- **変更対象**: `ipc/`, `inference-host/main.cpp`, `tsf-tip/src/TextService.cpp`
- **実装範囲**:
  - Named Pipe サーバ (Host) / クライアント (TIP) 実装
  - `Handshake(version, capabilities)` と `Ping`/`Health` のメッセージ実装
  - バージョン不一致時の切断ポリシー
- **現状**:
  - `ipc/src/NamedPipeTransport.cpp` (522行) はサーバ/クライアント・DACL・長さプリフィックスフレーミングまで実装済み。
  - `ipc/src/Messages.cpp` / `ipc/src/Payloads.cpp` で全 14 種のメッセージ型と build/parse 関数を定義済み。
  - `ipc/tests/named_pipe_transport_test.cpp`, `messages_test.cpp`, `payloads_test.cpp` で Handshake/Ping のラウンドトリップを検証。
  - `inference-host/src/main.cpp` は `--pipe` 起動で `NamedPipeServer` を立ち上げ、`Dispatcher` を MessageHandler として登録済み。
  - `tsf-tip/src/TextService.cpp` の `StartDebugIpcProbe` (21-81 行) で Activate 後に Handshake/Ping を実機確認できる。
- **残作業**:
  - `tsf-tip/` 側 NamedPipeClient のラウンドトリップを CTest に統合し、回帰可能なテストに昇格する。
- **受け入れ条件**:
  - `ipc/tests` に Handshake/Ping のラウンドトリップ単体テストが通る ✅
  - TIP 側 NamedPipeClient のテストが CTest に統合される

### M2: TIP 登録と最小キーボード活性化 ⚠️ 部分実装

- **目的**: Windows 側に TIP として登録され、IME バーから選択でき、
  キーイベントが TIP に届く。
- **変更対象**: `tsf-tip/src/Registrar` 相当の処理（M0 で削除した旧資産の
  正しい実装を `tsf-tip/` 側に再構築）、`DllMain.cpp`、レジストリ登録スクリプト。
- **実装範囲**:
  - `regsvr32` / インストーラ向けの自己登録ロジック
  - 言語バー有効化
  - `ITfKeyEventSink` 接続
- **現状**:
  - `tsf-tip/src/TextService.cpp` の `Activate`/`Deactivate`、`OnTestKeyDown`/`OnKeyDown` まで実装済み。A-Z は `romaji_.Feed()` で蓄積。
  - `scripts/register.ps1` / `scripts/unregister.ps1` はレジストリ書込みと Host の Run キー登録を実装済み（CLSID `{71EE04FA-B35D-4EB8-87A1-582D44A9A58C}`、Profile GUID `{A8F74D91-8DF3-4DA1-B80B-01F7C73D4A90}`、Lang `0x0411`）。
  - `tsf-tip/src/DllMain.cpp` の `DllRegisterServer`/`DllUnregisterServer` は `S_OK` を返すスタブのみ。
- **残作業**:
  - `DllRegisterServer`/`DllUnregisterServer` を本実装し、`regsvr32` 経由でも整合する自己登録ロジックを書く。
  - `scripts/register.ps1` のレジストリ書込みエラーハンドリング強化。
- **受け入れ条件**:
  - 開発機にビルド成果物をインストールして言語切替で azooKey が選べる
  - キー押下が `ITfKeyEventSink::OnKeyDown` まで到達することをログで確認（確認済み）

### M3: Composition / Preedit 表示 ⚠️ 基盤完成・本体未実装

- **目的**: ローマ字キー入力が preedit としてアプリ側 (例: メモ帳) に
  表示され、Backspace で削除でき、ESC で破棄できる。
- **変更対象**: `tsf-tip/src/TextService.cpp` 内の EditSession 周り。
- **実装範囲**:
  - `ITfCompositionSink` / `ITfComposition` の保持
  - `RequestEditSession` 経由でのテキスト挿入・置換
  - ローマ字 → かな変換テーブル（最低限）
- **現状**:
  - `core/src/RomajiKanaConverter.cpp` (119行) でローマ字→かなは完全実装（小書きっ・ん・長音対応）。`tests/romaji_kana_converter_test.cpp` で `konnichiha`→`こんにちは`, `gakkou`→`がっこう` 等を検証済み。
  - `TextService::EditSession::DoEditSession` (`tsf-tip/src/TextService.cpp:241`) は `// TODO: update composition range + display attribute.` のまま `S_OK` を返す。
  - `EnumDisplayAttributeInfo` / `GetDisplayAttributeInfo` は `E_NOTIMPL`。
- **残作業**:
  - `ITfContext::RequestEditSession` 経由で `ITfComposition` を作成・保持し、`preedit_kana_` を `SetText` でレンジ挿入する本実装。
  - Display attribute (アンダーライン) の `EnumDisplayAttributeInfo`/`GetDisplayAttributeInfo` 実装。
- **受け入れ条件**:
  - 「ka」「ki」等の入力で「か」「き」がアンダーライン付きで表示される
  - ESC で composition がクリアされる
  - Backspace で 1 文字戻る

### M4: モック候補生成（Host 経由） ✅ Host 側完成・TIP 配線のみ残

- **目的**: Host 側に固定テーブルベースの簡易変換を実装し、
  `QueryCandidates` の往復が成立する。
- **変更対象**: `inference-host/src/InferenceEngine.cpp`,
  `inference-host/src/RequestScheduler.cpp`, `ipc/`
- **実装範囲**:
  - `QueryCandidates(request_id, kana, context)` の Host 実装
  - 固定テーブル or 簡易 N-best
  - `request_id` 追跡と古い ID の破棄
- **現状**:
  - `inference-host/src/InferenceEngine.cpp` (119行) で `QueryCandidates` を実装。`atomic<bool>* cancel` でキャンセル対応。
  - `inference-host/src/RequestScheduler.cpp` (27行) で `NextRequestId`/`Cancel`/`IsCanceled`/`MarkLatest`/`IsLatest` を実装。
  - `inference-host/src/Dispatcher.cpp` (183行) で全 9 ハンドラ実装済み（`Handshake`/`Ping`/`Health`/`LoadModel`/`QueryCandidates`/`Cancel`/`CommitObservation`/`AddUserWord`/`RemoveUserWord`）。
  - `core/src/SimpleConverter.cpp` (164行) で固定辞書テーブル + TSV ロード + prefix fallback + bigram context bonus + `Learn()` を実装。
  - `inference-host/tests/engine_test.cpp` で `QueryWithLearningBoost`, `UserDictionaryInjection`, `CancelEarlyReturn` を検証済み。
- **残作業**:
  - TIP 側で `OnKeyDown` から `QueryCandidatesRequest` を `NamedPipeClient` 経由で送信し、応答を保持する配線。
- **受け入れ条件**:
  - `inference-host/tests` で固定 kana → 期待候補リストが返る（確認済み）
  - TIP 側で `OnKeyDown` から `QueryCandidatesRequest` を `NamedPipeClient` 経由で送信し、TIP デバッグログで候補リストが Host から受信されること

### M5: 候補 UI 表示

- **目的**: Space キーで候補ウィンドウが表示され、↑/↓ で選択、Enter で確定。
- **変更対象**: `tsf-tip/` 内の Candidate UI (新規)
- **実装範囲**:
  - `ITfCandidateListUIElement` 実装 or 自前 popup window
  - キャレット位置に追従するアンカリング
  - 候補配列の Host 結果からの差し替え
- **受け入れ条件**:
  - 「nihongo」入力 → Space で「日本語」等の候補が出る
  - 矢印キーで選択移動、Enter で確定、ESC でキャンセル

### M6: Commit と Observation ⚠️ Host 側完成・TIP 配線のみ残

- **目的**: 確定動作で composition が commit され、学習用 observation が
  Host に通知される。
- **変更対象**: `tsf-tip/`, `inference-host/`, `learning/`
- **実装範囲**:
  - `CommitObservation(context, chosen_candidate, shown_candidates)` 送信
  - Host 側で `learning/LearningStore` に書き込み
- **現状**:
  - Payloads.cpp に `CommitObservationRequest` / `Response` 定義済み。
  - `Dispatcher::HandleCommitObservation` で `LearningStore::Observe` + `Save` を実行。
  - `learning/src/LearningStore.cpp` (83行) は重み累積 + 時間減衰 + TSV 永続化を実装済み。
- **残作業**:
  - TIP 側で確定時に `CommitObservationRequest` を送信する経路。
- **受け入れ条件**:
  - 確定時にアプリへ最終テキストが入る
  - `learning.db` 相当に observation 行が増える（Host 単体テスト済み、TIP 配線後に E2E 確認）

### M7: 学習による再ランキング ✅ ほぼ完成

- **目的**: M6 で記録した observation を `Reranker` が読み、次回以降の
  候補順位に反映する。
- **前提**: M4 完了
- **変更対象**: `learning/src/Reranker.cpp`, `inference-host/`
- **現状**:
  - `learning/src/Reranker.cpp` (25行) で `Apply(reading, candidates, now_epoch_sec)` を実装。`LearningStore::Score` (時間減衰 `exp(-0.15 * days)`) を足して `stable_sort`。
  - `InferenceEngine::QueryCandidates` のパイプラインに組み込み済み。
  - `learning/tests/learning_test.cpp` で重み付け→減衰→再ランクを検証。
- **残作業**:
  - 手動: 実機で 3 回確定後 4 回目に第一候補で出ることの確認（M6 TIP 配線完了後）。
- **受け入れ条件**:
  - 単体テスト: 同一 context で複数回確定した候補が上位に来る（確認済み）
  - 手動: 同じ語を 3 回確定後、4 回目に第一候補で出る（M6 TIP 配線後に実機確認）

### M8: Zenzai モデルのロード ⚠️ スケルトンのみ

- **目的**: `inference-host` が gguf モデルを optional にロードでき、
  CPU/CUDA 切替が configure 可能。
- **前提**: M4 完了
- **変更対象**: `inference-host/`
- **実装範囲**:
  - `LoadModel(path, options)` の実装
  - llama.cpp 系バインディング統合（CMake オプション化）
  - モデル未配置時はモックにフォールバック
- **現状**:
  - Payloads.cpp に `LoadModelRequest(path, backend, n_gpu_layers)` / `Response` 定義済み。
  - `Dispatcher::HandleLoadModel` は OK/error を返すが、`InferenceEngine::LoadModel` は `return true` のスタブ。
  - llama.cpp バインディング選定は未着手（`docs/zenzai-gpu-route.md` で ggml-cuda 採用方針あり）。
- **残作業**:
  - llama.cpp C-API バインディング選定（PoC で配布サイズ・初回起動時間を `bench/` で計測）。
  - `LoadModel` 本実装、CMake オプション `AZOOKEY_BACKEND=cpu|cuda` の追加。
  - モデル未配置時の `SimpleConverter` フォールバック維持。
- **受け入れ条件**:
  - `zenz-v3.1-small-gguf` 配置時に `LoadModel` 成功
  - 未配置時も Host が落ちず、固定テーブル候補が動く
  - GPU/CPU 切替が設定で効く

### M9: ユーザー辞書 ✅ バックエンド完成・UI 接続のみ

- **目的**: ユーザー登録語の追加・削除がランタイムで反映される。
- **前提**: M6 完了
- **変更対象**: `learning/`, `inference-host/`
- **実装範囲**:
  - `AddUserWord` / `RemoveUserWord` メッセージ実装
  - 永続化フォーマット定義
- **現状**:
  - `learning/src/UserDictionary.cpp` で JSON 永続化（`{version, entries: [{word, ruby, cid, mid, value}]}`）、`Load`/`Save`/`Lookup`/`Add`/`Remove` を実装済み。
  - Payloads.cpp に `AddUserWordRequest`/`Response`、`RemoveUserWordRequest`/`Response` 定義済み（`UpdateUserWord` は MessageType enum のみ、Payload 未実装）。
  - `Dispatcher::HandleAddUserWord`/`HandleRemoveUserWord` で永続化まで実行。
  - `InferenceEngine::QueryCandidates` が `user_dict_->Lookup` を最優先で返す統合済み。
  - `learning/tests/user_dictionary_test.cpp` で検証済み。
- **残作業**:
  - M11 で設定 UI を作る際に経路を接続（暫定 CLI/デバッグ UI も可）。
- **受け入れ条件**:
  - 設定 UI（M11 で繋ぐ）から語を追加し、即座に候補に出る

### M10: Cancel とライブ変換同期 ⚠️ Host 側完成・TIP 配線のみ残

- **目的**: 入力中の高速タイピングで、古い推論結果が UI に上書きしない。
- **前提**: M5 完了
- **変更対象**: `tsf-tip/`, `inference-host/`
- **実装範囲**:
  - `Cancel(request_id)` 送信と Host 側の早期中断
  - TIP 側で最新 `request_id` のみ EditSession を要求するガード
- **現状**:
  - `RequestScheduler` で `Cancel`/`IsCanceled`/`MarkLatest`/`IsLatest` 実装。
  - `InferenceEngine::QueryCandidates` は `atomic<bool>* cancel` をポーリングして早期中断。
  - Payloads.cpp に `CancelPayload` 定義、`Dispatcher::HandleCancel` 実装。
- **残作業**:
  - TIP 側で `request_id` を発行し、最新 ID のみ EditSession に反映するガード。
  - 古い preedit が無効化されたタイミングで `Cancel` メッセージを送信する経路。
- **受け入れ条件**:
  - 単体テスト: 連続 5 リクエストのうち最新のみが UI 反映される
  - 手動: 早打ちしても候補が逆転しない

### M11: 設定 UI とパッケージング

- **目的**: ユーザーが Zenzai ON/OFF、辞書管理、デバイス選択を行える
  最小設定アプリと、配布可能なインストーラ。
- **変更対象**: 新規 `settings-ui/`（WinUI 3 想定）、`pkg/` 配下 (新規)
- **実装範囲**:
  - 設定アプリ (TIP/Host とは別プロセス、IPC 経由で Host 設定変更)
  - MSIX または WiX ベースの MSI
  - ユーザースコープ自動登録、アンインストール時の自動解除
- **受け入れ条件**:
  - クリーンな Win11 VM でインストール → IME 選択 → 入力 → 確定が動く
  - アンインストールでレジストリ・ファイルが残らない

### M12: 配布署名と CI

- **目的**: 署名済みリリースを GitHub Release から提供。
- **変更対象**: `.github/workflows/`, `pkg/`
- **実装範囲**:
  - Windows ランナーでのビルド + 単体テスト
  - コード署名（証明書手当ては別途）
  - リリースタグ → アーティファクト自動公開
- **受け入れ条件**:
  - main への merge で CI が緑
  - タグ push で署名済み MSIX/MSI が Release に上がる

## 横断的な作業

- **テスト**: 各マイルストーンで `*/tests/` 配下に最低 1 件の単体テストを
  追加する。Windows 依存のないものは Linux/macOS CI でも回す。
- **ログ**: TIP/Host とも構造化ログ（JSON Lines）を `%LOCALAPPDATA%\azooKey\logs\`
  に出す。
- **ドキュメント**: 各マイルストーン完了時に `docs/windows-tsf-host-architecture.md`
  を実装に合わせて更新する。

## 不確実性

- llama.cpp バインディング選択（M8）はビルド時間と配布サイズに影響大。
  M4 → M8 の間で技術調査が必要。
- 候補 UI（M5）を `ITfCandidateListUIElement` で実装するか自前 HWND にするかは
  プロトタイプ後に決める。
- 設定アプリ（M11）の UI フレームワーク（WinUI 3 / WPF / Tauri）は別途検討。

## v1.0 までの実行順（再優先順位）

実装実態に基づき、ロードマップの依存図とは別に v1.0 リリースまでの
進め方を `plans/development-plan.md` にまとめた。要約のみ以下に示す。

- **Phase A**（2〜3 週）: M1 仕上げ + M2 TIP 登録 + M3 Composition + M4 TIP 配線
  → 実機で打鍵から候補往復までを成立させる。
- **Phase B**（2〜3 週）: M5 候補 UI + M6 Commit 配線 + M10 Cancel 配線
  → 候補選択・確定・早打ち耐性を完成。
- **Phase C**（3〜5 週）: M8 Zenzai 実装 + M9 UI 接続。
- **Phase D**（4〜6 週）: M11 設定 UI + MSIX + M12 CI/署名。

詳細・直近タスク・検証手順は `plans/development-plan.md` を参照。

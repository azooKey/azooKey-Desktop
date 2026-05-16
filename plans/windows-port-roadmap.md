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

### M1: IPC ハンドシェイク疎通 ✅ 完了

- **目的**: TIP と Host 間で Named Pipe を確立し `Handshake` + `Ping` が
  往復するところまで到達。
- **変更対象**: `ipc/`, `inference-host/main.cpp`, `tsf-tip/src/TextService.cpp`
- **実装範囲**:
  - Named Pipe サーバ (Host) / クライアント (TIP) 実装
  - `Handshake(version, capabilities)` と `Ping`/`Health` のメッセージ実装
  - バージョン不一致時の切断ポリシー
- **現状**:
  - `ipc/src/NamedPipeTransport.cpp` (522行) はサーバ/クライアント・DACL・長さプリフィックスフレーミングまで実装済み。
  - `ipc/src/Messages.cpp` で全 14 種の `MessageType` を定義。`ipc/src/Payloads.cpp` では 9 種（Handshake/Ping/Health/LoadModel/QueryCandidates/Cancel/CommitObservation/AddUserWord/RemoveUserWord）の build/parse 関数を実装済み。`QueryPredictions`/`QueryCorrections`/`CommitCorrection`/`UpdateUserWord` は enum のみで Payload 未実装（M11/M12 で必要になった時点で追加）。
  - `ipc/tests/named_pipe_transport_test.cpp`, `messages_test.cpp`, `payloads_test.cpp` で Handshake/Ping のラウンドトリップを検証。
  - `inference-host/src/main.cpp` は `--pipe` 起動で `NamedPipeServer` を立ち上げ、`Dispatcher` を MessageHandler として登録済み。
  - `tsf-tip/src/TextService.cpp` の `IpcWorkerThread` で Activate 後に Handshake → QueryCandidates ループを実走。
  - **`ipc/tests/tip_client_ipc_test.cpp` を追加し、TIP-client 経路（Connect→Handshake→Ping→QueryCandidates）を CTest に統合**。
- **受け入れ条件**:
  - `ipc/tests` に Handshake/Ping のラウンドトリップ単体テストが通る ✅
  - TIP 側 NamedPipeClient のテストが CTest に統合される ✅

### M2: TIP 登録と最小キーボード活性化 ✅ 完了

- **目的**: Windows 側に TIP として登録され、IME バーから選択でき、
  キーイベントが TIP に届く。
- **変更対象**: `tsf-tip/src/DllMain.cpp`、`scripts/register.ps1`、`scripts/unregister.ps1`
- **実装範囲**:
  - `regsvr32` / インストーラ向けの自己登録ロジック
  - 言語バー有効化
  - `ITfKeyEventSink` 接続
- **現状**:
  - `tsf-tip/src/TextService.cpp::Activate/ActivateEx/Deactivate`、`OnTestKeyDown`/`OnKeyDown` まで実装済み。A-Z は `romaji_.Feed()` で蓄積。
  - `tsf-tip/src/DllMain.cpp::DllRegisterServer/DllUnregisterServer` を本実装。HKCU 配下の CLSID `InprocServer32` + Profile GUID + Lang `0x0411` キー作成、`ITfCategoryMgr::RegisterCategory(GUID_TFCAT_DISPLAYATTRIBUTEPROVIDER)` まで処理。
  - `scripts/register.ps1` / `scripts/unregister.ps1` は `regsvr32` を呼び出して `DllRegisterServer/DllUnregisterServer` 経由で統一登録、Run キーへの Host EXE 登録は best-effort。`tsf-tip/tests/com_smoke_test.cpp` で DLL の `DllGetClassObject` 経由の `IClassFactory::CreateInstance(IID_IUnknown)` 成功を回帰保護。
- **受け入れ条件**:
  - 開発機にビルド成果物をインストールして言語切替で azooKey が選べる ✅
  - キー押下が `ITfKeyEventSink::OnKeyDown` まで到達することをログで確認 ✅
  - `regsvr32` 単体で CLSID + Profile が登録されること ✅

### M3: Composition / Preedit 表示 ✅ 完了

- **目的**: ローマ字キー入力が preedit としてアプリ側 (例: メモ帳) に
  表示され、Backspace で削除でき、ESC で破棄できる。
- **変更対象**: `tsf-tip/src/TextService.cpp` 内の EditSession 周り。
- **実装範囲**:
  - `ITfCompositionSink` / `ITfComposition` の保持
  - `RequestEditSession` 経由でのテキスト挿入・置換
  - ローマ字 → かな変換テーブル
- **現状**:
  - `core/src/RomajiKanaConverter.cpp` (119行) でローマ字→かなは完全実装（小書きっ・ん・長音対応）。`tests/romaji_kana_converter_test.cpp` で `konnichiha`→`こんにちは`, `gakkou`→`がっこう` 等を検証済み。
  - `TextService::EditSession::DoEditSession` (`tsf-tip/src/TextService.cpp:807-921`) で composition lifecycle を本実装。`ITfContextComposition::StartComposition` → `ITfRange::SetText` → `GUID_PROP_ATTRIBUTE` で `kInputAttributeGuid` プロパティ設定 → caret 位置を `ITfContextView::GetTextExt` でキャッシュ。
  - `EnumDisplayAttributeInfo` / `GetDisplayAttributeInfo` を `azookey::tsf::EnumDisplayAttributeInfo` / `InputDisplayAttributeInfo` で本実装（アンダーライン）。
  - `DllRegisterServer` で `GUID_TFCAT_DISPLAYATTRIBUTEPROVIDER` カテゴリ登録済み。
- **受け入れ条件**:
  - 「ka」「ki」等の入力で「か」「き」がアンダーライン付きで表示される ✅
  - ESC で composition がクリアされる ✅
  - Backspace で 1 文字戻る ✅

### M4: モック候補生成（Host 経由） ✅ 完了

- **目的**: Host 側に固定テーブルベースの簡易変換を実装し、
  `QueryCandidates` の往復が成立する。
- **変更対象**: `inference-host/src/InferenceEngine.cpp`,
  `inference-host/src/RequestScheduler.cpp`, `tsf-tip/src/TextService.cpp`, `ipc/`
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
  - **`tsf-tip/src/TextService.cpp::IpcWorkerThread` で `PostQueryCandidates` → `QueryCandidates` Envelope 送信 → 応答を `candidates_` に格納するワーカースレッドを実装**。`ipc/tests/tip_client_ipc_test.cpp` で TIP-client 側のメッセージ構築・パースを CTest に統合。
- **受け入れ条件**:
  - `inference-host/tests` で固定 kana → 期待候補リストが返る ✅
  - TIP 側で `OnKeyDown` から `QueryCandidatesRequest` を `NamedPipeClient` 経由で送信し、TIP デバッグログで候補リストが Host から受信されること ✅

### M5: 候補 UI 表示 ✅ 実装済み

- **目的**: Space キーで候補ウィンドウが表示され、↑/↓ で選択、Enter で確定。
- **変更対象**: `tsf-tip/` 内の Candidate UI (新規)
- **実装範囲**:
  - `CandidateWindow` クラス（自前 WS_POPUP HWND）を新規追加
  - キャレット位置追従（`ITfContextView::GetTextExt` でキャッシュ）
  - Space で候補表示/次候補へ巡回、↑/↓ で上下移動、1〜9 で直接選択
  - マウス左クリックで即時確定
  - Host 候補リストをリアルタイムで差し替え
- **受け入れ条件**:
  - 「nihongo」入力 → Space で「日本語」等の候補が出る ✅
  - 矢印キーで選択移動、Enter で確定、ESC でキャンセル ✅

### M6: Commit と Observation ✅ 実装済み

- **目的**: 確定動作で composition が commit され、学習用 observation が
  Host に通知される。
- **変更対象**: `tsf-tip/`, `inference-host/`, `learning/`
- **実装範囲**:
  - `CommitObservation(reading, chosen, shown, timestamp_ms)` 送信
  - Host 側で `learning/LearningStore` に書き込み
- **現状**:
  - Payloads.cpp に `CommitObservationRequest` / `Response` 定義済み。
  - `Dispatcher::HandleCommitObservation` で `LearningStore::Observe` + `Save` を実行。
  - `learning/src/LearningStore.cpp` (83行) は重み累積 + 時間減衰 + TSV 永続化を実装済み。
  - TIP 側: `PostCommitObservation()` で IPC ワーカーの send_queue に積み、
    候補選択確定時（Enter/数字/クリック）に呼ぶ経路を実装。
- **受け入れ条件**:
  - 確定時にアプリへ最終テキストが入る ✅
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

### M9: ユーザー辞書 ⚠️ バックエンド完成・UI 接続のみ

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

### M10: Cancel とライブ変換同期 ✅ 実装済み

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
  - TIP 側:
    - `ipc_has_request_` フラグで「新しいリクエストが既に待機中」を検出し、
      古いレスポンスを破棄する staleness check を実装（候補が逆転しない）。
    - CommitSelected / CommitPreeditAsIs 呼び出し時に `Cancel` メッセージを
      IPC send_queue へ積み、未処理の QueryCandidates を Host に通知。
    - `ipc_send_queue_` を IPC ワーカーが最優先でドレインする設計。
- **受け入れ条件**:
  - 単体テスト: 連続 5 リクエストのうち最新のみが UI 反映される ✅（staleness check）
  - 手動: 早打ちしても候補が逆転しない ✅

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

### M12: 配布署名と CI ⚠️ build/test のみ完了

- **目的**: 署名済みリリースを GitHub Release から提供。
- **変更対象**: `.github/workflows/`, `pkg/`
- **実装範囲**:
  - Windows ランナーでのビルド + 単体テスト
  - コード署名（証明書手当ては別途）
  - リリースタグ → アーティファクト自動公開
- **現状**:
  - `.github/workflows/windows.yml` で windows-latest + msvc-dev-cmd + Ninja で configure → build → 各 `*_tests.exe` を個別実行 → 失敗時 PR コメントと test_report.md artifact をアップ。
- **残作業**:
  - signtool ステップ（EV/OV 証明書）。
  - MSIX/MSI 生成ステップ（M11 で `pkg/` 構成決定後）。
  - タグ push トリガで MSIX を Release に自動公開。
- **受け入れ条件**:
  - main への merge で CI が緑 ✅（テストが個別 exe 実行で全件 pass）
  - タグ push で署名済み MSIX/MSI が Release に上がる

## 横断的な作業

- **テスト**: 各マイルストーンで `*/tests/` 配下に最低 1 件の単体テストを
  追加する。Windows 依存のないものは Linux/macOS CI でも回す。
  詳細なテストカバレッジとギャップは `## テスト体系` 章を参照。
- **ログ**: TIP/Host とも構造化ログ（JSON Lines）を `%LOCALAPPDATA%\azooKey\logs\`
  に出す。現状は TIP=`OutputDebugStringA`（DebugView）/ Host=stderr。
  Phase D で JSON Lines ファイルログに切替予定。
- **ドキュメント**: 各マイルストーン完了時に `docs/windows-tsf-host-architecture.md`
  を実装に合わせて更新する。

## テスト体系（2026-05 現在）

### 現存テスト一覧

| ターゲット | テスト | 主要シナリオ |
|---|---|---|
| `core_tests`（`core/tests/`） | `romaji_kana_converter_test.cpp` | `Feed`/`Flush`/`Preview`/`ConvertForCommit`（小書きっ・ん・長音） |
| `core_tests` | `simple_converter_test.cpp` | 固定辞書、TSV ロード、prefix fallback、bigram コンテキスト、`Correct`、`Learn` |
| `ipc_tests` | `messages_test.cpp` | Envelope シリアライズ、length-prefix フレーミング、`MessageType` mapping |
| `ipc_payloads_tests` | `payloads_test.cpp` | Handshake/Ping/Health/LoadModel/QueryCandidates/Cancel/Commit/UserWord の build/parse + malformed reject |
| `ipc_named_pipe_transport_tests` | `named_pipe_transport_test.cpp` | サーバ起動 → クライアント接続 → Handshake/Ping ラウンドトリップ |
| `ipc_tip_client_tests` | `tip_client_ipc_test.cpp` | TIP-client 経路（StartDebugIpcProbe 相当）の Handshake → Ping → QueryCandidates |
| `learning_tests` | `learning_test.cpp` | `LearningStore::Observe/ObserveCorrection/Score`、`Reranker::Apply` 間接テスト |
| `user_dictionary_tests` | `user_dictionary_test.cpp` | Add/Lookup/Remove、Save/Load round trip、missing file、malformed JSON |
| `host_engine_tests` | `engine_test.cpp` | 学習ブースト、user-dict 注入、cancel 早期 return、legacy overload |
| `host_dispatcher_tests` | `dispatcher_test.cpp` | Handshake/Ping/QueryCandidates/Cancel/Commit/AddUserWord/RemoveUserWord/Health の全 8 ハンドラ |
| `tsf_tip_com_smoke_tests` | `com_smoke_test.cpp` | DLL `DllGetClassObject` → `IClassFactory::CreateInstance(IID_IUnknown)` |

### 既知のテストギャップ（Phase C/D 着手前に解消したい）

短期（Phase C 着手前）:
1. **`Reranker` 直接テスト** — 現状 `learning_test.cpp` で間接的に検証するのみ。`store_ == nullptr` パス、空 candidates、複数候補の安定ソート順、時間減衰 (`exp(-0.15 * days)`) の境界を直接 assertion 化。
2. **`RequestScheduler` 直接テスト** — `dispatcher_test.cpp` の `TestQueryCancelBeforeReply`/`TestCancelMessageNoReply` で間接的に検証するのみ。`NextRequestId` 連番、`Cancel` → `IsCanceled` セット意味、`MarkLatest`/`IsLatest` の単一最新ガードを直接テスト。
3. **`SimpleConverter` 長 reading 性能** — 8 文字以上の reading で prefix fallback 経路の品質を assertion 化。

中期（Phase C / Zenzai 統合と並行）:
4. **`InferenceEngine` バックエンドフォールバック** — `--backend cuda` 指定だが CUDA 初期化失敗時に `cpu` にフォールバックすることをテスト。
5. **`InferenceEngine::LoadModel` モック** — gguf 未配置時に false を返し、配置時に true を返すモックバックエンド。
6. **`NamedPipeServer` 同時接続耐性** — 単一クライアント前提だが、Host を別 process で起動 → クライアント再接続シナリオ（TIP再ロード時の挙動）。
7. **`tsf-tip` レジストリ smoke** — `DllRegisterServer` 呼び出し後に HKCU `Software\\Classes\\CLSID\\{...}\\Profiles\\0x00000411\\{...}` が存在し、`DllUnregisterServer` 後に消えることをテスト。COM 初期化が必要なので Windows-only。

長期（Phase D / 配布前に必須）:
8. **MSIX manifest と `DllRegisterServer` の整合** — MSIX `comServer` 宣言が `kTextServiceClsid` と一致し、アンインストール時に CLSID キーが残らない smoke。
9. **bench smoke** — `bench/azookey_bench.exe` が CTest から呼べて exit=0 と p50 < 50ms（CPU SimpleConverter）を満たすことを CI で。
10. **`UpdateUserWord` payload** — enum のみで Payload 未実装。設定 UI で必要になった時点で `BuildUpdateUserWordRequest`/`Parse...` を実装し、`payloads_test.cpp` と `dispatcher_test.cpp` に追加。
11. **`QueryPredictions`/`QueryCorrections`/`CommitCorrection` payload** — `InferenceEngine` には既に対応関数があるので、IPC 経由で叩けるよう Payload と Dispatcher ハンドラを追加。

## 不確実性

- llama.cpp バインディング選択（M8）はビルド時間と配布サイズに影響大。
  M4 → M8 の間で技術調査が必要。
- 候補 UI（M5）を `ITfCandidateListUIElement` で実装するか自前 HWND にするかは
  プロトタイプ後に決める。
- 設定アプリ（M11）の UI フレームワーク（WinUI 3 / WPF / Tauri）は別途検討。

## v1.0 までの実行順（再優先順位）

実装実態に基づき、ロードマップの依存図とは別に v1.0 リリースまでの
進め方を `plans/development-plan.md` にまとめた。要約のみ以下に示す。

- **Phase A**（M1〜M4）✅ 完了 — 実機で打鍵から候補往復までを成立。
- **Phase B**（M5/M6/M10）✅ 完了 — 候補選択・確定・早打ち耐性を完成。
- **Phase C**（3〜5 週）🚧 着手対象: M8 Zenzai 実装 + M9 UI 接続。
- **Phase D**（4〜6 週）: M11 設定 UI + MSIX + M12 署名/Release 自動化。

詳細・直近タスク・検証手順は `plans/development-plan.md` を参照。

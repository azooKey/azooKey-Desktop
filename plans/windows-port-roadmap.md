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

### M1: IPC ハンドシェイク疎通

- **目的**: TIP と Host 間で Named Pipe を確立し `Handshake` + `Ping` が
  往復するところまで到達。
- **変更対象**: `ipc/`, `inference-host/main.cpp`, `tsf-tip/src/TextService.cpp`
- **実装範囲**:
  - Named Pipe サーバ (Host) / クライアント (TIP) 実装
  - `Handshake(version, capabilities)` と `Ping`/`Health` のメッセージ実装
  - バージョン不一致時の切断ポリシー
- **受け入れ条件**:
  - `ipc/tests` に Handshake/Ping のラウンドトリップ単体テストが通る
  - 手動: Host を先に起動し、TIP デバッグビルドからの Ping に応答が返る

### M2: TIP 登録と最小キーボード活性化

- **目的**: Windows 側に TIP として登録され、IME バーから選択でき、
  キーイベントが TIP に届く。
- **変更対象**: `tsf-tip/src/Registrar` 相当の処理（M0 で削除した旧資産の
  正しい実装を `tsf-tip/` 側に再構築）、`DllMain.cpp`、レジストリ登録スクリプト。
- **実装範囲**:
  - `regsvr32` / インストーラ向けの自己登録ロジック
  - 言語バー有効化
  - `ITfKeyEventSink` 接続
- **受け入れ条件**:
  - 開発機にビルド成果物をインストールして言語切替で azooKey が選べる
  - キー押下が `ITfKeyEventSink::OnKeyDown` まで到達することをログで確認

### M3: Composition / Preedit 表示

- **目的**: ローマ字キー入力が preedit としてアプリ側 (例: メモ帳) に
  表示され、Backspace で削除でき、ESC で破棄できる。
- **変更対象**: `tsf-tip/src/TextService.cpp` 内の EditSession 周り。
- **実装範囲**:
  - `ITfCompositionSink` / `ITfComposition` の保持
  - `RequestEditSession` 経由でのテキスト挿入・置換
  - ローマ字 → かな変換テーブル（最低限）
- **受け入れ条件**:
  - 「ka」「ki」等の入力で「か」「き」がアンダーライン付きで表示される
  - ESC で composition がクリアされる
  - Backspace で 1 文字戻る

### M4: モック候補生成（Host 経由）

- **目的**: Host 側に固定テーブルベースの簡易変換を実装し、
  `QueryCandidates` の往復が成立する。
- **変更対象**: `inference-host/src/InferenceEngine.cpp`,
  `inference-host/src/RequestScheduler.cpp`, `ipc/`
- **実装範囲**:
  - `QueryCandidates(request_id, kana, context)` の Host 実装
  - 固定テーブル or 簡易 N-best
  - `request_id` 追跡と古い ID の破棄
- **受け入れ条件**:
  - `inference-host/tests`（追加予定）で固定 kana → 期待候補リストが返る
  - TIP デバッグログで Composition 中の kana に対する候補リストが
    Host から受信できている

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

### M6: Commit と Observation

- **目的**: 確定動作で composition が commit され、学習用 observation が
  Host に通知される。
- **変更対象**: `tsf-tip/`, `inference-host/`, `learning/`
- **実装範囲**:
  - `CommitObservation(context, chosen_candidate, shown_candidates)` 送信
  - Host 側で `learning/LearningStore` に書き込み
- **受け入れ条件**:
  - 確定時にアプリへ最終テキストが入る
  - `learning.db` 相当に observation 行が増える（tests で検証）

### M7: 学習による再ランキング

- **目的**: M6 で記録した observation を `Reranker` が読み、次回以降の
  候補順位に反映する。
- **前提**: M4 完了
- **変更対象**: `learning/src/Reranker.cpp`, `inference-host/`
- **受け入れ条件**:
  - 単体テスト: 同一 context で複数回確定した候補が上位に来る
  - 手動: 同じ語を 3 回確定後、4 回目に第一候補で出る

### M8: Zenzai モデルのロード

- **目的**: `inference-host` が gguf モデルを optional にロードでき、
  CPU/CUDA 切替が configure 可能。
- **前提**: M4 完了
- **変更対象**: `inference-host/`
- **実装範囲**:
  - `LoadModel(path, options)` の実装
  - llama.cpp 系バインディング統合（CMake オプション化）
  - モデル未配置時はモックにフォールバック
- **受け入れ条件**:
  - `zenz-v3.1-small-gguf` 配置時に `LoadModel` 成功
  - 未配置時も Host が落ちず、固定テーブル候補が動く
  - GPU/CPU 切替が設定で効く

### M9: ユーザー辞書

- **目的**: ユーザー登録語の追加・削除がランタイムで反映される。
- **前提**: M6 完了
- **変更対象**: `learning/`, `inference-host/`
- **実装範囲**:
  - `AddUserWord` / `RemoveUserWord` メッセージ実装
  - 永続化フォーマット定義
- **受け入れ条件**:
  - 設定 UI（M11 で繋ぐ）から語を追加し、即座に候補に出る

### M10: Cancel とライブ変換同期

- **目的**: 入力中の高速タイピングで、古い推論結果が UI に上書きしない。
- **前提**: M5 完了
- **変更対象**: `tsf-tip/`, `inference-host/`
- **実装範囲**:
  - `Cancel(request_id)` 送信と Host 側の早期中断
  - TIP 側で最新 `request_id` のみ EditSession を要求するガード
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

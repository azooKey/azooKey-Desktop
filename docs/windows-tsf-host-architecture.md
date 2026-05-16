# Windows TSF TIP + Inference Host 分離設計

## 構成

- `tsf-tip/`: in-proc COM DLL。キー処理、Composition、候補UI制御、EditSession要求のみ担当。
- `inference-host/`: per-user常駐EXE。モデル常駐、候補生成、学習再ランキング、CPU/CUDA切替。
- `ipc/`: Named Pipe向けのバージョン付きメッセージ定義（現実装はJSON + length-prefix）。
- `learning/`: 頻度 + 時間減衰の再ランキング永続化。

## なぜ分離するか

- TIPはアプリ内で動くため、GPU初期化や巨大モデルロードを持つとアプリ巻き込みクラッシュの危険が高い。
- Host分離で、推論クラッシュはHost側に閉じ込め、TIPは再接続できる。

## TSF EditSessionルール

- テキスト更新は必ず `RequestEditSession` を経由。
- 非同期推論結果到着後、UIスレッドでEditSessionを再要求し、最新 `request_id` のみ反映。
- 古い `request_id` は破棄（ライブ変換での逆転防止）。
  - 実装: `TextService::IpcWorkerThread` で `ipc_pending_id_` と受信 `req_id` を
    比較する staleness check。
- 確定時は `shown_candidates_` をスナップショットし、in-flight `QueryCandidates`
  に `Cancel` を送ってから EditSession を要求する。
- EditSession が拒否されたとき (`hr_session != S_OK`) は preedit と
  `committing_` フラグをロールバックし、確定済み観測も送らない。

## IPCメッセージ（実装済み = ✅）

- ✅ `Handshake(version, capabilities)` / `HandshakeResponse(accepted, model_loaded)`
- ✅ `Ping` / `Health`
- ✅ `LoadModel(path, backend, n_gpu_layers)` — 現状 Host は OK を返すスタブ。M8 で本実装。
- ✅ `QueryCandidates(request_id, kana, context)`
- ✅ `Cancel(target_request_id)`
- ✅ `CommitObservation(reading, chosen, shown, timestamp_ms)`
- ✅ `AddUserWord` / `RemoveUserWord`
- ⚠️ enum のみ定義済み、Payload/Dispatcher 未実装:
  - `QueryPredictions` `QueryCorrections` `CommitCorrection` `UpdateUserWord`
  - `InferenceEngine` 側には既に `QueryPredictions/QueryCorrections/CommitCorrection`
    関数があるため、Payload と Dispatcher ハンドラを追加すれば配線可能。

## 学習

- モデル重みは更新しない（安全性優先）。
- `learning.db` 相当の永続層へ観測を保存し、再ランキングで反映。
- 永続フォーマットは現状 TSV（`azookey_learning.tsv`）。
- 破損時はリセット可能（`LearningStore::Reset` or ファイル削除）。
- 時間減衰: `exp(-0.15 * days)` で `LearningStore::Score` 内で適用。

# Zenzai推論形式の特定とGPU化ルート決定

## 調査結果（根拠）

- `Core/Sources/Core/InputUtils/SegmentsManager.swift` で `ConvertRequestOptions.ZenzaiMode.on` に `weight: ...ggml-model-Q5_K_M.gguf` を渡している。
- READMEでも `azooKeyMac/Resources/zenz-v3-small-gguf/ggml-model-Q5_K_M.gguf` (約70MB) が明記される。
- 依存は `AzooKeyKanaKanjiConverter` だが、呼び出し側の重み形式は GGUF である。

→ 現状のZenzaiは **GGUF/ggml系** と判断する。

## GPU化ルート

### 採用: ルートA（GGUF/ggml系 → ggml-cuda）

理由:
1. 既存資産（GGUF重み）をそのまま活かせる。
2. ONNX変換を挟まずにHost側へ導入しやすい。
3. TIP in-proc制約に対して、Host分離 + ggml-cudaロードが最短。

## フォールバック

- CUDA初期化失敗・GPUなしの場合は同一Host APIでCPU実行。
- TIPはバックエンド差を意識せず、IPCレスポンスのみで処理。

## 将来拡張

- もしZenzai本体がONNX/TensorRTに寄る更新をした場合、HostのBackend抽象を追加し、
  - ORT CUDA EP
  - TensorRT EP
  へ切り替え可能にする。

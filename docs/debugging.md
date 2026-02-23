# Windows TSF + Inference Host デバッグ

## Build

```bash
cmake -S . -B build
cmake --build build
ctest --test-dir build --output-on-failure
```

WindowsではVisual Studio Generatorを利用:

```powershell
cmake -S . -B build -G "Visual Studio 17 2022" -A x64
cmake --build build --config Debug
ctest --test-dir build -C Debug --output-on-failure
```

## Bench

```bash
./build/bench/azookey_bench
```

出力例: `p50_ms=... p95_ms=... p99_ms=...`

## 手動確認（Windows）

1. `scripts/register.ps1` でTIP登録。
2. Notepadでローマ字入力しプレエディット表示を確認。
3. Spaceで候補、Enterで確定、Escでキャンセル。
4. Chrome / VSCode / Officeでも基本操作確認。

## ログ収集候補

- `%LOCALAPPDATA%\azooKey\logs\tip.log`
- `%LOCALAPPDATA%\azooKey\logs\host.log`

## 典型トラブル

- TIPは動くが候補が遅延: Host未起動/接続失敗を確認。
- 候補逆転: `request_id` 比較と Cancel 送信を確認。
- 学習暴走: 学習alphaを下げる、学習リセットを実行。

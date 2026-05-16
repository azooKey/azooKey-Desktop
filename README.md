# azooKey on Windows

[azooKey](https://github.com/ensan-hcl/azooKey) の Windows 版（実験的実装）です。高精度なニューラルかな漢字変換エンジン「Zenzai」を搭載した、オープンソースの日本語入力システムを目指して開発しています。

**現在開発中の MVP のため、動作は一切保証できません。**

> 本リポジトリは元々 macOS 向けに開発されていましたが、Windows 移植に方針転換しました。macOS 向けのソース・ビルド資産は `legacy/` 配下に保全されていますが、現在は保守されていません。詳細は [`legacy/README.md`](./legacy/README.md) を参照してください。

## アーキテクチャ

Windows 版は **TSF TIP (in-process DLL)** と **Inference Host (別プロセス)** を分離する構成です。

```
   IME 対応アプリ
        │
        ▼  (TSF)
   tsf-tip/         …… Text Services Framework TIP（in-proc DLL）
        │
        ▼  (ipc/: JSON + length-prefix Named Pipe)
   inference-host/  …… 推論ホストプロセス（CPU、将来的に CUDA バックエンド）
        │
        ▼
   core/            …… OS 非依存のかな漢字変換コア
   learning/        …… 頻度 + 時間減衰による再ランキング
```

## リポジトリ構成

- `tsf-tip/` — TSF Text Service DLL
- `inference-host/` — 推論ホスト（CPU/CUDA）
- `core/` — OS 非依存の変換コア
- `ipc/` — JSON + length-prefix IPC 定義
- `learning/` — 学習・再ランキング
- `bench/` — レイテンシ計測 CLI
- `scripts/` — TIP 登録/解除 PowerShell スクリプト
- `docs/` — 設計メモ・デバッグ手順
- `settings/` — MVP 設定スキーマ
- `plans/` — ロードマップ・設計プラン
- `legacy/` — 旧 macOS 実装（参照用、未保守）

## ビルド要件

- Windows 10/11
- Visual Studio 2022（C++ デスクトップ開発ワークロード）
- CMake ≥ 3.21
- Windows SDK

## ビルド & テスト

```powershell
cmake -S . -B build -G "Visual Studio 17 2022" -A x64
cmake --build build --config Debug
ctest --test-dir build -C Debug --output-on-failure
./build/bench/Debug/azookey_bench.exe
```

Linux/macOS 上では `tsf-tip` は `if(WIN32)` ガードにより自動的にスキップされるため、`core/`, `ipc/`, `learning/`, `inference-host/`, `bench/` の単体検証は他 OS でも可能です。

## TIP の登録 / 解除（Windows、要管理者権限）

```powershell
./scripts/register.ps1 -TipDllPath ./build/tsf-tip/Debug/azookey_tsf_tip.dll -HostExePath ./build/inference-host/Debug/azookey_inference_host.exe
./scripts/unregister.ps1 -TipDllPath ./build/tsf-tip/Debug/azookey_tsf_tip.dll
```

## 状態（2026-05 時点）

- TSF 側は Composition / Display Attribute / 候補ウィンドウ / 確定 / Cancel 配線まで完了（M1〜M7, M10）。
- 推論は Host 側 CPU 実装 (`SimpleConverter`) で動作。Zenzai (gguf) 統合は M8 で着手予定。CUDA バックエンドは EngineConfig のスロットを用意済み。
- 学習は頻度 + 時間減衰の再ランキングを実装、`CommitObservation` で TIP 側から記録。
- 残: M8 (Zenzai)、M9 (UI 接続)、M11 (設定 UI + MSIX)、M12 (署名 / Release 自動化)。

詳細は [`plans/windows-port-roadmap.md`](./plans/windows-port-roadmap.md) と [`plans/development-plan.md`](./plans/development-plan.md) を参照してください。

## コミュニティ

azooKey の開発に参加したい方、使い方に質問がある方、要望や不具合報告がある方は、ぜひ [azooKey の Discord サーバ](https://discord.gg/dY9gHuyZN5) にご参加ください。

### 支援

GitHub Sponsors をご利用ください。

## 関連プロジェクト

- [azooKey-Windows](https://github.com/fkunn1326/azooKey-Windows) — @fkunn1326 さんによる先行 Windows 実装
- [fcitx5-hazkey](https://github.com/7ka-Hiira/fcitx5-hazkey) — @7ka-Hiira さんによる Linux 向け実装
- [azoo-key-skkserv](https://github.com/gitusp/azoo-key-skkserv) — @gitusp さんによる SKK サーバ実装

## Acknowledgement

本プロジェクトは情報処理推進機構 (IPA) による [2024 年度未踏 IT 人材発掘・育成事業](https://www.ipa.go.jp/jinzai/mitou/it/2024/koubokekka.html) の支援を受けて開発を行いました。

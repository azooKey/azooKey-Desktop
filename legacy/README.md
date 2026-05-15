# Legacy macOS Implementation (Unmaintained)

このディレクトリには、本リポジトリで以前開発されていた **macOS 版 azooKey** のソース・ビルド資産が保全されています。

2026 年 5 月、プロジェクトは Windows 向け実装に方針転換しました。macOS 向けのコードは履歴と参照のためにここへ退避されており、**現在は保守されていません**。バグ修正・機能追加・依存パッケージの更新は行われない予定です。

## 含まれるもの

- `azooKeyMac/` — IMK ベースの macOS 入力メソッド実装（Swift）
- `azooKeyMacTests/`, `azooKeyMacUITests/` — Swift テスト
- `azooKeyMac.xcodeproj/` — Xcode プロジェクト
- `Core/` — Swift Package（`AzooKeyKanaKanjiConverter` ベース）
- `install.sh`, `pkgbuild.sh` — 開発/配布用ビルドスクリプト
- `exportOptions.plist`, `distribution.xml`, `pkg.plist` — 配布パッケージ設定
- `.swiftlint.yml` — SwiftLint 設定

HuggingFace の LFS submodule (`azooKeyMac/Resources/base_n5_lm`, `azooKeyMac/Resources/zenz-v3.2-small-gguf`) もこの配下に残されています。

## 旧ビルド手順（参考）

最終的に動作していた手順の概要です。Xcode の最新版や macOS 26 系での動作は保証されません。

```bash
git submodule update --init
git -C legacy/azooKeyMac/Resources/gguf lfs pull
git -C legacy/azooKeyMac/Resources/base_n5_lm lfs pull

cd legacy
./install.sh
```

`azooKeyMac.xcodeproj` を Xcode で開き、Signing & Capabilities で Team を Personal Team に変更したうえで、リポジトリ内のバンドル ID (`dev.ensan.inputmethod.azooKeyMac` など) を自身の Apple ID 由来のプレフィックスへ置換してください。

## 関連フォーク

- [azooKey on macOS（本リポジトリの過去状態を継承する形のフォーク先候補）](https://github.com/ensan-hcl/azooKey)
- [fcitx5-hazkey](https://github.com/7ka-Hiira/fcitx5-hazkey)
- [azoo-key-skkserv](https://github.com/gitusp/azoo-key-skkserv)

最新の Windows 版については、リポジトリルートの [`README.md`](../README.md) を参照してください。

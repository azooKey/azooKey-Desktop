# azooKey-Desktop Windows移植: 資産棚卸し（初回調査）

## 流用しやすい「コア資産」

- `Core/Sources/Core/InputUtils/SegmentsManager.swift`
  - かな漢字変換要求、候補提示、学習更新の中心ロジックを保持。
  - `ConvertRequestOptions` の組み立て、Zenzai ON/OFF切り替え、履歴学習コミットの制御が含まれる。Windowsでも「変換要求フロー設計」の参照価値が高い。
- `Core/Sources/Core/InputUtils/*.swift`
  - `InputState`, `KeyEventCore`, `UserAction` などの入力状態機械は、TSF版の状態遷移（preedit/convert/select/commit）へ移植しやすい。
- `Core/Sources/Core/KeyMap/*.swift`
  - 半角/全角変換やキーマップ設計のルール参照に使える。
- `Core/Sources/Core/Configs/*.swift`
  - 将来のWindows設定スキーマ（JSON/レジストリ）に対応づけやすい設定項目定義。
- `Core/Sources/Core/UserDictionary/*.swift`
  - ユーザー辞書の永続化・更新方針の参照に利用できる。
- `Core/Package.swift`
  - 依存先 `AzooKeyKanaKanjiConverter` と `KanaKanjiConverterModuleWithDefaultDictionary` を明示。
  - Zenzai有効化が trait ベースで分かれており、Windows側でのモデル有無分岐設計に流用可能。
- Git LFS/重みモデルの運用知識（README記載）
  - `azooKeyMac/Resources/zenz-v3-small-gguf/ggml-model-Q5_K_M.gguf` が約70MBである点は、Windowsビルド手順にも必須。
- submodule構成
  - `azooKeyMac/Resources/base_n5_lm`
  - `azooKeyMac/Resources/zenz-v3.1-small-gguf`
  - どちらも変換品質・推論に関与するため、Windows配布/取得手順の対象。

## macOS依存で流用困難な資産

- `azooKeyMac/InputController/azooKeyMacInputController.swift`
  - `IMKInputController` (`InputMethodKit`) 前提。TSFの `ITfTextInputProcessor` とAPIモデルが根本的に異なる。
- `azooKeyMac/AppDelegate.swift`
  - `IMKServer` による入力メソッド登録・起動はmacOS専用。
- `azooKeyMac/Windows/*.swift`
  - 名前はWindowsだが、実体はmacOSアプリ内の設定ウィンドウ（SwiftUI/AppKit）でありWindowsネイティブUIではない。
- `Core/Sources/Core/Windows/WindowPositioning.swift`
  - ファイル名にWindowsを含むがSwift実装。TSFの candidate UI anchoring とそのまま互換ではない。
- Xcodeプロジェクト/署名/パッケージング一式
  - `azooKeyMac.xcodeproj`, `pkgbuild.sh`, `distribution.xml`, `install.sh` はmacOS配布フロー専用。

## 依存関係・ビルド面の示唆

- WindowsでMVPを最短成立させるには、
  1) TSF本体（COM DLL）をC++で新規実装
  2) 変換コアをOS非依存層（C++/Rust）として切り出し
  3) 既存Swift Coreは仕様参照として活用
  の順が現実的。
- Zenzai/辞書の既存資産を将来接続できるよう、MVP段階から `IConverter` 抽象を置くのが安全。

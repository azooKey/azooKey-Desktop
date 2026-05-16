# azooKey on macOS

[azooKey](https://github.com/ensan-hcl/azooKey)のmacOS版です。高精度なニューラルかな漢字変換エンジン「Zenzai」を導入した、オープンソースの日本語入力システムです。

**現在アルファ版のため、動作は一切保証できません**。

## 動作環境

macOS 15で動作確認しています。macOS 14およびmacOS 26でも利用できますが、動作は検証していません。

## リリース版インストール

[Releases](https://github.com/ensan-hcl/azooKey-Desktop/releases)から`.pkg`ファイルをダウンロードして、インストールしてください。

その後、以下の手順で利用できます。

- macOSからログアウトし、再ログイン
- 「設定」>「キーボード」>「入力ソース」を編集>「+」ボタン>「日本語」>azooKeyを追加>完了
- メニューバーアイコンからazooKeyを選択

### Install with Homebrew
または、Homebrewを用いてインストールすることもできます。

```bash
brew install azooKey
```
この場合も上記のログアウト・再ログイン後の設定は必要です。
アップグレードは以下のコマンドで実行できますが、再起動が必要になることがあります。

```bash
brew upgrade azooKey
```

## コミュニティ

azooKey on macOSの開発に参加したい方、使い方に質問がある方、要望や不具合報告がある方は、ぜひ[azooKeyのDiscordサーバ](https://discord.gg/dY9gHuyZN5)にご参加ください。


### azooKey on macOSを支援する

GitHub Sponsorsをご利用ください。


## 機能

* ニューラルかな漢字変換システム「Zenzai」による高精度な変換
  * プロフィールプロンプト機能
  * 履歴学習機能
  * ユーザ辞書機能
  * 個人最適化システム「[Tuner](https://github.com/azooKey/Tuner)」との連携機能
* LLMによる「いい感じ変換」機能
* ライブ変換
* AZIKのネイティブサポート
* Slack風ショートネーム絵文字入力（日本語入力中に `：` を打ち、`：smile` のように英字でインクリメンタル検索して絵文字を確定）
  * ON/OFFと起動トリガー文字は「設定 > カスタマイズ > 絵文字入力」で変更可能
  * 変換途中でトリガーを打っても、composingテキストを保持したまま絵文字を挿入できる


## 開発ガイド

コントリビュート歓迎です！！

### 必要な環境
* macOS 15+
* Xcode 26.1+
* Git LFS（必須。Hugging Face上のsubmoduleがLFSを利用しているため、未導入だとモデル重みが取得できません）
* SwiftLint

```bash
brew install git-lfs swiftlint
git lfs install
```

### 開発版のビルド・デバッグ

#### 1. クローン

submoduleにzenzのgguf重みと言語モデル（`.marisa`）が含まれるため、`--recursive`と Git LFS の有効化が必須です。

```bash
git lfs install        # 未実行の場合のみ
git clone https://github.com/azooKey/azooKey-Desktop --recursive
cd azooKey-Desktop
```

既にcloneしていてsubmoduleやLFSが揃っていない場合は以下を実行してください。

```bash
git submodule update --init
git -C azooKeyMac/Resources/zenz-v3.1-small-gguf lfs pull
git -C azooKeyMac/Resources/base_n5_lm lfs pull
```

重みファイルが正しく取得できているか、サイズで確認できます（数十MB以上あればLFSの実体、134B程度ならポインタのままです）。

```bash
ls -lh azooKeyMac/Resources/zenz-v3.1-small-gguf/ggml-model-Q5_K_M.gguf
```

#### 2. 署名の設定（初回のみ）

`install.sh` はアーカイブビルドを行うため、Xcode上で署名設定が通っている必要があります。Apple Developer Programに加入していない場合は、Personal Teamでの署名に切り替えてください。

* `azooKeyMac.xcodeproj` を Xcode で開く
* azooKeyMac ターゲット → Signing & Capabilities で Team を自身の Personal Team に変更
* リポジトリ内のバンドルID（`dev.ensan.inputmethod.azooKeyMac` など）を、自身の所有するプレフィックスに一括置換（例: `dev.yourname.inputmethod.azooKeyMac`）

#### 3. ビルド＆インストール

```bash
./install.sh
```

`.pkg`によるインストールと同等の状態になります。その後、上記の「リリース版インストール」の手順（ログアウト→入力ソース追加）を行ってください。

開発中はazooKeyのプロセスをkillすることで最新版を反映することが出来ます。また、必要に応じて入力ソースからazooKeyを削除して再度追加する、macOSからログアウトして再ログインするなど、リセットが必要になる場合があります。

### 開発時のトラブルシューティング

`install.sh`でビルドが成功しない場合、以下をご確認ください。

* 署名エラーで失敗する場合は、上記「署名の設定」が完了しているかを確認してください（Team変更とバンドルID置換の両方が必要です）
* 「Packages are not supported when using legacy build locations, but the current project has them enabled.」と表示される場合は[https://qiita.com/glassmonkey/items/3e8203900b516878ff2c](https://qiita.com/glassmonkey/items/3e8203900b516878ff2c)を参考に、Xcodeの設定をご確認ください
* Xcode 26.0ではビルドできない可能性があります。Xcode 16系または26.1以降をご利用ください。

変換精度がリリース版に比べて悪いと感じた場合、以下をご確認ください。
* Git LFSが導入されていない環境では、重みファイルがローカル環境に落とせていない場合があります。`azooKeyMac/Resources/zenz-v3.1-small-gguf/ggml-model-Q5_K_M.gguf` が数十MB以上あるかを確認し、ポインタのままであれば `git -C azooKeyMac/Resources/zenz-v3.1-small-gguf lfs pull` を実行してください

### pkgファイルの作成
`pkgbuild.sh`によって配布用のdmgファイルを作成できます。`build/azooKeyMac.app` としてDeveloper IDで署名済みの.appを配置してください。

### v1.0リリースに向けて
[meta: v1.0のリリースに向けたロードマップ（#181）](https://github.com/azooKey/azooKey-Desktop/issues/181)をご覧ください．

## Community Forks

### [fcitx5-hazkey](https://github.com/7ka-Hiira/fcitx5-hazkey)
@7ka-Hiira さんによるLinux系OS向けのクライアント実装です。

### [azooKey-Windows](https://github.com/fkunn1326/azooKey-Windows)
@fkunn1326 さんによるWindows向けクライアント実装です。

### [azoo-key-skkserv](https://github.com/gitusp/azoo-key-skkserv)
@gitusp さんによるSKKクライアント向けのSKKサーバ実装です。macOS向けGUIアプリケーションを含みます。

## Reference

Thanks to authors!!

* https://mzp.hatenablog.com/entry/2017/09/17/220320
* https://www.logcg.com/en/archives/2078.html
* https://stackoverflow.com/questions/27813151/how-to-develop-a-simple-input-method-for-mac-os-x-in-swift
* https://mzp.booth.pm/items/809262

## Third-Party Data

* 絵文字入力機能のショートネーム/絵文字対応表として、[iamcal/emoji-data](https://github.com/iamcal/emoji-data)（MIT License）の `emoji.json` をバンドルしています。

## Acknowledgement
本プロジェクトは情報処理推進機構(IPA)による[2024年度未踏IT人材発掘・育成事業](https://www.ipa.go.jp/jinzai/mitou/it/2024/koubokekka.html)の支援を受けて開発を行いました。

# azooKey on macOS

[azooKey](https://github.com/ensan-hcl/azooKey)のmacOS版です。高精度なニューラルかな漢字変換エンジン「Zenzai」を導入した、オープンソースの日本語入力システムです。

**現在アルファ版のため、動作は一切保証できません**。

## 動作環境

macOS 14とmacOS 15で動作確認しています。macOS 13でも利用できますが、動作は検証していません。

## リリース版インストール

[Releases](https://github.com/ensan-hcl/azooKey-Desktop/releases)から`.pkg`ファイルをダウンロードして、インストールしてください。

その後、以下の手順で利用できます。

- macOSからログアウトし、再ログイン
- 「設定」>「キーボード」>「入力ソース」を編集>「+」ボタン>「日本語」>azooKeyを追加>完了
- メニューバーアイコンからazooKeyを選択

### アップデート
azooKey on macOS は[**Sparkle**](https://sparkle-project.org/)を利用しており、起動後に自動で新しいバージョンがないか確認します。また、メニューバーの **azooKey** メニューから「Check for updates…」を選択することで手動で更新確認も行えます。

### Install with Homebrew
または、Homebrewを用いてインストールすることもできます。

```bash
brew install azooKey
```
この場合も上記のログアウト・再ログイン後の設定は必要です。
アップグレードは以下のコマンドで実行できます。

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

* ライブ変換
* LLMによる「いい感じ変換」機能
* その他の

## 開発ガイド

コントリビュート歓迎です！！

### 想定環境
* macOS 14+
* Xcode 16+
* Git LFS導入済み
* SwiftLint導入済み

### 開発版のビルド・デバッグ

まず、想定環境が整っていることを確認してください。 git-lfs のない状態では正しく clone できません。

cloneする際には`--recursive`をつけてサブモジュールまでローカルに落としてください。

```bash
git clone https://github.com/azooKey/azooKey-Desktop --recursive
```

以下のスクリプトを用いて最新のコードをビルドしてください。`.pkg`によるインストールと同等になります。その後、上記の手順を行ってください。また、submoduleが更新されている場合は `git submodule update --init` を行ってください。

```bash
# submoduleを更新
git submodule update --init

# ビルド＆インストール
./install.sh
```

開発中はazooKeyのプロセスをkillすることで最新版を反映することが出来ます。また、必要に応じて入力ソースからazooKeyを削除して再度追加する、macOSからログアウトして再ログインするなど、リセットが必要になる場合があります。

### 開発時のトラブルシューティング

`install.sh`でビルドが成功しない場合、以下をご確認ください。

* XcodeのGUI上で「Team ID」を変更する必要がある場合があります
  * `azooKeyMac.xcodeproj` を Xcode で開く
  * azooKeyMac -> Signing & Capabilities から、 Team を Personal Team に変更する
  * リポジトリ内に存在する全てのバンドルID文字列を、適当な文字列に置換 (ex: `dev.ensan.inputmethod.azooKeyMac` -> `dev.yourname.inputmethod.azooKeyMac`)
* 「Packages are not supported when using legacy build locations, but the current project has them enabled.」と表示される場合は[https://qiita.com/glassmonkey/items/3e8203900b516878ff2c](https://qiita.com/glassmonkey/items/3e8203900b516878ff2c)を参考に、Xcodeの設定をご確認ください

変換精度がリリース版に比べて悪いと感じた場合、以下をご確認ください。
* Git LFSが導入されていない環境では、重みファイルがローカル環境に落とせていない場合があります。`azooKey-Desktop/azooKeyMac/Resources/zenz-v3-small-gguf/ggml-model-Q5_K_M.gguf`が70MB程度のファイルとなっているかを確認してください

### pkgファイルの作成
`pkgbuild.sh`によって配布用のdmgファイルを作成できます。`build/azooKeyMac.app` としてDeveloper IDで署名済みの.appを配置してください。このスクリプトはSparkleの `sign_update` と `generate_appcast` を用いて署名付き`appcast.xml`を生成するため、ダウンロードURLや鍵情報を適宜書き換えて利用してください。

### TODO
* 予測変換を表示する
* CIを増やす
  * アルファ版を自動リリースする
* 「いい感じ変換」の改良
* 「Tuner」との相互運用性の向上

### Future Direction

* WindowsとLinuxもサポートする
  * @7ka-Hiira さんによる[fcitx5-hazkey](https://github.com/7ka-Hiira/fcitx5-hazkey)もご覧ください
  * @fkunn1326 さんによる[azooKey-Windows](https://github.com/fkunn1326/azooKey-Windows)もご覧ください

* iOS版のazooKeyと学習や設定を同期する

## Reference

Thanks to authors!!

* https://mzp.hatenablog.com/entry/2017/09/17/220320
* https://www.logcg.com/en/archives/2078.html
* https://stackoverflow.com/questions/27813151/how-to-develop-a-simple-input-method-for-mac-os-x-in-swift
* https://mzp.booth.pm/items/809262

## Acknowledgement
本プロジェクトは情報処理推進機構(IPA)による[2024年度未踏IT人材発掘・育成事業](https://www.ipa.go.jp/jinzai/mitou/it/2024/koubokekka.html)の支援を受けて開発を行いました。

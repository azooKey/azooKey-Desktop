# azooKey Windows TSF MVP 設計メモ

## 1. 必要COMクラス（MVP）

- `TextService`（`ITfTextInputProcessorEx`, `ITfKeyEventSink`, `ITfCompositionSink` 実装）
  - 入力キー受理
  - preedit文字列管理
  - composition開始/更新/確定/キャンセル
- `TextServiceFactory`（`IClassFactory`）
  - COMアクティベーションの入口
- DLLエクスポート
  - `DllGetClassObject`
  - `DllCanUnloadNow`
  - `DllRegisterServer` / `DllUnregisterServer`

将来追加（MVP後）:
- `ITfDisplayAttributeProvider`（未確定下線スタイル提供）
- `ITfUIElement` / `ITfCandidateListUIElementBehavior`（標準候補UI寄せ）
- `ITfLangBarItemButton`（言語バー状態表示）

## 2. スレッドモデル

- COM apartment: TSF text service DLLは `InProcServer32` でロードされるため、ホストアプリ文脈に従う。
- 方針:
  - UIスレッド境界でTSFインターフェースを扱う。
  - 推論/重い変換を将来的にワーカースレッドへ逃がす際は、
    - TSFオブジェクトへ直接触らない
    - 結果はメッセージ/キューでUIスレッドへ戻して反映
- 参照カウント:
  - `AddRef/Release` と `QueryInterface` を厳格実装
  - COMポインタは将来的に `wil::com_ptr` または `Microsoft::WRL::ComPtr` へ移行

## 3. Composition管理（MVPシーケンス）

1. 英字キー入力
   - `ITfKeyEventSink::OnKeyDown` で受理
   - `core::RomajiKanaConverter` へ逐次入力
2. preedit更新
   - 初回は `StartComposition()`
   - 以降 `UpdateComposition()`
3. 変換開始（Space）
   - `IConverter::Convert(kana, context)` で候補取得
   - MVPは内部で候補選択状態を保持（UI最小）
4. 確定（Enter）
   - 現選択候補またはpreedit全文を `CommitComposition()`
5. キャンセル（Esc）
   - `CancelComposition()` と内部状態リセット

## 4. 例外・障害耐性

- COM境界をまたぐ関数は**例外を外へ出さない**。
- 失敗時は `HRESULT` で返却し、ログに詳細を書き込む。
- 最低ログ要件:
  - `%LOCALAPPDATA%\azooKey\logs\tsf.log`
  - 起動/終了、例外、キーイベント要約、変換失敗理由

## 5. core層のAPI設計

- `Candidate { surface, reading, score, debug_info }`
- `IConverter`
  - `Convert(kana, context)`
  - `PredictNext(kana, context)`
  - `Learn(committed_surface, committed_reading)`
- 実装差し替え:
  - MVP: `SimpleConverter`（小辞書）
  - 次段: Zenzai/既存辞書ローダー接続実装

## 6. レジストリ/登録方針（MVP）

- `regsvr32` でCOM DLL登録
- `scripts/register.ps1` でTSFプロファイルキー作成（HKCU）
- `scripts/unregister.ps1` で逆操作

## 7. 互換性優先の実装ルール

- Notepad/Chrome/VSCode/Officeの挙動差を前提に、
  - 未処理キーは極力食わない
  - composition状態不整合時は安全側（キャンセル）で復帰
- ライブ変換/LLMは拡張ポイントのみ確保しMVPは無効。

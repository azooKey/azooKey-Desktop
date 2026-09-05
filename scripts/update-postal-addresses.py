#!/usr/bin/env python3
"""日本郵便の全国 UTF-8 CSV をオフライン変換用 TSV に変換する。標準ライブラリのみ使用。"""

import argparse
import csv
import datetime
import hashlib
import io
from pathlib import Path
import re
import urllib.request
import zipfile

SOURCE_PAGE = "https://www.post.japanpost.jp/service/search/zipcode/download/utf-zip.html"
SOURCE_URL = "https://www.post.japanpost.jp/service/search/zipcode/download/utf/zip/utf_ken_all.zip"
DESCRIPTION_URL = "https://www.post.japanpost.jp/service/search/zipcode/download/utf-readme.html"
ROOT = Path(__file__).resolve().parents[1]
MAX_ZIP_BYTES = 25 * 1024 * 1024
MAX_CSV_BYTES = 100 * 1024 * 1024


def convert_csv(contents: bytes) -> tuple[bytes, int, int]:
    """郵便番号を数値化せず、完全一致する郵便番号・住所ペアのみ重複除去する。"""
    entries = set()
    input_count = 0
    for line, row in enumerate(csv.reader(io.StringIO(contents.decode("utf-8-sig"), newline="")), 1):
        if len(row) != 15:
            raise ValueError(f"CSV {line}行目: 15列ではありません")
        postal_code = row[2]
        if not re.fullmatch(r"[0-9]{7}", postal_code):
            raise ValueError(f"CSV {line}行目: 郵便番号が7桁のASCII数字ではありません")
        prefecture, city, town = row[6:9]
        if not prefecture or not city:
            raise ValueError(f"CSV {line}行目: 都道府県・市区町村が空です")
        if town == "以下に掲載がない場合":
            town = ""
        address = prefecture + city + town
        if any(char in address for char in "\t\r\n"):
            raise ValueError(f"CSV {line}行目: 住所にTSVの区切り文字が含まれています")
        entries.add((postal_code, address))
        input_count += 1
    if not entries:
        raise ValueError("CSVに住所データがありません")
    output = "".join(f"{code}\t{address}\n" for code, address in sorted(entries)).encode("utf-8")
    return output, input_count, len({code for code, _ in entries})


def sha256(contents: bytes) -> str:
    return hashlib.sha256(contents).hexdigest()


def main() -> None:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--source-date", required=True, type=datetime.date.fromisoformat,
                        help="公式ページで確認したデータ更新日（YYYY-MM-DD）")
    parser.add_argument("--zip", type=Path, dest="zip_path", help="保存済み公式ZIPを使ってオフラインで再生成")
    parser.add_argument("--output", type=Path, default=ROOT / "Core/Sources/Core/Resources/postal-addresses.tsv")
    parser.add_argument("--documentation", type=Path, default=ROOT / "docs/postal-address-data.md")
    args = parser.parse_args()
    if args.zip_path:
        if args.zip_path.stat().st_size > MAX_ZIP_BYTES:
            raise ValueError("ZIPが想定サイズを超えています")
        archive = args.zip_path.read_bytes()
    else:
        with urllib.request.urlopen(SOURCE_URL, timeout=60) as response:
            archive = response.read(MAX_ZIP_BYTES + 1)
        if len(archive) > MAX_ZIP_BYTES:
            raise ValueError("ZIPが想定サイズを超えています")
    with zipfile.ZipFile(io.BytesIO(archive)) as zipped:
        members = [member for member in zipped.infolist() if not member.is_dir()]
        if len(members) != 1 or Path(members[0].filename).name.lower() != "utf_ken_all.csv":
            raise ValueError("全国版UTF-8 CSV以外のZIPです")
        if members[0].file_size > MAX_CSV_BYTES:
            raise ValueError("CSVが想定サイズを超えています")
        contents = zipped.read(members[0])
    output, input_count, postal_count = convert_csv(contents)
    output_count = output.count(b"\n")
    documentation = f"""# 郵便番号から住所への変換データ

日本郵便の全国町域データを加工した UTF-8 TSV をアプリに同梱します。入力時の通信は不要です。

- 出典：[日本郵便・住所の郵便番号（1レコード1行、UTF-8形式）]({SOURCE_PAGE})
- [元ZIP]({SOURCE_URL}) / [データ仕様・利用条件]({DESCRIPTION_URL})
- 元データ更新日：{args.source_date.isoformat()}
- 元CSVレコード数：{input_count:,}
- TSV住所行数：{output_count:,}
- 郵便番号数：{postal_count:,}

## 加工内容

CSVの第3列を7桁のASCII数字の文字列として読み、第7〜9列（都道府県・市区町村・町域）を連結します。
TSVはヘッダーなし、1行につき「郵便番号、タブ、住所、改行」です。先頭の0を保存します。
同じ郵便番号に複数の住所がある場合は別行で保持し、郵便番号と住所がともに一致する行だけ重複除去します。
郵便番号、住所の順でソートして再生成結果を一定にしています。
変換時はこのソート順を利用してTSVを二分探索し、一致する住所行だけを読み取ります。入力時に全国分の辞書を構築する処理はありません。

町域が「以下に掲載がない場合」と完全一致する場合だけ町域を省略します。
丁目・番地の条件、括弧、ビル階数、「一円」「次に番地がくる場合」など、それ以外の原文は残します。
このデータは町域の郵便番号が対象で、大口事業所の個別郵便番号は含みません。

## 利用条件

日本郵便は郵便番号データについて著作権を主張せず、自由な配布を認めています。
根拠は上記の公式説明ページ「使用・再配布・移植・改良について」です。
この説明は郵便番号データに限るもので、日本郵便サイト全体の画像・文章の再利用を意味しません。

## SHA-256

| 対象 | SHA-256 |
| --- | --- |
| ダウンロードしたZIP | `{sha256(archive)}` |
| ZIP内のCSV | `{sha256(contents)}` |
| 生成TSV | `{sha256(output)}` |

## 更新方法

公式ページで更新日を確認してから、リポジトリのルートで実行します。
生成スクリプトはPython標準ライブラリのみを使います。更新日は取得日時と混同せず明示指定します。

```sh
python3 scripts/update-postal-addresses.py --source-date {args.source_date.isoformat()}
```

保存済みの元ZIPを使う場合は `--zip /path/to/utf_ken_all.zip` を追加します。
公式の同じURLは月次で内容が更新されるため、同じ版を再生成するには元ZIPを保存してください。
スクリプトはTSVとこの説明ファイルを更新します。差分、件数、複数住所と先頭0の保持を確認してから反映します。
"""
    args.output.parent.mkdir(parents=True, exist_ok=True)
    args.documentation.parent.mkdir(parents=True, exist_ok=True)
    args.output.write_bytes(output)
    args.documentation.write_text(documentation, encoding="utf-8")
    print(f"元CSV {input_count:,}行 → TSV {output_count:,}行 / {postal_count:,}郵便番号")
    print(f"TSV SHA-256: {sha256(output)}")


if __name__ == "__main__":
    main()

@testable import Core
import Foundation
import Testing

@Suite("Postal address shortcuts")
struct PostalAddressShortcutsTests {
    @Test(arguments: ["2400054", "２４０００５４", "２4０0０5４"])
    func normalizesSevenDigits(_ input: String) {
        #expect(PostalAddressShortcuts.normalizedPostalCode(matching: input) == "2400054")
    }

    @Test(arguments: ["-", "ｰ", "ー", "－", "−"])
    func acceptsOnlyASeparatorAfterThreeDigits(_ separator: String) {
        #expect(PostalAddressShortcuts.normalizedPostalCode(matching: "240" + separator + "0054") == "2400054")
        #expect(PostalAddressShortcuts.normalizedPostalCode(matching: "２４０" + separator + "００５４") == "2400054")
        #expect(PostalAddressShortcuts.normalizedPostalCode(matching: "24" + separator + "00054") == nil)
        #expect(PostalAddressShortcuts.normalizedPostalCode(matching: "2400" + separator + "054") == nil)
    }

    @Test func preservesLeadingZeros() {
        #expect(PostalAddressShortcuts.normalizedPostalCode(matching: "0010001") == "0010001")
        #expect(PostalAddressShortcuts.normalizedPostalCode(matching: "００１ー０００１") == "0010001")
    }

    @Test(arguments: [
        "", "240054", "24000054", "240--0054", "240 0054", "240_0054", "240/0054", "240–0054", "240—0054",
        "〒2400054", " 2400054", "2400054 ", "2400054\n", "住所2400054", "2400054です", "24000a4",
        "٢٤٠٠٠٥٤", "②④⓪⓪⓪⑤④", "２４０〇〇５４", "＋2400054", "240.0054", "2400054-"
    ])
    func rejectsUnsupportedOrPartialInput(_ input: String) {
        #expect(PostalAddressShortcuts.normalizedPostalCode(matching: input) == nil)
        #expect(PostalAddressShortcuts.addresses(matching: input).isEmpty)
    }

    @Test func parserKeepsMultipleAddressesWithoutDuplicates() {
        let entries = PostalAddressShortcuts.parseAddresses("""
        0010001\t北海道テスト市一丁目
        0010001\t北海道テスト市二丁目
        0010001\t北海道テスト市一丁目
        0010002\t北海道テスト市三丁目
        """)
        #expect(entries["0010001"] == ["北海道テスト市一丁目", "北海道テスト市二丁目"])
        #expect(entries["0010002"] == ["北海道テスト市三丁目"])
        #expect(entries.count == 2)
    }

    @Test func parserRejectsMalformedRows() {
        let entries = PostalAddressShortcuts.parseAddresses("""
        invalid
        000001\t短い番号
        00000001\t長い番号
        ００１０００１\t非ASCII番号
        001-0001\t区切り付き番号
        0010001\t
        \t住所のみ
        0010001\t住所\t余分な列
        """)
        #expect(entries.isEmpty)
        #expect(PostalAddressShortcuts.parseAddresses("0010001\t   ").isEmpty)
    }

    @Test func parserAcceptsCRLFAndMissingFinalNewline() {
        let entries = PostalAddressShortcuts.parseAddresses("0010001\t住所一\r\n0010002\t住所二")
        #expect(entries["0010001"] == ["住所一"])
        #expect(entries["0010002"] == ["住所二"])
    }

    @Test(arguments: ["\n", "\r\n"])
    func directLookupFindsBoundaryRowsAndAllMatchingAddresses(newline: String) {
        // 最終行の改行なし、UTF-8 の長い行、同じ番号の複数行も検索する。
        let rows = [
            "0010001\t北海道テスト市一丁目",
            "0010001\t北海道テスト市二丁目",
            "0010001\t北海道テスト市二丁目",
            "2400054\t神奈川県横浜市保土ケ谷区西谷",
            "9999999\t末尾の住所"
        ]
        let data = Data(rows.joined(separator: newline).utf8)
        #expect(PostalAddressShortcuts.addresses(in: data, postalCode: "0010001") == ["北海道テスト市一丁目", "北海道テスト市二丁目"])
        #expect(PostalAddressShortcuts.addresses(in: data, postalCode: "2400054") == ["神奈川県横浜市保土ケ谷区西谷"])
        #expect(PostalAddressShortcuts.addresses(in: data, postalCode: "9999999") == ["末尾の住所"])
        for missing in ["0000000", "0010002", "9999998"] {
            #expect(PostalAddressShortcuts.addresses(in: data, postalCode: missing).isEmpty)
        }
    }

    @Test func directLookupHandlesEmptyAndSingleRowData() {
        #expect(PostalAddressShortcuts.addresses(in: Data(), postalCode: "2400054").isEmpty)
        for newline in ["", "\n"] {
            let data = Data(("2400054\t神奈川県横浜市保土ケ谷区西谷" + newline).utf8)
            #expect(PostalAddressShortcuts.addresses(in: data, postalCode: "2400054") == ["神奈川県横浜市保土ケ谷区西谷"])
            #expect(PostalAddressShortcuts.addresses(in: data, postalCode: "9999999").isEmpty)
        }
    }

    @Test func unknownPostalCodeHasNoCandidates() {
        #expect(PostalAddressShortcuts.addresses(matching: "0000000").isEmpty)
    }

    @Test func bundledLeadingZeroAndMultipleAddresses() {
        #expect(PostalAddressShortcuts.addresses(matching: "００１ー００００") == ["北海道札幌市北区"])
        #expect(Set(PostalAddressShortcuts.addresses(matching: "0040000")) == Set(["北海道札幌市厚別区", "北海道札幌市清田区"]))
    }

    @Test func bundledAddressForRequestedPostalCode() {
        let addresses = PostalAddressShortcuts.addresses(matching: "2400054")
        #expect(addresses == ["神奈川県横浜市保土ケ谷区西谷"])
        #expect(addresses == PostalAddressShortcuts.addresses(matching: "２４０ー００５４"))
        #expect(Set(addresses).count == addresses.count)
    }
}

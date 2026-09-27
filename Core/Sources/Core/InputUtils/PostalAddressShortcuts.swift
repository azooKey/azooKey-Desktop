import Foundation

enum PostalAddressShortcuts {
    // 生成スクリプトが郵便番号順に並べた TSV を直接検索し、初回入力でも全件の辞書構築を避ける。
    private static let addressData: Data = {
        guard let url = Bundle.module.url(forResource: "postal-addresses", withExtension: "tsv") else {
            return Data()
        }
        return (try? Data(contentsOf: url, options: .mappedIfSafe)) ?? Data()
    }()

    static func addresses(matching reading: String) -> [String] {
        guard let postalCode = normalizedPostalCode(matching: reading) else {
            return []
        }
        return addresses(in: addressData, postalCode: postalCode)
    }

    // 入力データは ASCII 郵便番号順の TSV。二分探索後、一致する行だけ UTF-8 として読む。
    static func addresses(in data: Data, postalCode: String) -> [String] {
        let key = Array(postalCode.utf8)
        guard key.count == 7, key.allSatisfy({ (0x30...0x39).contains($0) }) else {
            return []
        }
        return data.withUnsafeBytes { (bytes: UnsafeRawBufferPointer) -> [String] in
            var lower = 0
            var upper = bytes.count
            while lower < upper {
                var start = lower + (upper - lower) / 2
                while start > lower && bytes[start - 1] != 0x0A {
                    start -= 1
                }
                var end = start
                while end < bytes.count && bytes[end] != 0x0A {
                    end += 1
                }
                let codeEnd = min(start + 7, end)
                if bytes[start..<codeEnd].lexicographicallyPrecedes(key) {
                    lower = end < bytes.count ? end + 1 : end
                } else {
                    upper = start
                }
            }
            let first = lower
            while lower + 7 < bytes.count,
                  bytes[lower..<(lower + 7)].elementsEqual(key), bytes[lower + 7] == 0x09 {
                while lower < bytes.count && bytes[lower] != 0x0A {
                    lower += 1
                }
                if lower < bytes.count {
                    lower += 1
                }
            }
            guard lower > first else {
                return []
            }
            guard let matchingRows = String(bytes: bytes[first..<lower], encoding: .utf8) else {
                return []
            }
            return parseAddresses(matchingRows)[postalCode] ?? []
        }
    }

    static func normalizedPostalCode(matching reading: String) -> String? {
        let scalars = Array(reading.unicodeScalars)
        guard scalars.count == 7 || scalars.count == 8 else {
            return nil
        }
        var digits = ""
        digits.reserveCapacity(7)
        for (index, scalar) in scalars.enumerated() {
            if scalars.count == 8, index == 3 {
                switch scalar.value {
                case 0x2D, 0xFF70, 0x30FC, 0xFF0D, 0x2212:
                    continue
                default:
                    return nil
                }
            }
            switch scalar.value {
            case 0x30...0x39:
                digits.unicodeScalars.append(scalar)
            case 0xFF10...0xFF19:
                digits.unicodeScalars.append(Unicode.Scalar(scalar.value - 0xFF10 + 0x30)!)
            default:
                return nil
            }
        }
        return digits
    }

    static func parseAddresses(_ contents: String) -> [String: [String]] {
        var addresses: [String: [String]] = [:]
        for line in contents.split(whereSeparator: \.isNewline) {
            let fields = line.split(separator: "\t", maxSplits: 1, omittingEmptySubsequences: false)
            guard fields.count == 2 else {
                continue
            }
            let postalCode = String(fields[0])
            guard postalCode.utf8.count == 7,
                  postalCode.utf8.allSatisfy({ (0x30...0x39).contains($0) }) else {
                continue
            }
            let address = fields[1].trimmingCharacters(in: .whitespaces)
            guard !address.isEmpty, !address.contains("\t") else {
                continue
            }
            if !(addresses[postalCode]?.contains(address) ?? false) {
                addresses[postalCode, default: []].append(address)
            }
        }
        return addresses
    }
}

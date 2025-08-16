//
//  hankaku2zenkaku.swift
//  azooKeyMac
//
//  Created by miwa on 2024/03/25.
//

import Foundation

extension KeyMap {
    private static let h2z: [String: String] = [
        "!": "！",
        "\"": "”",
        "#": "＃",
        "$": "＄",
        "%": "％",
        "&": "＆",
        "'": "’",
        "(": "（",
        ")": "）",
        "=": "＝",
        "~": "〜",
        "|": "｜",
        "`": "｀",
        "{": "『",
        "+": "＋",
        "*": "＊",
        "}": "』",
        "<": "＜",
        ">": "＞",
        "?": "？",
        "_": "＿",
        "-": "ー",
        "^": "＾",
        "\\": "＼",
        "¥": "￥",
        "@": "＠",
        "[": "「",
        ";": "；",
        ":": "：",
        "]": "」",
        ",": "、",
        ".": "。",
        "/": "・"
    ]

    public static func h2zMap(_ text: String) -> String {
        h2z[text, default: text]
    }
}

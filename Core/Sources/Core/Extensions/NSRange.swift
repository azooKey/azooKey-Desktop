//
//  NSRange.swift
//  azooKeyMac
//
//  Created by miwa on 2024/03/18.
//

import Foundation

extension NSRange {
    static var notFound: NSRange {
        NSRange(location: NSNotFound, length: NSNotFound)
    }
}

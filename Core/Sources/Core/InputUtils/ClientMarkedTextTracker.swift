/// 入力先アプリに、azooKey が渡した未確定文字列が残っているかを追跡する。
///
/// `insertText` で確定すると、入力先アプリ側の未確定文字列はなくなる。
/// そのあとに空文字列で `setMarkedText` を送ると、アプリによっては
/// 長さ0の未確定範囲が残り続ける（macOS の「メモ」など）。
/// この範囲はカーソルを動かしても元の位置に残り、次の入力で
/// 先頭の文字が消える・意図しない改行が入るといった不具合の原因になる。
///
/// そのため、空の未確定文字列は「アプリ側に消すべき未確定文字列があるとき」だけ送る。
public struct ClientMarkedTextTracker: Sendable, Equatable {
    /// azooKey が渡した未確定文字列が、入力先アプリに残っているか
    public private(set) var clientHasMarkedText = false

    public init() {}

    /// `setMarkedText` を送る必要があるか
    /// - Parameter markedTextIsEmpty: これから送る未確定文字列が空か
    public func shouldSendMarkedText(markedTextIsEmpty: Bool) -> Bool {
        !markedTextIsEmpty || self.clientHasMarkedText
    }

    /// `setMarkedText` を送ったあとに呼ぶ
    public mutating func didSendMarkedText(markedTextIsEmpty: Bool) {
        self.clientHasMarkedText = !markedTextIsEmpty
    }

    /// `insertText` で確定したあとに呼ぶ（アプリ側の未確定文字列は確定によってなくなる）
    public mutating func didInsertText() {
        self.clientHasMarkedText = false
    }
}

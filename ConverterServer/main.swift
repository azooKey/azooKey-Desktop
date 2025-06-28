import Foundation

let listener = NSXPCListener(machServiceName: "dev.ensan.inputmethod.azooKeyMac.ConverterServer")
class ServiceDelegate: NSObject, NSXPCListenerDelegate {
    func listener(_ listener: NSXPCListener, shouldAcceptNewConnection conn: NSXPCConnection) -> Bool {
        conn.exportedInterface = NSXPCInterface(with: ConverterXPCProtocol.self)
        conn.exportedObject    = ConverterXPC()          // 既存ロジック
        conn.resume()
        return true
    }
}
let delegate = ServiceDelegate()
listener.delegate = delegate
listener.resume()
RunLoop.current.run()          // プロセスを常駐させる

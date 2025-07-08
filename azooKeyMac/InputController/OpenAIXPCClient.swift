//
//  OpenAIXPCClient.swift
//  azooKeyMac
//

import Foundation

@objc protocol OpenAIServiceProtocol {
    func sendRequest(
        prompt: String,
        mode: String,
        systemPrompt: String,
        model: String,
        apiKey: String,
        endpoint: String?,
        with reply: @escaping (String?, Error?) -> Void
    )
    
    func sendTextTransformRequest(
        text: String,
        prompt: String,
        context: String?,
        model: String,
        apiKey: String,
        endpoint: String?,
        with reply: @escaping (String?, Error?) -> Void
    )
}

class OpenAIXPCClient {
    private var connection: NSXPCConnection?
    
    init() {
        setupConnection()
    }
    
    deinit {
        connection?.invalidate()
    }
    
    private func setupConnection() {
        connection = NSXPCConnection(serviceName: "com.azooKey.azooKeyMac.OpenAIService")
        connection?.remoteObjectInterface = NSXPCInterface(with: OpenAIServiceProtocol.self)
        
        connection?.interruptionHandler = { [weak self] in
            print("XPC connection interrupted")
            self?.connection = nil
        }
        
        connection?.invalidationHandler = { [weak self] in
            print("XPC connection invalidated")
            self?.connection = nil
        }
        
        connection?.resume()
    }
    
    func sendRequest(
        prompt: String,
        mode: String,
        systemPrompt: String,
        model: String,
        apiKey: String,
        endpoint: String?
    ) async throws -> [String] {
        return try await withCheckedThrowingContinuation { continuation in
            guard let service = connection?.remoteObjectProxyWithErrorHandler({ error in
                continuation.resume(throwing: error)
            }) as? OpenAIServiceProtocol else {
                continuation.resume(throwing: NSError(domain: "OpenAIXPCClient", code: 1, userInfo: [NSLocalizedDescriptionKey: "Failed to connect to XPC service"]))
                return
            }
            
            service.sendRequest(
                prompt: prompt,
                mode: mode,
                systemPrompt: systemPrompt,
                model: model,
                apiKey: apiKey,
                endpoint: endpoint
            ) { result, error in
                if let error = error {
                    continuation.resume(throwing: error)
                } else if let result = result {
                    // Parse the result string into array
                    let predictions = result.components(separatedBy: "\n")
                    continuation.resume(returning: predictions)
                } else {
                    continuation.resume(throwing: NSError(domain: "OpenAIXPCClient", code: 2, userInfo: [NSLocalizedDescriptionKey: "No result returned"]))
                }
            }
        }
    }
    
    func sendTextTransformRequest(
        text: String,
        prompt: String,
        context: String?,
        model: String,
        apiKey: String,
        endpoint: String?
    ) async throws -> String {
        return try await withCheckedThrowingContinuation { continuation in
            guard let service = connection?.remoteObjectProxyWithErrorHandler({ error in
                continuation.resume(throwing: error)
            }) as? OpenAIServiceProtocol else {
                continuation.resume(throwing: NSError(domain: "OpenAIXPCClient", code: 1, userInfo: [NSLocalizedDescriptionKey: "Failed to connect to XPC service"]))
                return
            }
            
            service.sendTextTransformRequest(
                text: text,
                prompt: prompt,
                context: context,
                model: model,
                apiKey: apiKey,
                endpoint: endpoint
            ) { result, error in
                if let error = error {
                    continuation.resume(throwing: error)
                } else if let result = result {
                    continuation.resume(returning: result)
                } else {
                    continuation.resume(throwing: NSError(domain: "OpenAIXPCClient", code: 2, userInfo: [NSLocalizedDescriptionKey: "No result returned"]))
                }
            }
        }
    }
}
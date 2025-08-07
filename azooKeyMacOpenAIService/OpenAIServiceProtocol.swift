//
//  OpenAIServiceProtocol.swift
//  azooKeyMacOpenAIService
//

import Foundation

// swiftlint:disable function_parameter_count
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
// swiftlint:enable function_parameter_count

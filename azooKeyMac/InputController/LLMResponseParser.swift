import Foundation

enum LLMResponseParser {
    // Parse OpenAI-compatible chat completion response
    static func parseOpenAICompatibleResponse(_ data: Data, logger: ((String) -> Void)?) throws -> [String] {
        let jsonObject: Any
        do {
            jsonObject = try JSONSerialization.jsonObject(with: data)
        } catch {
            let dataString = String(data: data, encoding: .utf8) ?? "Invalid UTF-8 data"
            logger?("Failed to parse JSON response: \(dataString.prefix(100))")
            throw OpenAIError.parseError("Failed to parse JSON response: \(error.localizedDescription)")
        }

        guard let jsonDict = jsonObject as? [String: Any] else {
            logger?("Response is not a JSON object: \(jsonObject)")
            throw OpenAIError.invalidResponseStructure("Expected JSON object, got: \(type(of: jsonObject))")
        }

        guard let choices = jsonDict["choices"] as? [[String: Any]] else {
            logger?("Missing or invalid 'choices' field in response")
            throw OpenAIError.invalidResponseStructure("Missing or invalid 'choices' field")
        }

        var allPredictions: [String] = []
        for choice in choices {
            guard let message = choice["message"] as? [String: Any],
                  let contentString = message["content"] as? String else {
                continue
            }

            logger?("Raw content string: \(contentString)")

            guard let contentData = contentString.data(using: .utf8) else {
                logger?("Failed to convert `content` string to data")
                continue
            }

            do {
                guard let parsedContent = try JSONSerialization.jsonObject(with: contentData) as? [String: [String]],
                      let predictions = parsedContent["predictions"] else {
                    logger?("Failed to parse `content` as expected JSON dictionary: \(contentString)")
                    continue
                }

                logger?("Parsed predictions: \(predictions)")
                allPredictions.append(contentsOf: predictions)
            } catch {
                logger?("Error parsing JSON from `content`: \(error.localizedDescription)")
            }
        }

        return allPredictions
    }

    // Parse OpenAI-compatible text completion response
    static func parseOpenAITextResponse(_ data: Data) throws -> String {
        let jsonObject: Any
        do {
            jsonObject = try JSONSerialization.jsonObject(with: data)
        } catch {
            throw OpenAIError.parseError("Failed to parse JSON response: \(error.localizedDescription)")
        }

        guard let jsonDict = jsonObject as? [String: Any] else {
            throw OpenAIError.invalidResponseStructure("Expected JSON object, got: \(type(of: jsonObject))")
        }

        guard let choices = jsonDict["choices"] as? [[String: Any]], !choices.isEmpty else {
            throw OpenAIError.invalidResponseStructure("Missing or empty 'choices' field")
        }

        guard let firstChoice = choices.first,
              let message = firstChoice["message"] as? [String: Any],
              let content = message["content"] as? String else {
            throw OpenAIError.invalidResponseStructure("Invalid message structure in first choice")
        }

        return content.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    // Parse simple JSON array format (legacy support)
    static func parseSimpleJSONArray(_ data: Data, logger: ((String) -> Void)?) throws -> [String] {
        let jsonObject: Any
        do {
            jsonObject = try JSONSerialization.jsonObject(with: data)
        } catch {
            let dataString = String(data: data, encoding: .utf8) ?? "Invalid UTF-8 data"
            logger?("Failed to parse JSON array: \(dataString.prefix(100))")
            throw OpenAIError.parseError("Failed to parse JSON response: \(error.localizedDescription)")
        }

        if let predictions = jsonObject as? [String] {
            logger?("Parsed simple JSON array: \(predictions)")
            return predictions
        }

        if let jsonDict = jsonObject as? [String: Any],
           let predictions = jsonDict["predictions"] as? [String] {
            logger?("Parsed predictions from object: \(predictions)")
            return predictions
        }

        logger?("Unexpected JSON structure: \(jsonObject)")
        throw OpenAIError.invalidResponseStructure("Expected string array or object with 'predictions' field")
    }
}

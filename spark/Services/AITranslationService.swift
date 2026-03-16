//
//  AITranslationService.swift
//  spark
//
//  Created by Claude on 2026/3/16.
//

import Foundation

/// Real implementation of TranslationService using OpenAI-compatible API
class AITranslationService: TranslationService {
    private let urlSession: URLSession

    init(urlSession: URLSession = .shared) {
        self.urlSession = urlSession
    }

    func translate(text: String, config: ModelConfig, apiKey: String) async throws -> String {
        let endpoint = buildEndpoint(baseURL: config.baseURL)
        let request = try buildTranslationRequest(
            endpoint: endpoint,
            text: text,
            modelName: config.modelName,
            apiKey: apiKey
        )

        let (data, response) = try await urlSession.data(for: request)

        guard let httpResponse = response as? HTTPURLResponse else {
            throw TranslationError.invalidResponse
        }

        guard (200...299).contains(httpResponse.statusCode) else {
            throw TranslationError.httpError(statusCode: httpResponse.statusCode)
        }

        let apiResponse = try JSONDecoder().decode(OpenAIResponse.self, from: data)

        guard let translatedText = apiResponse.choices.first?.message.content else {
            throw TranslationError.emptyResponse
        }

        return translatedText
    }

    func testConnection(config: ModelConfig, apiKey: String) async -> Result<String, Error> {
        do {
            // Use a simple test prompt to verify connectivity
            let testText = "你好"
            _ = try await translate(text: testText, config: config, apiKey: apiKey)
            return .success("Connection successful to \(config.modelName)")
        } catch {
            return .failure(error)
        }
    }

    // MARK: - Private Helpers

    private func buildEndpoint(baseURL: String?) -> URL {
        let defaultURL = "https://api.openai.com/v1/chat/completions"
        guard let baseURL = baseURL, !baseURL.isEmpty else {
            return URL(string: defaultURL)!
        }

        // If baseURL doesn't end with the chat completions path, append it
        if baseURL.hasSuffix("/chat/completions") {
            return URL(string: baseURL)!
        } else if baseURL.hasSuffix("/v1") {
            return URL(string: "\(baseURL)/chat/completions")!
        } else {
            return URL(string: "\(baseURL)/v1/chat/completions")!
        }
    }

    private func buildTranslationRequest(
        endpoint: URL,
        text: String,
        modelName: String,
        apiKey: String
    ) throws -> URLRequest {
        var request = URLRequest(url: endpoint)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")

        let payload = OpenAIRequest(
            model: modelName,
            messages: [
                OpenAIMessage(
                    role: "system",
                    content: "You are a professional translator. Translate the following Chinese text to English. Only output the English translation, nothing else."
                ),
                OpenAIMessage(
                    role: "user",
                    content: text
                )
            ],
            temperature: 0.3,
            maxTokens: 1000
        )

        request.httpBody = try JSONEncoder().encode(payload)
        return request
    }
}

// MARK: - API Models

private struct OpenAIRequest: Codable {
    let model: String
    let messages: [OpenAIMessage]
    let temperature: Double
    let maxTokens: Int

    enum CodingKeys: String, CodingKey {
        case model
        case messages
        case temperature
        case maxTokens = "max_tokens"
    }
}

private struct OpenAIMessage: Codable {
    let role: String
    let content: String
}

private struct OpenAIResponse: Codable {
    let choices: [Choice]

    struct Choice: Codable {
        let message: Message

        struct Message: Codable {
            let content: String
        }
    }
}

// MARK: - Errors

enum TranslationError: LocalizedError {
    case invalidResponse
    case httpError(statusCode: Int)
    case emptyResponse

    var errorDescription: String? {
        switch self {
        case .invalidResponse:
            return "Invalid response from translation API"
        case .httpError(let statusCode):
            return "HTTP error: \(statusCode)"
        case .emptyResponse:
            return "Empty translation response"
        }
    }
}

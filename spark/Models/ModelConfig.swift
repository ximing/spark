//
//  ModelConfig.swift
//  spark
//
//  Created by Claude on 2026/3/16.
//

import Foundation

/// Configuration for an AI translation model
struct ModelConfig: Identifiable, Codable, Equatable {
    let id: UUID
    var name: String
    var modelName: String
    var baseURL: String?
    var isActive: Bool

    init(
        id: UUID = UUID(),
        name: String,
        modelName: String,
        baseURL: String? = nil,
        isActive: Bool = false
    ) {
        self.id = id
        self.name = name
        self.modelName = modelName
        self.baseURL = baseURL
        self.isActive = isActive
    }

    /// Creates a copy with isActive toggled
    func withActive(_ active: Bool) -> ModelConfig {
        ModelConfig(
            id: id,
            name: name,
            modelName: modelName,
            baseURL: baseURL,
            isActive: active
        )
    }
}

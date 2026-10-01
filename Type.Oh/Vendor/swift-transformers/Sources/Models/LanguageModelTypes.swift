//
//  LanguageModelTypes.swift
//  
//
//  Created by Pedro Cuenca on 8/5/23.
//

import CoreML
import Tokenizers
import Generation

public protocol LanguageModelProtocol {
    /// `name_or_path` in the Python world
    var modelName: String { get }

    var tokenizer: Tokenizer { get async throws }
    var model: MLModel { get }
    
    init(model: MLModel)
    
    /// Make prediction callable (this works like __call__ in Python)
    func predictNextTokenScores(_ tokens: InputTokens, config: GenerationConfig) -> any MLShapedArrayProtocol
    func callAsFunction(_ tokens: InputTokens, config: GenerationConfig) -> any MLShapedArrayProtocol
}

public extension LanguageModelProtocol {
    func callAsFunction(_ tokens: InputTokens, config: GenerationConfig) -> any MLShapedArrayProtocol {
        predictNextTokenScores(tokens, config: config)
    }
}

public protocol TextGenerationModel: Generation, LanguageModelProtocol {
    var defaultGenerationConfig: GenerationConfig { get }
    func generate(config: GenerationConfig, prompt: String, callback: PredictionStringCallback?) async throws -> String
}

public extension TextGenerationModel {
    @discardableResult
    func generate(config: GenerationConfig, prompt: String, callback: PredictionStringCallback? = nil) async throws -> String {
        // Patched for swift.org toolchains: passing `self.callAsFunction` as a
        // method reference trips the SIL ownership verifier ("leak due to a
        // consuming post-dominance failure"). An explicit closure compiles.
        // Resolving the async throwing `tokenizer` getter before creating the
        // model closure keeps the closure's lifetime simple for the verifier.
        let tokenizer = try await self.tokenizer
        let model: (InputTokens, GenerationConfig) -> any MLShapedArrayProtocol = { tokens, config in
            self.callAsFunction(tokens, config: config)
        }
        return try await self.generate(config: config, prompt: prompt, model: model, tokenizer: tokenizer, callback: callback)
    }
}

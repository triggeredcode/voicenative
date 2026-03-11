import Foundation

enum TechnicalDictionary {
    static let defaultTerms: [String] = [
        "LSM-tree",
        "SSTable",
        "SSTables",
        "Protobuf",
        "gRPC",
        "SwiftUI",
        "SwiftData",
        "MLX",
        "CoreML",
        "AVFoundation",
        "WhisperKit",
        "Ollama",
        "MochiStack",
        "agentic",
        "RAG",
        "embeddings",
        "vector database",
        "LLM",
        "transformer",
        "attention mechanism",
        "fine-tuning",
        "quantization",
        "inference",
        "tokenizer",
        "prompt engineering",
        "API",
        "REST",
        "GraphQL",
        "WebSocket",
        "microservices",
        "Kubernetes",
        "Docker",
        "CI/CD",
        "GitHub Actions",
        "async/await",
        "concurrency",
        "actor model",
        "Sendable",
        "MainActor"
    ]
    
    static func customTerms(from storage: String) -> [String] {
        storage
            .split(separator: "\n")
            .map { String($0).trimmingCharacters(in: .whitespaces) }
            .filter { !$0.isEmpty }
    }
    
    static func allTerms(customStorage: String) -> [String] {
        defaultTerms + customTerms(from: customStorage)
    }
}

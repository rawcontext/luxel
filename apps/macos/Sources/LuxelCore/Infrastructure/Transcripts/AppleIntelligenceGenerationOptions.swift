import FoundationModels

enum AppleIntelligenceGenerationOptions {
    static func greedy(maximumResponseTokens: Int) -> GenerationOptions {
        #if compiler(>=6.4)
            GenerationOptions(samplingMode: .greedy, temperature: 0, maximumResponseTokens: maximumResponseTokens)
        #else
            GenerationOptions(sampling: .greedy, temperature: 0, maximumResponseTokens: maximumResponseTokens)
        #endif
    }
}

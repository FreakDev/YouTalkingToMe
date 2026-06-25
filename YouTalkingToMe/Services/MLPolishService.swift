import Foundation
import HuggingFace
import MLX
import MLXLLM
import MLXLMCommon

@MainActor
final class MLPolishService {
    private var modelContainer: ModelContainer?
    private var loadedTier: ModelTier?

    var isLoaded: Bool { modelContainer != nil }

    func loadModel(
        tier: ModelTier,
        onProgress: @Sendable @escaping (String, String, Double) -> Void
    ) async throws {
        if loadedTier == tier, modelContainer != nil {
            return
        }

        unload()

        let configuration = ModelConfiguration(id: tier.polishModel)
        let modelName = configuration.name
        onProgress("download_polish", modelName, 0)

        Memory.cacheLimit = 20 * 1024 * 1024

        let cache = HubCache(cacheDirectory: AppPaths.modelsDirectory)
        let hub = HubClient(cache: cache)
        let container = try await LLMModelFactory.shared.loadContainer(
            from: HuggingFaceHubDownloader(hub),
            using: HuggingFaceBridgeTokenizerLoader(),
            configuration: configuration
        ) { progress in
            Task { @MainActor in
                onProgress("download_polish", modelName, progress.fractionCompleted)
            }
        }

        modelContainer = container
        loadedTier = tier
        onProgress("download_polish", modelName, 1)
    }

    func polish(_ rawText: String) async throws -> String {
        let trimmed = rawText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return "" }
        guard let modelContainer else {
            throw DictationError.inferenceNotReady
        }

        let session = ChatSession(
            modelContainer,
            instructions: PolishPromptBuilder.systemInstructions,
            generateParameters: GenerateParameters(maxTokens: 512, temperature: 0.2),
            additionalContext: ["enable_thinking": false]
        )

        let response = try await session.respond(to: PolishPromptBuilder.userPrompt(for: trimmed))
        return PolishOutputSanitizer.sanitize(response)
    }

    func unload() {
        modelContainer = nil
        loadedTier = nil
    }
}

import Foundation

final class InferenceClient: @unchecked Sendable {
    private var process: Process?
    private var inputPipe: Pipe?
    private var outputPipe: Pipe?
    private var pendingHandlers: [UUID: (Result<InferenceEvent, Error>) -> Void] = [:]
    private var progressHandler: (@Sendable (String, String, Double) -> Void)?
    private let queue = DispatchQueue(label: "InferenceClient.queue")
    private var outputBuffer = ""
    private var isReady = false

    func start() throws {
        guard process == nil else { return }

        let inferenceDir = findInferenceDirectory()
        let python = InferenceDirectoryResolver.pythonExecutable(in: inferenceDir)
        let server = inferenceDir.appendingPathComponent("server.py")

        let proc = Process()
        proc.executableURL = python
        proc.arguments = [server.path]
        proc.currentDirectoryURL = inferenceDir
        var environment = ProcessInfo.processInfo.environment
        environment[AppPaths.modelsCacheEnvironmentKey] = AppPaths.modelsDirectory.path
        proc.environment = environment

        let input = Pipe()
        let output = Pipe()
        let errorPipe = Pipe()
        proc.standardInput = input
        proc.standardOutput = output
        proc.standardError = errorPipe

        errorPipe.fileHandleForReading.readabilityHandler = { handle in
            let data = handle.availableData
            guard !data.isEmpty, let text = String(data: data, encoding: .utf8) else { return }
            let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !trimmed.isEmpty else { return }
            let isProgress = trimmed.contains("Fetching") || trimmed.contains("|")
            if isProgress {
                AppLogger.debug("[inference stderr] \(trimmed)")
            } else {
                AppLogger.error("[inference stderr] \(trimmed)")
            }
        }

        output.fileHandleForReading.readabilityHandler = { [weak self] handle in
            let data = handle.availableData
            guard !data.isEmpty else { return }
            self?.handleOutput(data)
        }

        try proc.run()
        process = proc
        inputPipe = input
        outputPipe = output
        AppLogger.info("Inference server started at \(server.path)")
    }

    func stop() {
        if let process {
            process.terminate()
        }
        process = nil
        inputPipe = nil
        outputPipe = nil
        isReady = false
        queue.async { [weak self] in
            self?.pendingHandlers.removeAll()
            self?.progressHandler = nil
        }
    }

    func ping() async throws {
        let event = try await send(command: "ping")
        guard case .pingResult(let ok, _) = event, ok else {
            throw DictationError.inferenceNotReady
        }
    }

    func loadModels(
        tier: ModelTier,
        onProgress: @Sendable @escaping (String, String, Double) -> Void
    ) async throws {
        progressHandler = onProgress
        defer { progressHandler = nil }

        let event = try await send(
            command: "load_models",
            payload: ["tier": tier.rawValue],
            timeout: 600
        )
        guard case .loadModelsResult = event else {
            throw DictationError.inferenceNotReady
        }
        isReady = true
    }

    func transcribe(audioURL: URL) async throws -> String {
        guard isReady else { throw DictationError.inferenceNotReady }
        AppLogger.info("Sending transcribe for \(audioURL.lastPathComponent)")
        let event = try await send(
            command: "transcribe",
            payload: ["audio_path": audioURL.path],
            timeout: 120
        )
        guard case .transcribeResult(let text, _) = event else {
            throw DictationError.inferenceNotReady
        }
        return text
    }

    private func send(
        command: String,
        payload: [String: Any] = [:],
        timeout: TimeInterval = 300
    ) async throws -> InferenceEvent {
        try startIfNeeded()

        let requestID = UUID()
        var body: [String: Any] = [
            "command": command,
            "request_id": requestID.uuidString,
        ]
        for (key, value) in payload {
            body[key] = value
        }
        let data = try JSONSerialization.data(withJSONObject: body)
        guard let jsonLine = String(data: data, encoding: .utf8) else {
            throw DictationError.inferenceNotReady
        }

        return try await withCheckedThrowingContinuation { continuation in
            queue.async { [weak self] in
                guard let self, let inputPipe else {
                    continuation.resume(throwing: DictationError.inferenceNotReady)
                    return
                }

                self.pendingHandlers[requestID] = { result in
                    continuation.resume(with: result)
                }
                inputPipe.fileHandleForWriting.write((jsonLine + "\n").data(using: .utf8)!)
            }

            Task { [weak self] in
                try await Task.sleep(nanoseconds: UInt64(timeout * 1_000_000_000))
                self?.failRequest(
                    requestID,
                    error: NSError(
                        domain: "InferenceClient",
                        code: 2,
                        userInfo: [NSLocalizedDescriptionKey: "Délai d'inférence expiré (\(Int(timeout))s)."]
                    )
                )
            }
        }
    }

    private func startIfNeeded() throws {
        if process == nil {
            try start()
        }
    }

    private func handleOutput(_ data: Data) {
        guard let chunk = String(data: data, encoding: .utf8) else { return }
        outputBuffer += chunk

        while let newlineIndex = outputBuffer.firstIndex(of: "\n") {
            let line = String(outputBuffer[..<newlineIndex])
            outputBuffer = String(outputBuffer[outputBuffer.index(after: newlineIndex)...])
            processLine(line)
        }
    }

    private func processLine(_ line: String) {
        guard let event = InferenceEvent.decodeLine(line) else { return }

        switch event {
        case .progress(let stage, let model, let percent, _):
            progressHandler?(stage, model, percent)
        case .error(let message, let requestID):
            AppLogger.error("Inference server error: \(message)")
            if let requestID, let id = UUID(uuidString: requestID) {
                failRequest(
                    id,
                    error: NSError(
                        domain: "InferenceClient",
                        code: 1,
                        userInfo: [NSLocalizedDescriptionKey: message]
                    )
                )
            }
        case .pingResult, .loadModelsResult, .transcribeResult:
            resolveRequest(for: event)
        }
    }

    private func resolveRequest(for event: InferenceEvent) {
        guard let requestID = event.requestID, let id = UUID(uuidString: requestID) else { return }
        queue.async { [weak self] in
            guard let self, let handler = self.pendingHandlers.removeValue(forKey: id) else { return }
            handler(.success(event))
        }
    }

    private func failRequest(_ requestID: UUID, error: Error) {
        queue.async { [weak self] in
            guard let self, let handler = self.pendingHandlers.removeValue(forKey: requestID) else { return }
            handler(.failure(error))
        }
    }

    private func findInferenceDirectory() -> URL {
        InferenceDirectoryResolver.resolve(
            bundleResourceURL: Bundle.main.resourceURL,
            srcRoot: ProcessInfo.processInfo.environment["SRCROOT"],
            currentDirectory: FileManager.default.currentDirectoryPath,
            fallbackPath: FileManager.default.currentDirectoryPath + "/inference"
        )
    }
}

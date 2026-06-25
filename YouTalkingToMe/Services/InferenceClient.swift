import Foundation

struct InferenceMessage: Decodable {
    let type: String
    let command: String?
    let text: String?
    let rawText: String?
    let message: String?
    let stage: String?
    let model: String?
    let percent: Double?
    let tier: String?
    let ok: Bool?

    enum CodingKeys: String, CodingKey {
        case type
        case command
        case text
        case rawText = "raw_text"
        case message
        case stage
        case model
        case percent
        case tier
        case ok
    }
}

final class InferenceClient: @unchecked Sendable {
    private var process: Process?
    private var inputPipe: Pipe?
    private var outputPipe: Pipe?
    private var pendingHandlers: [String: (Result<InferenceMessage, Error>) -> Void] = [:]
    private var loadHandler: ((InferenceMessage) -> Void)?
    private let queue = DispatchQueue(label: "InferenceClient.queue")
    private var outputBuffer = ""
    private var isReady = false

    var onProgress: ((String, String, Double) -> Void)?

    func start() throws {
        guard process == nil else { return }

        let inferenceDir = findInferenceDirectory()
        let python = InferenceDirectoryResolver.pythonExecutable(in: inferenceDir)
        let server = inferenceDir.appendingPathComponent("server.py")

        let proc = Process()
        proc.executableURL = python
        proc.arguments = [server.path]
        proc.currentDirectoryURL = inferenceDir

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
    }

    func ping() async throws {
        let message = try await send(command: "ping")
        guard message.ok == true else {
            throw DictationError.inferenceNotReady
        }
    }

    func loadModels(tier: ModelTier, onProgress: @Sendable @escaping (String, String, Double) -> Void) async throws {
        loadHandler = { message in
            if message.type == "progress", let stage = message.stage, let model = message.model, let percent = message.percent {
                onProgress(stage, model, percent)
            }
        }
        let message = try await send(command: "load_models", payload: ["tier": tier.rawValue], timeout: 600)
        loadHandler = nil
        guard message.command == "load_models" else {
            throw DictationError.inferenceNotReady
        }
        isReady = true
    }

    func transcribe(audioURL: URL) async throws -> String {
        guard isReady else { throw DictationError.inferenceNotReady }
        AppLogger.info("Sending transcribe for \(audioURL.lastPathComponent)")
        let message = try await send(
            command: "transcribe",
            payload: ["audio_path": audioURL.path],
            timeout: 120
        )
        return message.text ?? ""
    }

    private func send(command: String, payload: [String: Any] = [:], timeout: TimeInterval = 300) async throws -> InferenceMessage {
        try startIfNeeded()

        var body: [String: Any] = ["command": command]
        for (key, value) in payload {
            body[key] = value
        }
        let data = try JSONSerialization.data(withJSONObject: body)
        guard let jsonLine = String(data: data, encoding: .utf8) else {
            throw DictationError.inferenceNotReady
        }

        return try await withThrowingTaskGroup(of: InferenceMessage.self) { group in
            group.addTask {
                try await withCheckedThrowingContinuation { continuation in
                    self.queue.async { [weak self] in
                        guard let self, let inputPipe else {
                            continuation.resume(throwing: DictationError.inferenceNotReady)
                            return
                        }
                        self.pendingHandlers[command] = { result in
                            continuation.resume(with: result)
                        }
                        inputPipe.fileHandleForWriting.write((jsonLine + "\n").data(using: .utf8)!)
                    }
                }
            }

            group.addTask {
                try await Task.sleep(nanoseconds: UInt64(timeout * 1_000_000_000))
                throw NSError(
                    domain: "InferenceClient",
                    code: 2,
                    userInfo: [NSLocalizedDescriptionKey: "Délai d'inférence expiré (\(Int(timeout))s)."]
                )
            }

            let result = try await group.next()!
            group.cancelAll()
            return result
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
        guard let message = InferenceMessage.decodeLine(line) else { return }

        if message.type == "progress" {
            if let handler = loadHandler {
                handler(message)
            } else if let stage = message.stage, let model = message.model, let percent = message.percent {
                onProgress?(stage, model, percent)
            }
            return
        }

        if message.type == "error" {
            let errorMessage = message.message ?? "Inference error"
            AppLogger.error("Inference server error: \(errorMessage)")
            resolvePending(with: .failure(NSError(domain: "InferenceClient", code: 1, userInfo: [NSLocalizedDescriptionKey: errorMessage])))
            return
        }

        if message.type == "result", let command = message.command {
            resolvePending(command: command, result: .success(message))
        }
    }

    private func resolvePending(command: String, result: Result<InferenceMessage, Error>) {
        queue.async { [weak self] in
            guard let self else { return }
            if let handler = self.pendingHandlers.removeValue(forKey: command) {
                handler(result)
            }
        }
    }

    private func resolvePending(with result: Result<InferenceMessage, Error>) {
        queue.async { [weak self] in
            guard let self else { return }
            for (_, handler) in self.pendingHandlers {
                handler(result)
            }
            self.pendingHandlers.removeAll()
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

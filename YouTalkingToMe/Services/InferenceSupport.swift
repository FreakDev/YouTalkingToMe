import Foundation

extension InferenceMessage {
    static func decodeLine(_ line: String) -> InferenceMessage? {
        guard !line.isEmpty, let lineData = line.data(using: .utf8) else { return nil }
        return try? JSONDecoder().decode(InferenceMessage.self, from: lineData)
    }
}

enum InferenceDirectoryResolver {
    static func resolve(
        bundleResourceURL: URL?,
        srcRoot: String?,
        currentDirectory: String,
        fallbackPath: String,
        fileManager: FileManager = .default
    ) -> URL {
        let candidates: [URL] = [
            bundleResourceURL?.appendingPathComponent("inference"),
            srcRoot.map { URL(fileURLWithPath: $0).appendingPathComponent("inference") },
            URL(fileURLWithPath: currentDirectory).appendingPathComponent("inference"),
        ].compactMap { $0 }

        for url in candidates {
            let serverPath = url.appendingPathComponent("server.py").path
            if fileManager.fileExists(atPath: serverPath) {
                return url
            }
        }

        return URL(fileURLWithPath: fallbackPath)
    }

    static func pythonExecutable(in inferenceDirectory: URL, fileManager: FileManager = .default) -> URL {
        let venvPython = inferenceDirectory.appendingPathComponent(".venv/bin/python")
        if fileManager.fileExists(atPath: venvPython.path) {
            return venvPython
        }
        return URL(fileURLWithPath: "/usr/bin/python3")
    }
}

protocol InferenceServing: AnyObject, Sendable {
    func transcribeAndPolish(audioURL: URL) async throws -> (raw: String, polished: String)
}

protocol AudioCapturing: AnyObject {
    func start() throws
    func stop() -> URL?
}

extension AudioCapture: AudioCapturing {}

protocol TextInjecting: AnyObject {
    @MainActor
    func inject(_ text: String) -> (success: Bool, method: TextInjectionMethod?)
}

extension TextInjector: TextInjecting {}

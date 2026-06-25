import Foundation

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

protocol STTServing: AnyObject, Sendable {
    func transcribe(audioURL: URL) async throws -> String
}

protocol PolishServing: AnyObject, Sendable {
    func polish(_ rawText: String) async throws -> String
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

extension InferenceClient: STTServing {}

extension MLPolishService: PolishServing {}

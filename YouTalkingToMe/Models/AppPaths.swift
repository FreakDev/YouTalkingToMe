import Foundation

enum AppPaths {
    static let modelsCacheEnvironmentKey = "YTTM_MODELS_CACHE_DIR"

    static var modelsDirectory: URL {
        let appSupport = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
        let directory = appSupport.appendingPathComponent("YouTalkingToMe/models", isDirectory: true)
        try? FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        return directory
    }
}

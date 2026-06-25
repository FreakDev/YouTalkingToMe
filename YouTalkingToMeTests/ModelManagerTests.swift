import Foundation
import XCTest
@testable import YouTalkingToMe

final class ModelManagerTests: XCTestCase {
    func testCacheDirectoryNameMatchesHuggingFaceLayout() {
        XCTAssertEqual(
            ModelManager.cacheDirectoryName(for: "mlx-community/whisper-small-mlx"),
            "models--mlx-community--whisper-small-mlx"
        )
    }

    func testIsModelInstalledRequiresSnapshotContent() throws {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        defer { try? FileManager.default.removeItem(at: root) }

        let manager = ModelManager(inferenceClient: InferenceClient())
        let repo = "mlx-community/whisper-small-mlx"
        let cacheDirectory = root
            .appendingPathComponent(ModelManager.cacheDirectoryName(for: repo), isDirectory: true)
        let snapshotDirectory = cacheDirectory
            .appendingPathComponent("snapshots/abc123", isDirectory: true)

        try FileManager.default.createDirectory(at: snapshotDirectory, withIntermediateDirectories: true)
        XCTAssertFalse(manager.isModelInstalled(repo: repo, cacheRoot: root))

        try Data("weights".utf8).write(to: snapshotDirectory.appendingPathComponent("weights.safetensors"))
        XCTAssertTrue(manager.isModelInstalled(repo: repo, cacheRoot: root))
    }

    func testTierInstallStatusReflectsBothModels() throws {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        defer { try? FileManager.default.removeItem(at: root) }

        let manager = ModelManager(inferenceClient: InferenceClient())
        let tier = ModelTier.fast

        XCTAssertEqual(
            TierInstallStatus(
                tier: tier,
                sttInstalled: manager.isModelInstalled(repo: tier.sttModel, cacheRoot: root),
                polishInstalled: manager.isModelInstalled(repo: tier.polishModel, cacheRoot: root)
            ).statusLabel,
            "Absent"
        )

        let sttSnapshot = root
            .appendingPathComponent(ModelManager.cacheDirectoryName(for: tier.sttModel), isDirectory: true)
            .appendingPathComponent("snapshots/abc123", isDirectory: true)
        try FileManager.default.createDirectory(at: sttSnapshot, withIntermediateDirectories: true)
        try Data("weights".utf8).write(to: sttSnapshot.appendingPathComponent("weights.safetensors"))

        let partial = TierInstallStatus(
            tier: tier,
            sttInstalled: manager.isModelInstalled(repo: tier.sttModel, cacheRoot: root),
            polishInstalled: manager.isModelInstalled(repo: tier.polishModel, cacheRoot: root)
        )
        XCTAssertEqual(partial.statusLabel, "Partiel")

        let polishSnapshot = root
            .appendingPathComponent(ModelManager.cacheDirectoryName(for: tier.polishModel), isDirectory: true)
            .appendingPathComponent("snapshots/def456", isDirectory: true)
        try FileManager.default.createDirectory(at: polishSnapshot, withIntermediateDirectories: true)
        try Data("weights".utf8).write(to: polishSnapshot.appendingPathComponent("weights.safetensors"))

        let complete = TierInstallStatus(
            tier: tier,
            sttInstalled: manager.isModelInstalled(repo: tier.sttModel, cacheRoot: root),
            polishInstalled: manager.isModelInstalled(repo: tier.polishModel, cacheRoot: root)
        )
        XCTAssertEqual(complete.statusLabel, "Téléchargé")
    }
}

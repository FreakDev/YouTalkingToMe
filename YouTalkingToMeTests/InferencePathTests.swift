import Foundation
import XCTest
@testable import YouTalkingToMe

final class InferencePathTests: XCTestCase {
    func testResolveUsesSrcRootWhenServerExists() throws {
        let tmp = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        let inference = tmp.appendingPathComponent("inference", isDirectory: true)
        try FileManager.default.createDirectory(at: inference, withIntermediateDirectories: true)
        FileManager.default.createFile(
            atPath: inference.appendingPathComponent("server.py").path,
            contents: Data()
        )
        defer { try? FileManager.default.removeItem(at: tmp) }

        let resolved = InferenceDirectoryResolver.resolve(
            bundleResourceURL: nil,
            srcRoot: tmp.path,
            currentDirectory: "/nonexistent",
            fallbackPath: "/fallback/inference"
        )

        XCTAssertEqual(resolved.standardizedFileURL, inference.standardizedFileURL)
    }

    func testResolveFallsBackWhenNoCandidateExists() {
        let resolved = InferenceDirectoryResolver.resolve(
            bundleResourceURL: nil,
            srcRoot: nil,
            currentDirectory: "/nonexistent/path",
            fallbackPath: "/custom/fallback/inference"
        )

        XCTAssertEqual(resolved.path, "/custom/fallback/inference")
    }

    func testPythonExecutablePrefersVenv() throws {
        let tmp = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        let inference = tmp.appendingPathComponent("inference", isDirectory: true)
        let venvBin = inference.appendingPathComponent(".venv/bin", isDirectory: true)
        try FileManager.default.createDirectory(at: venvBin, withIntermediateDirectories: true)
        let python = venvBin.appendingPathComponent("python")
        FileManager.default.createFile(atPath: python.path, contents: Data())
        defer { try? FileManager.default.removeItem(at: tmp) }

        let resolved = InferenceDirectoryResolver.pythonExecutable(in: inference)
        XCTAssertEqual(resolved.lastPathComponent, "python")
        XCTAssertTrue(resolved.path.contains(".venv/bin/python"))
    }

    func testPythonExecutableFallsBackToSystemPython() {
        let inference = URL(fileURLWithPath: "/tmp/no-venv-here")
        let resolved = InferenceDirectoryResolver.pythonExecutable(in: inference)
        XCTAssertEqual(resolved.path, "/usr/bin/python3")
    }
}

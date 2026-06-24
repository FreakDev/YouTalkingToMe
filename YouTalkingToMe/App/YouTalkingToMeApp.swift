import AppKit
import SwiftUI

@main
struct YouTalkingToMeApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate

    var body: some Scene {
        Settings {
            EmptyView()
        }
    }
}

final class AppDelegate: NSObject, NSApplicationDelegate {
    private var menubarController: MenubarController?

    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.accessory)
        AppLogger.info("You Talking To Me launched — logs at \(AppLogger.logFileURL.path)")

        let settingsStore = SettingsStore()
        let permissionsManager = PermissionsManager()
        let inferenceClient = InferenceClient()
        let modelManager = ModelManager(inferenceClient: inferenceClient)
        let pipeline = PipelineCoordinator(inferenceClient: inferenceClient, settingsStore: settingsStore)

        menubarController = MenubarController(
            settingsStore: settingsStore,
            permissionsManager: permissionsManager,
            modelManager: modelManager,
            pipeline: pipeline,
            inferenceClient: inferenceClient
        )
        menubarController?.bootstrap()
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
        false
    }
}

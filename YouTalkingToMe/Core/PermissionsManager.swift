import AppKit
import ApplicationServices
import AVFoundation
import Foundation
import IOKit

extension Notification.Name {
    static let retryHotkeySetup = Notification.Name("YouTalkingToMe.retryHotkeySetup")
}

final class PermissionsManager: ObservableObject {
    @Published var microphoneGranted = false
    @Published var accessibilityGranted = false
    @Published var inputMonitoringGranted = false
    @Published var hotkeyOperational = false
    @Published var restartRequired = false

    private var activeObserver: NSObjectProtocol?

    init() {
        activeObserver = NotificationCenter.default.addObserver(
            forName: NSApplication.didBecomeActiveNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.4) {
                self?.refresh()
            }
        }
    }

    deinit {
        if let activeObserver {
            NotificationCenter.default.removeObserver(activeObserver)
        }
    }

    func refresh() {
        setIfChanged(\.microphoneGranted, checkMicrophonePermission())
        setIfChanged(\.accessibilityGranted, AXIsProcessTrusted())

        let listenGranted = checkInputMonitoringPermission()
        setIfChanged(\.inputMonitoringGranted, listenGranted)

        let needsRestart = !listenGranted && !hotkeyOperational && microphoneGranted && accessibilityGranted
        setIfChanged(\.restartRequired, needsRestart)
    }

    func setHotkeyOperational(_ operational: Bool) {
        setIfChanged(\.hotkeyOperational, operational)
        if operational {
            setIfChanged(\.inputMonitoringGranted, true)
            setIfChanged(\.restartRequired, false)
        }
    }

    var allGranted: Bool {
        microphoneGranted && accessibilityGranted && (inputMonitoringGranted || hotkeyOperational)
    }

    func requestMicrophone() {
        if #available(macOS 14.0, *) {
            AVAudioApplication.requestRecordPermission { [weak self] _ in
                DispatchQueue.main.async {
                    self?.refresh()
                }
            }
        } else {
            AVCaptureDevice.requestAccess(for: .audio) { [weak self] _ in
                DispatchQueue.main.async {
                    self?.refresh()
                }
            }
        }
    }

    func requestAccessibility() {
        let options = [kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String: true] as CFDictionary
        AXIsProcessTrustedWithOptions(options)
        scheduleRefresh()
    }

    func openAccessibilitySettings() {
        openSettings(url: "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility")
    }

    func openInputMonitoringSettings() {
        openSettings(url: "x-apple.systempreferences:com.apple.preference.security?Privacy_ListenEvent")
    }

    func openMicrophoneSettings() {
        openSettings(url: "x-apple.systempreferences:com.apple.preference.security?Privacy_Microphone")
    }

    func requestInputMonitoring() {
        NSApp.activate(ignoringOtherApps: true)

        if #available(macOS 10.15, *) {
            _ = IOHIDRequestAccess(kIOHIDRequestTypeListenEvent)

            if !CGPreflightListenEventAccess() {
                _ = CGRequestListenEventAccess()
            }

            refresh()

            if !checkInputMonitoringPermission() {
                openInputMonitoringSettings()
            }
        }

        NotificationCenter.default.post(name: .retryHotkeySetup, object: nil)
        scheduleRefresh()
    }

    private func scheduleRefresh() {
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) { [weak self] in
            self?.refresh()
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + 2.0) { [weak self] in
            self?.refresh()
        }
    }

    private func checkMicrophonePermission() -> Bool {
        if AVCaptureDevice.authorizationStatus(for: .audio) == .authorized {
            return true
        }

        if #available(macOS 14.0, *) {
            return AVAudioApplication.shared.recordPermission == .granted
        }

        return false
    }

    private func checkInputMonitoringPermission() -> Bool {
        if #available(macOS 10.15, *) {
            if IOHIDCheckAccess(kIOHIDRequestTypeListenEvent) == kIOHIDAccessTypeGranted {
                return true
            }
            return CGPreflightListenEventAccess()
        }
        return true
    }

    private func setIfChanged(_ keyPath: ReferenceWritableKeyPath<PermissionsManager, Bool>, _ newValue: Bool) {
        if self[keyPath: keyPath] != newValue {
            self[keyPath: keyPath] = newValue
        }
    }

    private func openSettings(url: String) {
        guard let settingsURL = URL(string: url) else { return }
        NSWorkspace.shared.open(settingsURL)
    }
}

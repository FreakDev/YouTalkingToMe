import AppKit
import SwiftUI

final class OverlayPanelController {
    private var panel: NSPanel?
    private var hostingView: NSHostingView<OverlayView>?

    func show(state: OverlayState) {
        if panel == nil {
            let content = OverlayView(state: state)
            let hosting = NSHostingView(rootView: content)
            hostingView = hosting

            let panel = NSPanel(
                contentRect: NSRect(x: 0, y: 0, width: 320, height: 56),
                styleMask: [.nonactivatingPanel, .fullSizeContentView],
                backing: .buffered,
                defer: false
            )
            panel.isOpaque = false
            panel.backgroundColor = .clear
            panel.hasShadow = false
            panel.level = .floating
            panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
            panel.hidesOnDeactivate = false
            panel.isReleasedWhenClosed = false
            panel.contentView = hosting
            self.panel = panel
        }

        if let hostingView {
            hostingView.rootView = OverlayView(state: state)
            resizeToFitContent(for: state)
        }

        positionPanel()
        panel?.orderFrontRegardless()

        if state == .hidden {
            panel?.orderOut(nil)
        }
    }

    private func resizeToFitContent(for state: OverlayState) {
        guard let hostingView, let panel else { return }

        hostingView.invalidateIntrinsicContentSize()
        hostingView.layoutSubtreeIfNeeded()

        let fittingSize = hostingView.fittingSize
        let width: CGFloat
        let height: CGFloat

        switch state {
        case .error:
            width = min(max(fittingSize.width, 200), 460)
            height = max(fittingSize.height, 52)
        default:
            width = max(fittingSize.width, 160)
            height = max(fittingSize.height, 44)
        }

        panel.setContentSize(NSSize(width: width, height: height))
    }

    private func positionPanel() {
        guard let panel, let screen = NSScreen.main else { return }
        let frame = screen.visibleFrame
        let panelSize = panel.frame.size
        let x = frame.midX - panelSize.width / 2
        let y = frame.minY + 72
        panel.setFrameOrigin(NSPoint(x: x, y: y))
    }
}

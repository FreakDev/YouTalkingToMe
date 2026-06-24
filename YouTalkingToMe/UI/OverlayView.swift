import SwiftUI

struct OverlayView: View {
    let state: OverlayState

    var body: some View {
        Group {
            switch state {
            case .hidden:
                EmptyView()
            case .listening:
                pillContent(title: "Écoute...", showWaveform: true)
            case .processing:
                pillContent(title: "Traitement...", showWaveform: false)
            case .error(let message):
                errorContent(message: message)
            }
        }
    }

    @ViewBuilder
    private func pillContent(title: String, showWaveform: Bool) -> some View {
        HStack(spacing: 12) {
            if showWaveform {
                WaveformView()
                    .frame(width: 48, height: 20)
            } else {
                ProgressView()
                    .controlSize(.small)
            }

            Text(title)
                .font(.system(size: 14, weight: .medium))
                .foregroundStyle(.white)
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 12)
        .background(
            Capsule()
                .fill(Color.black.opacity(0.82))
        )
        .shadow(color: .black.opacity(0.25), radius: 12, y: 4)
    }

    @ViewBuilder
    private func errorContent(message: String) -> some View {
        HStack(alignment: .top, spacing: 10) {
            Image(systemName: "exclamationmark.triangle.fill")
                .font(.system(size: 16, weight: .semibold))
                .foregroundStyle(.white)
                .padding(.top, 2)

            Text(message)
                .font(.system(size: 13, weight: .medium))
                .foregroundStyle(.white)
                .multilineTextAlignment(.leading)
                .fixedSize(horizontal: false, vertical: true)
        }
        .frame(maxWidth: 420, alignment: .leading)
        .padding(.horizontal, 18)
        .padding(.vertical, 14)
        .background(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .fill(Color.red.opacity(0.92))
        )
        .shadow(color: .black.opacity(0.25), radius: 12, y: 4)
    }
}

struct WaveformView: View {
    var body: some View {
        TimelineView(.animation(minimumInterval: 0.12)) { timeline in
            let seed = timeline.date.timeIntervalSinceReferenceDate
            HStack(spacing: 3) {
                ForEach(0..<5, id: \.self) { index in
                    let level = 0.2 + abs(sin(seed * 4.0 + Double(index) * 1.2)) * 0.8
                    RoundedRectangle(cornerRadius: 2)
                        .fill(Color.white)
                        .frame(width: 4, height: 4 + level * 14)
                }
            }
        }
    }
}

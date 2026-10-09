import AppKit
import SwiftUI

/// Animated "now playing" equalizer bars.
struct EqualizerBars: View {
    var isAnimating: Bool
    var barCount: Int = 3
    var tint: Color = .white

    var body: some View {
        TimelineView(.animation(minimumInterval: 1.0 / 15.0, paused: !isAnimating)) { context in
            let t = context.date.timeIntervalSinceReferenceDate
            HStack(alignment: .center, spacing: 2) {
                ForEach(0..<barCount, id: \.self) { index in
                    Capsule()
                        .fill(tint)
                        .frame(width: 2.5, height: barHeight(index, t))
                }
            }
            .frame(height: 15)
        }
    }

    private func barHeight(_ index: Int, _ t: TimeInterval) -> CGFloat {
        guard isAnimating else { return 3 }
        let phase = Double(index) * 1.1
        let wave = (sin(t * 6.5 + phase) + 1) / 2
        return 4 + CGFloat(wave) * 11
    }
}

/// Album art with a graceful music-note placeholder.
struct ArtworkView: View {
    var image: NSImage?
    var size: CGFloat
    var cornerRadius: CGFloat = 10

    var body: some View {
        Group {
            if let image {
                Image(nsImage: image)
                    .resizable()
                    .aspectRatio(contentMode: .fill)
            } else {
                ZStack {
                    LinearGradient(
                        colors: [Color(white: 0.22), Color(white: 0.12)],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    )
                    Image(systemName: "music.note")
                        .font(.system(size: size * 0.34, weight: .medium))
                        .foregroundStyle(.white.opacity(0.35))
                }
            }
        }
        .frame(width: size, height: size)
        .clipShape(RoundedRectangle(cornerRadius: cornerRadius, style: .continuous))
    }
}

/// Circular transport button.
struct ControlButton: View {
    var systemName: String
    var size: CGFloat = 30
    var iconScale: CGFloat = 0.46
    var isActive: Bool = false
    var action: () -> Void

    var body: some View {
        Button(action: action) {
            Image(systemName: systemName)
                .font(.system(size: size * iconScale, weight: .semibold))
                .foregroundStyle(isActive ? Color.black : Color.white)
                .frame(width: size, height: size)
                .background(
                    Circle().fill(isActive ? Color.white : Color.white.opacity(0.12))
                )
        }
        .buttonStyle(.plain)
    }
}

/// A compact glass "chip" used for status readouts.
struct StatusChip: View {
    var systemName: String
    var text: String
    var tint: Color = .white.opacity(0.85)

    var body: some View {
        HStack(spacing: 4) {
            Image(systemName: systemName)
                .font(.system(size: 10, weight: .semibold))
            Text(text)
                .font(.system(size: 11, weight: .medium, design: .rounded))
        }
        .foregroundStyle(tint)
        .padding(.horizontal, 8)
        .padding(.vertical, 4)
        .background(Capsule().fill(Color.white.opacity(0.1)))
    }
}

/// Thin progress track that reflects live playback position.
struct ProgressTrack: View {
    var progress: Double
    var height: CGFloat = 5
    var onScrub: ((Double) -> Void)? = nil

    @State private var dragValue: Double?

    var body: some View {
        GeometryReader { geo in
            let width = geo.size.width
            let clamped = min(max(dragValue ?? progress, 0), 1)
            ZStack(alignment: .leading) {
                Capsule().fill(Color.white.opacity(0.16))
                Capsule()
                    .fill(Color.white.opacity(0.9))
                    .frame(width: max(2, width * clamped))
            }
            .frame(height: height)
            .contentShape(Rectangle())
            .gesture(
                DragGesture(minimumDistance: 0)
                    .onChanged { value in
                        dragValue = min(max(value.location.x / width, 0), 1)
                    }
                    .onEnded { value in
                        let final = min(max(value.location.x / width, 0), 1)
                        dragValue = nil
                        onScrub?(final)
                    }
            )
        }
        .frame(height: height)
    }
}

/// A draggable level track (used for volume) that writes continuously while
/// dragging. Custom-drawn so it matches the panel instead of the system accent.
struct LevelTrack: View {
    @Binding var value: Double
    var height: CGFloat = 5
    var minFill: CGFloat = 2

    var body: some View {
        GeometryReader { geo in
            let width = geo.size.width
            let clamped = min(max(value, 0), 1)
            ZStack(alignment: .leading) {
                Capsule().fill(Color.white.opacity(0.16))
                Capsule()
                    .fill(Color.white.opacity(0.9))
                    .frame(width: max(minFill, width * clamped))
            }
            .frame(height: height)
            .contentShape(Rectangle())
            .gesture(
                DragGesture(minimumDistance: 0)
                    .onChanged { gesture in
                        value = min(max(gesture.location.x / width, 0), 1)
                    }
            )
        }
        .frame(height: height)
    }
}

extension Double {
    var timeString: String {
        guard isFinite, self >= 0 else { return "0:00" }
        let total = Int(self.rounded())
        return String(format: "%d:%02d", total / 60, total % 60)
    }
}

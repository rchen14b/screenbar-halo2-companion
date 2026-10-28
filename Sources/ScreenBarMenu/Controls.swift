import SwiftUI

extension Color {
    /// Apple Home's yellow, the dashboard's active colour.
    static let homeActive = Color(red: 1, green: 0.8, blue: 0)
    /// Glyphs on white "on" discs.
    static let activeGlyph = Color(red: 1, green: 0.62, blue: 0.04)
}

/// A round toggle with a caption: glass when off, a white disc with an orange glyph when on.
struct RoundControl: View {
    let title: String
    let symbol: String
    let isOn: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            VStack(spacing: 6) {
                Image(systemName: symbol)
                    .font(.system(size: 19, weight: .medium))
                    .foregroundStyle(isOn ? Color.activeGlyph : Color.primary)
                    .frame(width: 52, height: 52)
                    .background {
                        if isOn { Circle().fill(.white).shadow(color: .black.opacity(0.12), radius: 6, y: 2) }
                    }
                    .glassEffect(isOn ? .identity : .regular.interactive(), in: .circle)
                Text(title)
                    .font(.system(size: 11))
                    .foregroundStyle(isOn ? .primary : .secondary)
            }
            .frame(maxWidth: .infinity)
            .contentShape(.rect)  // the whole column clicks, not just the glyph
        }
        .buttonStyle(.plain)
        .animation(.easeOut(duration: 0.15), value: isOn)
        .help(title)
    }
}

/// A slider with end icons and a caption. It sends once, on release; while dragging, only the
/// caption follows the thumb.
struct ControlSlider: View {
    enum Track {
        case fill(Color)
        case gradient([Color])
    }

    let title: String
    let value: Double
    let range: ClosedRange<Double>
    let step: Double
    let track: Track
    let leading: String
    let trailing: String
    var dimmed = false
    var format: (Double) -> String
    let onCommit: (Double) -> Void

    @State private var dragValue: Double?

    var body: some View {
        VStack(spacing: 2) {
            HStack(spacing: 10) {
                Image(systemName: leading).font(.system(size: 12)).foregroundStyle(.secondary).frame(width: 18)
                slider
                Image(systemName: trailing).font(.system(size: 15)).foregroundStyle(.secondary).frame(width: 18)
            }
            HStack {
                Text(title)
                Spacer()
                Text(format(dragValue ?? value)).fontWeight(.semibold).foregroundStyle(.primary).monospacedDigit()
            }
            .font(.system(size: 11))
            .foregroundStyle(.secondary)
            .padding(.horizontal, 28)
        }
        .opacity(dimmed && dragValue == nil ? 0.55 : 1)
    }

    private var slider: some View {
        GeometryReader { geometry in
            let thumb: CGFloat = 22
            let span = range.upperBound - range.lowerBound
            let fraction = span > 0 ? min(max(((dragValue ?? value) - range.lowerBound) / span, 0), 1) : 0
            ZStack(alignment: .leading) {
                trackView(width: geometry.size.width, fraction: fraction)
                    .frame(height: 6)
                    .clipShape(.capsule)
                Circle()
                    .fill(.white)
                    .frame(width: thumb, height: thumb)
                    .shadow(color: .black.opacity(0.28), radius: 2, y: 1)
                    .offset(x: fraction * (geometry.size.width - thumb))
            }
            .frame(maxHeight: .infinity)
            .contentShape(.rect)
            .gesture(
                DragGesture(minimumDistance: 0)
                    .onChanged { gesture in
                        let f = min(max((gesture.location.x - thumb / 2) / (geometry.size.width - thumb), 0), 1)
                        dragValue = range.lowerBound + ((f * span) / step).rounded() * step
                    }
                    .onEnded { _ in
                        if let dragValue { onCommit(dragValue) }
                        dragValue = nil
                    }
            )
        }
        .frame(height: 28)
    }

    @ViewBuilder
    private func trackView(width: CGFloat, fraction: CGFloat) -> some View {
        switch track {
        case .fill(let color):
            ZStack(alignment: .leading) {
                Rectangle().fill(.quaternary)
                Rectangle().fill(color).frame(width: width * fraction)
            }
        case .gradient(let colors):
            LinearGradient(colors: colors, startPoint: .leading, endPoint: .trailing)
        }
    }
}

/// The wide button at the bottom: icon, label, value and a chevron.
struct PillLabel: View {
    let title: String
    let value: String
    let symbol: String
    let isOn: Bool

    var body: some View {
        HStack(spacing: 9) {
            Image(systemName: symbol)
                .font(.system(size: 14, weight: .medium))
                .foregroundStyle(isOn ? Color.white : Color.primary)
                .frame(width: 32, height: 32)
                .background(Circle().fill(isOn ? AnyShapeStyle(Color.homeActive) : AnyShapeStyle(.quaternary)))
            VStack(alignment: .leading, spacing: 1) {  // one line each, shrinking a little before wrapping
                Text(title).font(.system(size: 12, weight: .semibold))
                Text(value).font(.system(size: 11)).opacity(0.7)
            }
            .lineLimit(1)
            .minimumScaleFactor(0.8)
            Spacer(minLength: 0)
            Image(systemName: "chevron.right")
                .font(.system(size: 11, weight: .semibold))
                .opacity(0.45)
        }
        .foregroundStyle(isOn ? Color.black.opacity(0.85) : Color.primary)
        .padding(.leading, 6)
        .padding(.trailing, 12)
        .frame(height: 46)
        .background {
            if isOn { Capsule().fill(.white.opacity(0.92)) }
        }
        .glassEffect(isOn ? .identity : .regular.interactive(), in: .capsule)
        .contentShape(.capsule)
    }
}

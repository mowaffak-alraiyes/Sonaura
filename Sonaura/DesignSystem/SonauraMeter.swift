//
//  SonauraMeter.swift
//  Sonaura
//
//  The signature check-in moment: a needle sweep, not a spinner. Replaces the
//  generic progress indicators used during "Checking the photo…"-style waits
//  elsewhere in the app's category, with something that reads as a real
//  instrument taking a real reading. See docs/design-system.md §3.
//
import SwiftUI

/// An analog-style meter. `progress` is 0...1 and drives the needle from rest
/// (-58°) toward its settled reading (+26°); `isSweeping` plays the settle
/// animation. Purely decorative — it does not measure anything itself.
struct SonauraMeterView: View {
    var progress: Double
    var isSweeping: Bool = true

    private let restAngle: Double = -58
    private let maxAngle: Double = 34
    private let settleAngle: Double = 26

    private var needleAngle: Double {
        restAngle + (settleAngle - restAngle) * min(max(progress, 0), 1)
    }

    var body: some View {
        GeometryReader { geo in
            let width = geo.size.width
            let height = width * (130.0 / 220.0)
            let pivot = CGPoint(x: width / 2, y: height)
            let radius = width * 0.45

            ZStack {
                Path { path in
                    path.addArc(
                        center: pivot,
                        radius: radius,
                        startAngle: .degrees(180),
                        endAngle: .degrees(0),
                        clockwise: true
                    )
                }
                .stroke(SonauraColor.border, lineWidth: 1.5)

                ForEach(0..<7) { tick in
                    let angle = Angle.degrees(-90 - 58 + Double(tick) * (116.0 / 6.0))
                    tickMark(at: angle, pivot: pivot, radius: radius)
                }

                Circle()
                    .fill(SonauraColor.accent)
                    .frame(width: 8, height: 8)
                    .position(pivot)

                Rectangle()
                    .fill(SonauraColor.accent)
                    .frame(width: 3, height: radius * 0.86)
                    .clipShape(RoundedRectangle(cornerRadius: 1.5))
                    .offset(y: -radius * 0.43)
                    .rotationEffect(.degrees(needleAngle), anchor: .bottom)
                    .position(pivot)
                    .animation(
                        isSweeping ? .interpolatingSpring(stiffness: 55, damping: 9) : .default,
                        value: needleAngle
                    )
            }
        }
        .aspectRatio(220.0 / 130.0, contentMode: .fit)
        .accessibilityHidden(true)
    }

    private func tickMark(at angle: Angle, pivot: CGPoint, radius: CGFloat) -> some View {
        // Resolve the trig in Double, then convert once. Mixing `angle.radians`
        // (Double) directly into CGPoint arithmetic (CGFloat) makes `cos`/`sin`
        // ambiguous between the Double and CGFloat overloads.
        let dx = CGFloat(cos(angle.radians))
        let dy = CGFloat(sin(angle.radians))
        let inner = CGPoint(
            x: pivot.x + dx * radius * 0.86,
            y: pivot.y + dy * radius * 0.86
        )
        let outer = CGPoint(
            x: pivot.x + dx * radius,
            y: pivot.y + dy * radius
        )
        return Path { path in
            path.move(to: inner)
            path.addLine(to: outer)
        }
        .stroke(SonauraColor.muted, lineWidth: 1.5)
    }
}

/// A soft, hand-tuned trend line with a glowing current point — replaces the
/// default `Charts` grid look for the home/trend surface. `points` should
/// already be normalized to 0...1 on both axes by the caller; this view only
/// draws.
struct SonauraTrendLine: View {
    var points: [CGPoint]

    var body: some View {
        GeometryReader { geo in
            let size = geo.size
            if points.count >= 2 {
                let scaled = points.map {
                    CGPoint(x: $0.x * size.width, y: (1 - $0.y) * size.height)
                }
                ZStack {
                    smoothPath(through: scaled)
                        .stroke(
                            // The Embers ramp itself, left to right: the
                            // past recedes into indigo, the present arrives
                            // at rose.
                            LinearGradient(
                                colors: [
                                    SonauraColor.steady.opacity(0.55),
                                    SonauraColor.ember,
                                    SonauraColor.accent
                                ],
                                startPoint: .leading,
                                endPoint: .trailing
                            ),
                            style: StrokeStyle(lineWidth: 3, lineCap: .round, lineJoin: .round)
                        )
                    if let last = scaled.last {
                        Circle()
                            .fill(SonauraColor.accent)
                            .frame(width: 9, height: 9)
                            .shadow(color: SonauraColor.accent.opacity(0.6), radius: 6)
                            .position(last)
                        Circle()
                            .strokeBorder(SonauraColor.accent.opacity(0.5), lineWidth: 1.5)
                            .frame(width: 16, height: 16)
                            .position(last)
                    }
                }
            } else {
                Text("A trend needs at least two check-ins.")
                    .font(SonauraFont.body(.caption))
                    .foregroundStyle(SonauraColor.muted)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }
    }

    /// A Catmull-Rom-ish smoothing pass. Deliberately soft rather than a
    /// straight polyline — see docs/design-system.md: "Softness in the line,
    /// precision in the point."
    private func smoothPath(through pts: [CGPoint]) -> Path {
        var path = Path()
        guard let first = pts.first else { return path }
        path.move(to: first)
        guard pts.count > 2 else {
            if let last = pts.last { path.addLine(to: last) }
            return path
        }
        for index in 1..<pts.count {
            let previous = pts[index - 1]
            let current = pts[index]
            let midX = (previous.x + current.x) / 2
            path.addCurve(
                to: current,
                control1: CGPoint(x: midX, y: previous.y),
                control2: CGPoint(x: midX, y: current.y)
            )
        }
        return path
    }
}

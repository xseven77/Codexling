import SwiftUI

/// Canvas 文字流光。位移由时间轴的绝对时间决定，View 重建时不会重置动画进度。
struct ActivityShimmerText: View {
    let text: String
    var font: Font = .system(size: 8.5)
    var base: Color = .codexMuted
    var highlight: Color = .white
    var isAnimated = true

    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        // 透明文字负责参与布局并提供精确的单行文字尺寸，Canvas 只负责绘制。
        Text(text)
            .font(font)
            .lineLimit(1)
            .foregroundStyle(Color.clear)
            .overlay {
                TimelineView(
                    .animation(
                        minimumInterval: 1.0 / 30.0,
                        paused: !isAnimated || reduceMotion
                    )
                ) { timeline in
                    shimmerCanvas(at: timeline.date.timeIntervalSinceReferenceDate)
                }
            }
            .accessibilityLabel(text)
    }

    private func shimmerCanvas(at time: TimeInterval) -> some View {
        Canvas { context, size in
            let bandWidth = max(24, size.width * 0.5)
            let offset = ActivityShimmerMotion.offset(
                canvasWidth: size.width,
                bandWidth: bandWidth,
                at: time,
                isAnimated: isAnimated && !reduceMotion
            )
            let origin = CGPoint.zero

            context.draw(
                Text(text).font(font).foregroundStyle(base),
                at: origin,
                anchor: .topLeading
            )

            if isAnimated {
                context.clipToLayer { layer in
                    let bandRect = CGRect(
                        x: offset,
                        y: 0,
                        width: bandWidth,
                        height: size.height
                    )
                    layer.fill(
                        Path(bandRect),
                        with: .linearGradient(
                            Gradient(colors: [.clear, .white, .white, .clear]),
                            startPoint: CGPoint(x: offset, y: 0),
                            endPoint: CGPoint(x: offset + bandWidth, y: 0)
                        )
                    )
                }

                context.draw(
                    Text(text).font(font).foregroundStyle(highlight),
                    at: origin,
                    anchor: .topLeading
                )
            }
        }
        .allowsHitTesting(false)
    }
}

enum ActivityShimmerMotion {
    /// 与原任务条一致，每 2.4 秒从文字左侧完整扫到右侧一次。
    static let duration: TimeInterval = 2.4

    static func offset(
        canvasWidth: CGFloat,
        bandWidth: CGFloat,
        at time: TimeInterval,
        isAnimated: Bool = true
    ) -> CGFloat {
        guard isAnimated else { return (canvasWidth - bandWidth) / 2 }
        let phase = time.truncatingRemainder(dividingBy: duration) / duration
        return -bandWidth + CGFloat(phase) * (canvasWidth + 2 * bandWidth)
    }
}

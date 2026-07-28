import SwiftUI

// MARK: - Reset coupon (timeline rail + grant message card)

private struct ResetCouponDisplayItem: Identifiable {
    let id: String
    let coupon: ResetCoupon
}

struct ResetCouponSummaryView: View {
    let coupons: [ResetCoupon]

    /// 临时预览空态；看完改回 `false` 并重新 `./rebuild_and_run.sh`。
    private static let forceEmptyForPreview = false

    private var displayCoupons: [ResetCoupon] {
        if Self.forceEmptyForPreview { return [] }
        return coupons
    }

    private var items: [ResetCouponDisplayItem] {
        displayCoupons.flatMap { coupon in
            (0..<coupon.count).map { copyIndex in
                ResetCouponDisplayItem(id: "\(coupon.id)-\(copyIndex)", coupon: coupon)
            }
        }
    }

    var body: some View {
        Group {
            if items.isEmpty {
                ResetCouponEmptyStateView()
            } else {
        ResetCouponFusionDeck(items: items)
            .fixedSize(horizontal: false, vertical: true)
            }
        }
    }
}

private struct ResetCouponEmptyStateView: View {
    @Environment(\.colorScheme) private var colorScheme

    private var isDark: Bool { colorScheme == .dark }

    var body: some View {
        HStack(spacing: 10) {
            ZStack {
                RoundedRectangle(cornerRadius: 9, style: .continuous)
                    .fill(Color.codexMist.opacity(isDark ? 0.35 : 0.55))
                    .frame(width: 34, height: 34)
                Image(systemName: "arrow.counterclockwise.circle")
                    .font(.system(size: 15, weight: .medium))
                    .foregroundStyle(Color.codexMuted.opacity(0.75))
            }

            VStack(alignment: .leading, spacing: 2) {
                Text("重置券 0 张")
                    .font(.system(size: 11, weight: .semibold))
                Text("当前没有可用重置券")
                    .font(.system(size: 9))
                    .foregroundStyle(Color.codexMuted)
            }

            Spacer(minLength: 0)
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 13)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            Color.codexCard.opacity(isDark ? 0.98 : 1),
            in: RoundedRectangle(cornerRadius: 14, style: .continuous)
        )
        .overlay {
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .stroke(Color.codexLine.opacity(isDark ? 0.42 : 0.78), lineWidth: 0.75)
        }
        .shadow(color: Color.black.opacity(isDark ? 0.1 : 0.04), radius: 10, x: 0, y: 4)
    }
}

private struct ResetCouponFusionDeck: View {
    let items: [ResetCouponDisplayItem]

    @State private var selectedIndex = 0

    private var sortedIndices: [Int] {
        items.indices.sorted { lhs, rhs in
            let left = ResetCouponDateParser.date(from: items[lhs].coupon.expiresAt) ?? .distantFuture
            let right = ResetCouponDateParser.date(from: items[rhs].coupon.expiresAt) ?? .distantFuture
            return left < right
        }
    }

    private var displayOrder: [Int] {
        sortedIndices
    }

    var body: some View {
        ResetCouponFusionCard(
            items: items,
            displayOrder: displayOrder,
            selectedIndex: selectedIndex,
            onSelect: { index in
                guard index >= 0, index < displayOrder.count else { return }
                selectedIndex = index
            },
            onNext: {
                guard displayOrder.count > 1 else { return }
                selectedIndex = (selectedIndex + 1) % displayOrder.count
            }
        )
        .accessibilityElement(children: .contain)
        .accessibilityLabel("重置券 \(items.count) 张，当前第 \(selectedIndex + 1) 张")
        .onChange(of: items.map(\.id)) { _, ids in
            if ids.isEmpty || selectedIndex >= ids.count {
                selectedIndex = 0
            }
        }
    }
}

private struct ResetCouponFusionCard: View {
    private static let cardSpace = "resetCouponFusionCard"

    let items: [ResetCouponDisplayItem]
    let displayOrder: [Int]
    let selectedIndex: Int
    let onSelect: (Int) -> Void
    let onNext: () -> Void

    @Environment(\.colorScheme) private var colorScheme
    @State private var ripples: [CodexMaterialWaveToken] = []

    private var selected: ResetCouponDisplayItem {
        items[displayOrder[selectedIndex]]
    }

    private var isDark: Bool { colorScheme == .dark }

    var body: some View {
        VStack(spacing: 0) {
            ResetCouponTimelineRail(
                items: items,
                displayOrder: displayOrder,
                selectedIndex: selectedIndex,
                isDark: isDark,
                onSelect: onSelect
            )

            Divider()
                .overlay(Color.codexLine.opacity(isDark ? 0.35 : 0.55))

            ResetCouponGrantMessageSection(
                coupon: selected.coupon,
                position: selectedIndex + 1,
                total: displayOrder.count,
                isDark: isDark,
                showsNext: displayOrder.count > 1,
                onNext: {
                    ripples.spawnWave(at: CGPoint(x: 120, y: 40))
                    onNext()
                }
            )
        }
        .background(
            Color.codexCard.opacity(isDark ? 0.98 : 1),
            in: RoundedRectangle(cornerRadius: 14, style: .continuous)
        )
        .overlay {
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .stroke(Color.codexLine.opacity(isDark ? 0.42 : 0.78), lineWidth: 0.75)
        }
        .shadow(color: Color.black.opacity(isDark ? 0.14 : 0.05), radius: 14, x: 0, y: 6)
        .shadow(color: Color.black.opacity(isDark ? 0.06 : 0.02), radius: 3, x: 0, y: 1)
        .overlay {
            CodexMaterialWaveLayer(ripples: $ripples)
                .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
        }
        .coordinateSpace(name: Self.cardSpace)
    }
}

private struct ResetCouponTimelineRail: View {
    let items: [ResetCouponDisplayItem]
    let displayOrder: [Int]
    let selectedIndex: Int
    let isDark: Bool
    let onSelect: (Int) -> Void

    private var timelineRange: (min: Date, max: Date) {
        ResetCouponDateParser.timelineRange(for: displayOrder.map { items[$0].coupon })
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(alignment: .firstTextBaseline) {
                Text("重置券有效期")
                    .font(.system(size: 10.5, weight: .semibold))
                Spacer(minLength: 8)
                Text("\(displayOrder.count) 张 · 按到期排序")
                    .font(.system(size: 9, weight: .medium))
                    .foregroundStyle(Color.codexMuted)
            }

            ResetCouponTimelineTrack(
                items: items,
                displayOrder: displayOrder,
                selectedIndex: selectedIndex,
                range: timelineRange,
                isDark: isDark,
                onSelect: onSelect
            )

            ResetCouponTimelineMetaGrid(coupon: items[displayOrder[selectedIndex]].coupon)
        }
        .padding(.horizontal, 14)
        .padding(.top, 11)
        .padding(.bottom, 10)
        .background(
            LinearGradient(
                colors: [
                    isDark ? Color.white.opacity(0.04) : Color(red: 0.98, green: 0.99, blue: 0.98),
                    Color.clear
                ],
                startPoint: .top,
                endPoint: .bottom
            )
        )
    }
}

private struct ResetCouponTimelineTrack: View {
    let items: [ResetCouponDisplayItem]
    let displayOrder: [Int]
    let selectedIndex: Int
    let range: (min: Date, max: Date)
    let isDark: Bool
    let onSelect: (Int) -> Void

    var body: some View {
        GeometryReader { geometry in
            let width = geometry.size.width
            ZStack(alignment: .leading) {
                Capsule(style: .continuous)
                    .fill(Color.codexTrack.opacity(isDark ? 0.85 : 1))
                    .frame(height: 3)
                    .frame(maxHeight: .infinity, alignment: .center)

                ForEach(Array(displayOrder.enumerated()), id: \.offset) { orderIndex, itemIndex in
                    let coupon = items[itemIndex].coupon
                    let fraction = ResetCouponDateParser.fraction(
                        of: ResetCouponDateParser.date(from: coupon.expiresAt) ?? range.max,
                        in: range
                    )
                    let x = width * fraction
                    let isSelected = orderIndex == selectedIndex

                    Button {
                        onSelect(orderIndex)
                    } label: {
                        ZStack {
                            if isSelected {
                                Circle()
                                    .fill(Color.codexGreen.opacity(0.22))
                                    .frame(width: 22, height: 22)
                            }
                            Circle()
                                .fill(isSelected ? Color.codexGreen : Color.codexLine.opacity(isDark ? 0.9 : 0.95))
                                .frame(width: isSelected ? 12 : 9, height: isSelected ? 12 : 9)
                                .overlay {
                                    Circle()
                                        .stroke(Color.codexCard, lineWidth: 2)
                                }
                                .shadow(
                                    color: isSelected ? Color.codexGreen.opacity(0.35) : Color.black.opacity(0.08),
                                    radius: isSelected ? 4 : 1,
                                    y: 1
                                )
                        }
                        .frame(width: 28, height: 28)
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .position(x: x, y: geometry.size.height / 2)
                    .accessibilityLabel("第 \(orderIndex + 1) 张，\(coupon.expiresAt) 到期")
                }
            }
        }
        .frame(height: 28)
        .padding(.horizontal, 2)
    }
}

private struct ResetCouponTimelineMetaGrid: View {
    let coupon: ResetCoupon

    var body: some View {
        LazyVGrid(
            columns: [GridItem(.flexible(), alignment: .leading), GridItem(.flexible(), alignment: .leading)],
            alignment: .leading,
            spacing: 3
        ) {
            metaCell(title: "获得", value: ResetCouponDateParser.shortDate(from: coupon.grantedAt) ?? "—")
            metaCell(title: "到期", value: ResetCouponDateParser.shortDate(from: coupon.expiresAt) ?? coupon.expiresAt)
            metaCell(title: "类型", value: ResetCouponDateParser.resetTypeLabel(coupon.resetType))
            metaCell(title: "状态", value: coupon.status ?? coupon.source)
        }
    }

    private func metaCell(title: String, value: String) -> some View {
        HStack(spacing: 4) {
            Text(title)
                .foregroundStyle(Color.codexMuted)
            Text(value)
                .foregroundStyle(Color.primary.opacity(0.88))
                .fontWeight(.semibold)
                .lineLimit(1)
                .minimumScaleFactor(0.85)
        }
        .font(.system(size: 8.5, weight: .medium))
    }
}

private struct ResetCouponGrantMessageSection: View {
    let coupon: ResetCoupon
    let position: Int
    let total: Int
    let isDark: Bool
    let showsNext: Bool
    let onNext: () -> Void

    var body: some View {
        VStack(spacing: 0) {
            HStack(alignment: .center, spacing: 9) {
                ResetCouponGrantAvatar(urlString: coupon.profileImageURL, isDark: isDark)

                VStack(alignment: .leading, spacing: 1) {
                    Text(coupon.profileUserID ?? coupon.source)
                        .font(.system(size: 10, weight: .semibold))
                        .lineLimit(1)
                    Text("授予 · \(ResetCouponDateParser.shortDate(from: coupon.grantedAt) ?? "—")")
                        .font(.system(size: 8.5, weight: .medium))
                        .foregroundStyle(Color.codexMuted)
                        .lineLimit(1)
                }

                Spacer(minLength: 4)

                Text("\(position)/\(total)")
                    .font(.system(size: 8, weight: .bold))
                    .monospacedDigit()
                    .foregroundStyle(Color.codexMuted)
            }
            .padding(.horizontal, 14)
            .padding(.top, 10)

            VStack(alignment: .leading, spacing: 4) {
                Text(coupon.title ?? coupon.name)
                    .font(.system(size: 13, weight: .bold))
                    .foregroundStyle(Color.primary.opacity(0.92))
                    .lineLimit(1)

                if let description = coupon.description, !description.isEmpty {
                    Text(description)
                        .font(.system(size: 9.5, weight: .medium))
                        .foregroundStyle(Color.codexMuted)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, 14)
            .padding(.top, 6)
            .padding(.bottom, 8)

            HStack(alignment: .center, spacing: 8) {
                Text("\(coupon.expiresAt) 到期")
                    .font(.system(size: 9, weight: .medium))
                    .foregroundStyle(Color.codexMuted)
                    .lineLimit(1)
                    .minimumScaleFactor(0.85)

                Spacer(minLength: 0)

                if showsNext {
                    HStack(spacing: 6) {
                        ResetCouponPageDots(count: total, index: position - 1)
                        Button(action: onNext) {
                            Text("下一张")
                                .font(.system(size: 9, weight: .semibold))
                                .foregroundStyle(Color.codexGreen)
                                .padding(.horizontal, 9)
                                .padding(.vertical, 4)
                                .background(
                                    Color.codexGreen.opacity(isDark ? 0.14 : 0.09),
                                    in: RoundedRectangle(cornerRadius: 8, style: .continuous)
                                )
                                .overlay {
                                    RoundedRectangle(cornerRadius: 8, style: .continuous)
                                        .stroke(Color.codexGreen.opacity(0.22), lineWidth: 0.6)
                                }
                        }
                        .buttonStyle(.plain)
                        .accessibilityLabel("下一张重置券")
                    }
                }
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 9)
            .background(Color.codexMist.opacity(isDark ? 0.22 : 0.38))
        }
    }
}

private struct ResetCouponGrantAvatar: View {
    let urlString: String?
    let isDark: Bool

    var body: some View {
        Group {
            if let urlString, let url = URL(string: urlString) {
                AsyncImage(url: url) { phase in
                    switch phase {
                    case .success(let image):
                        image.resizable().scaledToFill()
                    default:
                        fallbackIcon
                    }
                }
            } else {
                fallbackIcon
            }
        }
        .frame(width: 30, height: 30)
        .clipShape(RoundedRectangle(cornerRadius: 9, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 9, style: .continuous)
                .stroke(Color.codexLine.opacity(0.45), lineWidth: 0.6)
        }
    }

    private var fallbackIcon: some View {
        ZStack {
            Color.codexGreen.opacity(isDark ? 0.16 : 0.1)
            Image(systemName: "arrow.counterclockwise")
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(Color.codexGreen)
        }
    }
}

private struct ResetCouponPageDots: View {
    let count: Int
    let index: Int

    var body: some View {
        HStack(spacing: 4) {
            ForEach(0..<count, id: \.self) { dotIndex in
                Capsule(style: .continuous)
                    .fill(dotIndex == index ? Color.codexGreen : Color.codexLine.opacity(0.85))
                    .frame(width: dotIndex == index ? 11 : 4, height: 4)
            }
        }
        .accessibilityHidden(true)
    }
}

private enum ResetCouponDateParser {
    private static let displayFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = "yyyy-MM-dd HH:mm:ss"
        return formatter
    }()

    private static let shortDisplayFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "zh_CN")
        formatter.dateFormat = "M月d日"
        return formatter
    }()

    static func date(from value: String?) -> Date? {
        guard let value, !value.isEmpty else { return nil }
        if let date = displayFormatter.date(from: value) { return date }
        if let date = ISO8601DateFormatter().date(from: value) { return date }
        return nil
    }

    static func shortDate(from value: String?) -> String? {
        guard let date = date(from: value) else { return nil }
        return shortDisplayFormatter.string(from: date)
    }

    static func timelineRange(for coupons: [ResetCoupon]) -> (min: Date, max: Date) {
        var dates: [Date] = []
        for coupon in coupons {
            if let granted = date(from: coupon.grantedAt) { dates.append(granted) }
            if let expires = date(from: coupon.expiresAt) { dates.append(expires) }
        }
        guard let min = dates.min(), let max = dates.max(), min < max else {
            let now = Date()
            return (now, now.addingTimeInterval(86400))
        }
        return (min, max)
    }

    static func fraction(of date: Date, in range: (min: Date, max: Date)) -> CGFloat {
        let span = range.max.timeIntervalSince(range.min)
        guard span > 0 else { return 0.5 }
        let raw = date.timeIntervalSince(range.min) / span
        return CGFloat(min(max(raw, 0.04), 0.96))
    }

    static func resetTypeLabel(_ value: String?) -> String {
        guard let value, !value.isEmpty else { return "重置券" }
        if value == "codex_rate_limits" { return "重置 Codex 速率额度" }
        return value
    }
}

#if DEBUG
#Preview("重置券 · 空态") {
    ResetCouponSummaryView(coupons: [])
        .padding(14)
        .frame(width: 380)
        .background(Color.codexMist.opacity(0.3))
}

#Preview("重置券 · M1") {
    ResetCouponSummaryView(coupons: CodexUsageSnapshot.preview.resetCoupons)
        .padding(14)
        .frame(width: 380)
        .background(Color.codexMist.opacity(0.3))
}
#endif

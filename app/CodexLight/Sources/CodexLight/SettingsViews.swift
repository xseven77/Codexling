import SwiftUI

struct SettingsView: View {
    @Bindable var settings: AppSettingsStore
    let layout: UsagePanelLayout
    let onClose: () -> Void

    private var titleLeadingPadding: CGFloat {
        layout == .window ? 62 : 0
    }

    private var titleVerticalOffset: CGFloat {
        layout == .window ? -10 : 0
    }

    var body: some View {
        VStack(spacing: 0) {
            header
            ScrollView {
                VStack(alignment: .leading, spacing: 18) {
                    themeSection
                    refreshSection
                }
                .padding(16)
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            Spacer(minLength: 0)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        .foregroundStyle(Color.codexInk)
    }

    private var header: some View {
        HStack(spacing: 14) {
            VStack(alignment: .leading, spacing: 3) {
                Text("设置")
                    .font(.system(size: 15, weight: .semibold))
                    .padding(.leading, titleLeadingPadding)
                    .offset(y: titleVerticalOffset)
                Text("主题与自动刷新")
                    .font(.system(size: 12))
                    .foregroundStyle(Color.codexMuted)
            }

            Spacer(minLength: 8)

            IconButton(systemName: "xmark", title: "关闭设置", action: onClose)
        }
        .padding(EdgeInsets(top: 16, leading: 16, bottom: 16, trailing: 16))
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(CodexChromeBackground(intensity: .header))
        .overlay(alignment: .bottom) {
            Rectangle()
                .fill(Color.codexLine.opacity(0.74))
                .frame(height: 1)
        }
        .fixedSize(horizontal: false, vertical: true)
    }

    private var themeSection: some View {
        SettingsSection(title: "主题", subtitle: "跟随系统，或固定浅色 / 深色") {
            VStack(spacing: 8) {
                ForEach(AppThemePreference.allCases) { option in
                    SettingsOptionRow(
                        title: option.title,
                        systemName: option.symbolName,
                        isSelected: settings.theme == option
                    ) {
                        settings.theme = option
                    }
                }
            }
        }
    }

    private var refreshSection: some View {
        SettingsSection(title: "自动刷新", subtitle: "登录后按设定间隔自动拉取额度") {
            VStack(spacing: 8) {
                ForEach(AutoRefreshInterval.allCases) { option in
                    SettingsOptionRow(
                        title: option.title,
                        systemName: option == .off ? "pause.circle" : "clock",
                        isSelected: settings.autoRefreshInterval == option
                    ) {
                        settings.autoRefreshInterval = option
                    }
                }
            }
        }
    }
}

private struct SettingsSection<Content: View>: View {
    let title: String
    let subtitle: String
    @ViewBuilder let content: Content

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            VStack(alignment: .leading, spacing: 3) {
                Text(title)
                    .font(.system(size: 13, weight: .semibold))
                Text(subtitle)
                    .font(.system(size: 12))
                    .foregroundStyle(Color.codexMuted)
            }

            content
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

private struct SettingsOptionRow: View {
    let title: String
    let systemName: String
    let isSelected: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 10) {
                Image(systemName: systemName)
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(Color.codexMuted)
                    .frame(width: 18)

                Text(title)
                    .font(.system(size: 13, weight: .medium))
                    .foregroundStyle(Color.codexInk)

                Spacer(minLength: 8)

                if isSelected {
                    Image(systemName: "checkmark")
                        .font(.system(size: 12, weight: .bold))
                        .foregroundStyle(Color.codexPrimary)
                }
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 11)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .liquidGlassSurface(
            cornerRadius: 10,
            tint: isSelected ? Color.codexPrimary.opacity(0.06) : Color.codexGlassTint,
            shadowOpacity: 0.035
        )
    }
}

import SwiftUI

struct SettingsView: View {
    @Bindable var settings: AppSettingsStore
    @Bindable var updater: AppUpdateController
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
            ViewThatFits(in: .vertical) {
                settingsContent
                    .fixedSize(horizontal: false, vertical: true)

                ScrollView {
                    settingsContent
                }
                .scrollIndicators(.hidden)
                .background(ScrollIndicatorHider())
            }
        }
        .frame(maxWidth: .infinity, alignment: .top)
        .foregroundStyle(Color.codexInk)
    }

    private var settingsContent: some View {
        VStack(alignment: .leading, spacing: 18) {
            updateSection
            themeSection
            refreshSection
            statusBarDivider
            petSection
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var header: some View {
        HStack(spacing: 14) {
            VStack(alignment: .leading, spacing: 3) {
                Text("设置")
                    .font(.system(size: 15, weight: .semibold))
                    .padding(.leading, titleLeadingPadding)
                    .offset(y: titleVerticalOffset)
                Text("更新、主题、状态与 Pets、自动刷新")
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

    private var updateSection: some View {
        SettingsSection(title: "软件更新", subtitle: "从 GitHub Releases 检查并安装最新版本") {
            VStack(alignment: .leading, spacing: 12) {
                VStack(alignment: .leading, spacing: 4) {
                    Text("当前版本 \(updater.currentVersion)（\(updater.currentBuild)）")
                        .font(.system(size: 13, weight: .semibold))
                    Text(updater.statusText)
                        .font(.system(size: 12))
                        .foregroundStyle(statusColor)
                        .fixedSize(horizontal: false, vertical: true)
                }

                if case .downloading = updater.phase {
                    ProgressView(value: updater.downloadProgress)
                        .progressViewStyle(.linear)
                        .tint(Color.codexPrimary)
                }

                if case .available = updater.phase, let release = updater.latestRelease {
                    Text(release.name)
                        .font(.system(size: 12, weight: .medium))
                        .foregroundStyle(Color.codexMuted)
                    if !release.releaseNotes.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                        Text(release.releaseNotes)
                            .font(.system(size: 12))
                            .foregroundStyle(Color.codexMuted)
                            .lineLimit(4)
                    }
                }

                HStack(spacing: 8) {
                    Button(action: primaryUpdateAction) {
                        Text(primaryUpdateTitle)
                            .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(PrimaryButtonStyle())
                    .disabled(updater.phase.isBusy)

                    Button(action: updater.openReleasesPage) {
                        Image(systemName: "safari")
                            .font(.system(size: 14, weight: .medium))
                            .frame(width: 36, height: 36)
                    }
                    .buttonStyle(IconButtonStyle())
                    .help("打开 Releases 页面")
                    .accessibilityLabel("打开 Releases 页面")
                }
            }
            .padding(14)
            .frame(maxWidth: .infinity, alignment: .leading)
            .liquidGlassSurface(cornerRadius: 12, tint: Color.codexGlassTint, shadowOpacity: 0.04)
        }
    }

    private var statusColor: Color {
        switch updater.phase {
        case .failed:
            .codexRed
        case .available:
            .codexAmber
        case .upToDate:
            .codexGreen
        default:
            .codexMuted
        }
    }

    private var primaryUpdateTitle: String {
        switch updater.phase {
        case .checking:
            "检查中…"
        case .available:
            "下载并安装"
        case .downloading:
            "下载中…"
        case .installing:
            "安装中…"
        case .failed:
            "重新检查"
        default:
            "检查更新"
        }
    }

    private func primaryUpdateAction() {
        switch updater.phase {
        case .available:
            updater.downloadAndInstall()
        default:
            updater.checkForUpdates()
        }
    }

    private var themeSection: some View {
        SettingsInlineRow(title: "主题", subtitle: "跟随系统，或固定浅色 / 深色") {
            SettingsMenuPicker(
                selection: $settings.theme,
                options: AppThemePreference.allCases,
                title: \.title,
                symbol: \.symbolName
            )
        }
    }

    private var refreshSection: some View {
        SettingsInlineRow(title: "自动刷新", subtitle: "登录后按设定间隔自动拉取额度") {
            SettingsMenuPicker(
                selection: $settings.autoRefreshInterval,
                options: AutoRefreshInterval.allCases,
                title: \.title,
                symbol: { $0 == .off ? "pause.circle" : "clock" }
            )
        }
    }

    private var statusBarDivider: some View {
        Rectangle()
            .fill(Color.codexLine.opacity(0.74))
            .frame(height: 1)
            .frame(maxWidth: .infinity)
    }

    private var petSection: some View {
        SettingsSection(
            title: "状态与 Pets",
            subtitle: "配置状态栏任务状态、胶囊颜色与 Codex 动画角色"
        ) {
            VStack(spacing: 10) {
                SettingsInlineRow(
                    title: "胶囊背景色",
                    subtitle: "自动模式按任务状态变色，也可以固定一种颜色"
                ) {
                    SettingsMenuPicker(
                        selection: $settings.petBackgroundColor,
                        options: StatusBarPetBackgroundColor.allCases,
                        title: \.title,
                        symbol: \.symbolName
                    )
                }

                SettingsInlineRow(
                    title: "点击胶囊",
                    subtitle: "选择点击状态栏胶囊后打开的窗口类型"
                ) {
                    SettingsMenuPicker(
                        selection: $settings.statusBarClickBehavior,
                        options: StatusBarClickBehavior.allCases,
                        title: \.title,
                        symbol: \.symbolName
                    )
                }

                SettingsInlineRow(
                    title: "显示动画 Pet",
                    subtitle: "开启显示动画 Pet，关闭显示原来的额度健康圆灯"
                ) {
                    Toggle("", isOn: $settings.petsEnabled)
                        .labelsHidden()
                        .toggleStyle(.switch)
                }

                SettingsInlineRow(
                    title: "活动状态流光",
                    subtitle: "非空闲时，在状态栏胶囊内显示从左向右的流光"
                ) {
                    Toggle("", isOn: $settings.statusBarWaveEnabled)
                        .labelsHidden()
                        .toggleStyle(.switch)
                }

                SettingsInlineRow(
                    title: "状态栏圆角",
                    subtitle: "同步调整胶囊与 Pet 区域圆角，范围 20%–50%"
                ) {
                    HStack(spacing: 8) {
                        Text("\(Int(settings.statusBarCornerPercent))%")
                            .font(.system(size: 11, weight: .medium, design: .monospaced))
                            .foregroundStyle(Color.codexMuted)
                            .frame(width: 30, alignment: .trailing)
                        Slider(
                            value: $settings.statusBarCornerPercent,
                            in: 20...50,
                            step: 1
                        )
                        .frame(width: 112)
                    }
                }

                if let pet = settings.selectedPet {
                    HStack(spacing: 12) {
                        PetSettingsThumbnail(pet: pet)
                            .frame(width: 48, height: 48)

                        VStack(alignment: .leading, spacing: 3) {
                            Text(pet.displayName)
                                .font(.system(size: 13, weight: .semibold))
                            Text("\(pet.source.title) · v\(pet.spriteVersionNumber) · \(pet.rowCount) 行动画")
                                .font(.system(size: 11))
                                .foregroundStyle(Color.codexMuted)
                        }

                        Spacer(minLength: 8)
                        petPicker
                    }
                    .padding(12)
                    .liquidGlassSurface(
                        cornerRadius: 12,
                        tint: Color.codexGlassTint,
                        shadowOpacity: 0.04
                    )
                } else {
                    Text("没有发现可用 Pet。请安装 Codex，或把自定义 Pet 放入 ~/.codex/pets。")
                        .font(.system(size: 12))
                        .foregroundStyle(Color.codexAmber)
                        .padding(12)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .liquidGlassSurface(
                            cornerRadius: 12,
                            tint: Color.codexGlassTint,
                            shadowOpacity: 0.04
                        )
                }

                HStack {
                    let builtInCount = settings.availablePets.filter { $0.source == .codexBuiltIn }.count
                    let customCount = settings.availablePets.filter { $0.source == .custom }.count
                    Text("已发现 \(builtInCount) 个内置 Pet，\(customCount) 个自定义 Pet")
                        .font(.system(size: 11))
                        .foregroundStyle(Color.codexMuted)
                    Spacer()
                    Button("重新扫描") {
                        settings.reloadPets()
                    }
                    .buttonStyle(.plain)
                    .font(.system(size: 12, weight: .medium))
                    .foregroundStyle(Color.codexPrimary)
                }
                .padding(.horizontal, 4)
            }
        }
    }

    private var petPicker: some View {
        Menu {
            let builtIns = settings.availablePets.filter { $0.source == .codexBuiltIn }
            let custom = settings.availablePets.filter { $0.source == .custom }

            if !builtIns.isEmpty {
                Section("Codex 内置") {
                    ForEach(builtIns) { pet in
                        petPickerButton(pet)
                    }
                }
            }
            if !custom.isEmpty {
                Section("自定义") {
                    ForEach(custom) { pet in
                        petPickerButton(pet)
                    }
                }
            }
        } label: {
            HStack(spacing: 6) {
                Text("选择")
                Image(systemName: "chevron.up.chevron.down")
                    .font(.system(size: 10, weight: .semibold))
            }
            .font(.system(size: 12, weight: .medium))
            .padding(.horizontal, 10)
            .padding(.vertical, 6)
            .liquidGlassSurface(
                cornerRadius: 8,
                tint: Color.codexGlassTint,
                shadowOpacity: 0.03,
                interactive: true
            )
        }
        .menuStyle(.borderlessButton)
        .fixedSize()
    }

    private func petPickerButton(_ pet: CodexPet) -> some View {
        Button {
            settings.selectedPetID = pet.id
        } label: {
            if settings.selectedPetID == pet.id {
                Label(pet.displayName, systemImage: "checkmark")
            } else {
                Text(pet.displayName)
            }
        }
    }
}

private struct ScrollIndicatorHider: NSViewRepresentable {
    func makeNSView(context: Context) -> NSView {
        let view = NSView()
        hideIndicators(from: view)
        return view
    }

    func updateNSView(_ nsView: NSView, context: Context) {
        hideIndicators(from: nsView)
    }

    private func hideIndicators(from view: NSView) {
        DispatchQueue.main.async {
            guard let scrollView = view.enclosingScrollView else { return }
            scrollView.hasVerticalScroller = false
            scrollView.hasHorizontalScroller = false
            scrollView.autohidesScrollers = true
        }
    }
}

private struct PetSettingsThumbnail: View {
    let pet: CodexPet
    @State private var image: NSImage?

    var body: some View {
        Group {
            if let image {
                Image(nsImage: image)
                    .resizable()
                    .interpolation(.none)
                    .scaledToFit()
            } else {
                Image(systemName: "pawprint.fill")
                    .font(.system(size: 22))
                    .foregroundStyle(Color.codexMuted)
            }
        }
        .task(id: pet.id) {
            image = PetSpriteSheet(url: pet.spritesheetURL)?.frame(
                row: 0,
                column: 0,
                displayHeight: 44
            )
        }
        .accessibilityLabel(pet.displayName)
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

private struct SettingsInlineRow<Content: View>: View {
    let title: String
    let subtitle: String
    @ViewBuilder let content: Content

    var body: some View {
        HStack(alignment: .center, spacing: 12) {
            VStack(alignment: .leading, spacing: 3) {
                Text(title)
                    .font(.system(size: 13, weight: .semibold))
                Text(subtitle)
                    .font(.system(size: 12))
                    .foregroundStyle(Color.codexMuted)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .frame(maxWidth: .infinity, alignment: .leading)

            content
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 12)
        .liquidGlassSurface(cornerRadius: 12, tint: Color.codexGlassTint, shadowOpacity: 0.04)
    }
}

private struct SettingsMenuPicker<Option: Hashable & Identifiable>: View {
    @Binding var selection: Option
    let options: [Option]
    let title: (Option) -> String
    let symbol: (Option) -> String

    var body: some View {
        Menu {
            ForEach(options) { option in
                Button {
                    selection = option
                } label: {
                    Label {
                        Text(title(option))
                    } icon: {
                        if selection == option {
                            Image(systemName: "checkmark")
                        }
                    }
                }
            }
        } label: {
            HStack(spacing: 6) {
                Label(title(selection), systemImage: symbol(selection))
                    .labelStyle(.titleOnly)
                Image(systemName: "chevron.up.chevron.down")
                    .font(.system(size: 10, weight: .semibold))
                    .foregroundStyle(Color.codexMuted)
            }
            .font(.system(size: 13, weight: .medium))
            .padding(.horizontal, 10)
            .padding(.vertical, 6)
            .liquidGlassSurface(
                cornerRadius: 8,
                tint: Color.codexGlassTint,
                shadowOpacity: 0.03,
                interactive: true
            )
        }
        .menuStyle(.borderlessButton)
        .fixedSize(horizontal: true, vertical: false)
    }
}

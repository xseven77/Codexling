import SwiftUI

struct SettingsView: View {
    @Bindable var store: UsageSnapshotStore
    @Bindable var settings: AppSettingsStore
    @Bindable var updater: AppUpdateController
    let layout: UsagePanelLayout
    let onLogout: () -> Void
    let onClose: () -> Void
    @State private var showsCodexlingPetInstallToast = false
    @State private var showsLogoutConfirmation = false

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
        .overlay(alignment: .bottom) {
            if showsCodexlingPetInstallToast {
                Label("Codexling Pet 已安装到本机 Codex", systemImage: "checkmark.circle.fill")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(.white)
                    .padding(.horizontal, 14)
                    .frame(height: 38)
                    .background(.black.opacity(0.84), in: Capsule(style: .continuous))
                    .padding(.bottom, 18)
                    .transition(.move(edge: .bottom).combined(with: .opacity))
                    .accessibilityLabel("Codexling Pet 安装成功")
            }
        }
        .alert("确认退出登录？", isPresented: $showsLogoutConfirmation) {
            Button("取消", role: .cancel) {}
            Button("退出登录", role: .destructive, action: onLogout)
        } message: {
            Text("退出后需要重新授权才能查看用量。")
        }
    }

    private var settingsContent: some View {
        VStack(alignment: .leading, spacing: 20) {
            accountCard
            updateSection
            petSection
        }
        .padding(.horizontal, 16)
        .padding(.top, 18)
        .padding(.bottom, 22)
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var accountCard: some View {
        HStack(spacing: 10) {
            VStack(alignment: .leading, spacing: 3) {
                HStack(spacing: 5) {
                    Text(store.isLoggedIn && store.snapshot.accountName?.isEmpty == false
                         ? store.snapshot.accountName!
                         : "OpenAI 账号")
                        .font(.system(size: 13, weight: .semibold))
                    if store.isLoggedIn {
                        Text(store.snapshot.planName)
                            .font(.system(size: 10, weight: .semibold))
                            .foregroundStyle(Color.codexGreen)
                            .padding(.horizontal, 8)
                            .padding(.vertical, 4)
                            .background(Color.codexGreen.opacity(0.10), in: Capsule())
                    }
                }
                Text(store.isLoggedIn
                     ? "\(store.snapshot.accountEmail) · \(store.snapshot.workspaceName)"
                     : "尚未连接 ChatGPT / Codex")
                    .font(.system(size: 11))
                    .foregroundStyle(Color.codexMuted)
                    .lineLimit(1)
            }
            Spacer()
            if store.isLoggedIn {
                Button("退出登录") { showsLogoutConfirmation = true }
                    .buttonStyle(.plain)
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(Color.codexRed)
                    .padding(.horizontal, 10)
                    .frame(height: 28)
                    .background(Color.codexRed.opacity(0.08), in: RoundedRectangle(cornerRadius: 7))
                    .overlay(RoundedRectangle(cornerRadius: 7).stroke(Color.codexRed.opacity(0.18), lineWidth: 0.7))
            } else {
                Text("未登录")
                    .font(.system(size: 9, weight: .semibold))
                    .foregroundStyle(Color.codexMuted)
                    .padding(.horizontal, 7)
                    .padding(.vertical, 4)
                    .background(Color.codexMuted.opacity(0.10), in: Capsule())
            }
        }
        .padding(.horizontal, 13)
        .frame(minHeight: 54)
        .settingsGroupSurface()
    }

    private var header: some View {
        HStack(spacing: 0) {
            Color.clear.frame(width: 34, height: 34)
            Spacer()
            Text("设置")
                .font(.system(size: 16, weight: .semibold))
            Spacer()
            Button(action: onClose) {
                Image(systemName: "xmark")
                    .font(.system(size: 15, weight: .medium))
                    .foregroundStyle(Color.codexInk)
                    .frame(width: 34, height: 34)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .help("关闭设置")
            .accessibilityLabel("关闭设置")
        }
        .padding(.horizontal, 16)
        .frame(maxWidth: .infinity)
        .frame(height: DetachedWindowMetrics.chromeHeaderHeight)
        .background(CodexChromeBackground(intensity: .header))
        .fixedSize(horizontal: false, vertical: true)
    }

    private var updateSection: some View {
        SettingsSection(title: "应用") {
            VStack(alignment: .leading, spacing: 0) {
                HStack(spacing: 12) {
                    VStack(alignment: .leading, spacing: 4) {
                        Text("Codexling \(updater.currentVersion)（\(updater.currentBuild)）")
                            .font(.system(size: 13, weight: .semibold))
                        Text(updateStatusText)
                            .font(.system(size: 11))
                            .foregroundStyle(statusColor)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    Spacer(minLength: 8)
                    HStack(spacing: 7) {
                        IconButton(
                            systemName: "arrow.up.right",
                            title: "打开 GitHub Releases",
                            action: updater.openReleasesPage
                        )
                        Button(primaryUpdateTitle, action: primaryUpdateAction)
                            .buttonStyle(CodexlingPetInstallButtonStyle())
                            .disabled(updater.phase.isBusy)
                    }
                }
                .padding(.horizontal, 16)
                .frame(minHeight: 66)

                if case .downloading = updater.phase {
                    ProgressView(value: updater.downloadProgress)
                        .progressViewStyle(.linear)
                        .tint(Color.codexPrimary)
                }
                SettingsRowDivider()
                themeSection
                SettingsRowDivider()
                refreshSection
            }
            .settingsGroupSurface()
            .frame(maxWidth: .infinity, alignment: .leading)
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

    private var updateStatusText: String {
        switch updater.phase {
        case .idle, .upToDate:
            "通过 GitHub Releases 检查新版本"
        default:
            updater.statusText
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

    private var petSection: some View {
        VStack(alignment: .leading, spacing: 20) {
            SettingsSection(
                title: "状态栏与 Pet",
                subtitle: "颜色与任务状态同步，或固定一种颜色。"
            ) {
                VStack(spacing: 0) {
                SettingsInlineRow(
                    title: "胶囊提醒色",
                    subtitle: "按额度余量切换：充足绿、偏低黄、紧张红、未知灰"
                ) {
                    HStack(spacing: 8) {
                        petBackgroundPreview
                        SettingsMenuPicker(
                            selection: $settings.petBackgroundColor,
                            options: StatusBarPetBackgroundColor.allCases,
                            title: \.title,
                            symbol: \.symbolName
                        )
                    }
                }
                SettingsRowDivider()

                SettingsInlineRow(
                    title: "活动状态流光",
                    subtitle: "非空闲时，在状态栏胶囊内显示从左向右的流光"
                ) {
                    SettingsSwitch(isOn: $settings.statusBarWaveEnabled)
                }
                }
                .settingsGroupSurface()
            }

            SettingsSection(
                title: "当前 Pet",
                subtitle: "规则：仅当未安装 Codexling Pet 时展示；安装后重扫并自动选中。"
            ) {
                VStack(spacing: 10) {
                if let pet = settings.selectedPet {
                    HStack(spacing: 12) {
                        PetSettingsThumbnail(pet: pet)
                            .frame(width: 58, height: 58)

                        VStack(alignment: .leading, spacing: 3) {
                            Text(pet.displayName)
                                .font(.system(size: 14, weight: .semibold))
                            Text("\(pet.source.title) · v\(pet.spriteVersionNumber) · \(pet.rowCount) 行动画")
                                .font(.system(size: 12))
                                .foregroundStyle(Color.codexMuted)
                        }

                        Spacer(minLength: 8)
                        petPicker
                    }
                    .padding(16)
                    .settingsGroupSurface()
                } else {
                    Text("没有发现可用 Pet。请安装 Codex，或把自定义 Pet 放入 ~/.codex/pets。")
                        .font(.system(size: 12))
                        .foregroundStyle(Color.codexAmber)
                        .padding(12)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .settingsGroupSurface()
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

                if !settings.isCodexlingPetInstalled {
                    codexlingPetInstallationCard
                }

                if let installationError = settings.codexlingPetInstallationError {
                    Text("Codexling Pet 安装失败：\(installationError)")
                        .font(.system(size: 12))
                        .foregroundStyle(Color.codexRed)
                        .padding(.horizontal, 4)
                }
                }
            }
        }
    }

    private var codexlingPetInstallationCard: some View {
        HStack(spacing: 12) {
            BundledCodexlingPetThumbnail()
                .frame(width: 58, height: 58)

            VStack(alignment: .leading, spacing: 4) {
                Text("安装 Codexling Pet")
                    .font(.system(size: 14, weight: .semibold))
                Text("Codexling 的专属小精灵 · v2 · 11 行动画")
                    .font(.system(size: 12))
                    .foregroundStyle(Color.codexMuted)
            }
            .frame(maxWidth: .infinity, alignment: .leading)

            Button {
                settings.installCodexlingPet()
                showCodexlingPetInstallToastIfNeeded()
            } label: {
                Label("安装", systemImage: "arrow.down.to.line")
                    .labelStyle(.titleAndIcon)
            }
            .buttonStyle(CodexlingPetInstallButtonStyle())
            .fixedSize()
        }
        .padding(16)
        .background(Color.codexGreen.opacity(0.035), in: RoundedRectangle(cornerRadius: 12))
        .overlay(RoundedRectangle(cornerRadius: 12).stroke(Color.codexGreen.opacity(0.20), lineWidth: 0.8))
    }

    private func showCodexlingPetInstallToastIfNeeded() {
        guard settings.isCodexlingPetInstalled else { return }
        withAnimation(.spring(response: 0.32, dampingFraction: 0.84)) {
            showsCodexlingPetInstallToast = true
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + 2.4) {
            withAnimation(.easeOut(duration: 0.2)) {
                showsCodexlingPetInstallToast = false
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
                Image(systemName: "chevron.down")
                    .font(.system(size: 10, weight: .semibold))
            }
            .font(.system(size: 12, weight: .medium))
        }
        .menuStyle(.borderlessButton)
        .menuIndicator(.hidden)
        .fixedSize()
    }

    @ViewBuilder
    private var petBackgroundPreview: some View {
        if settings.petBackgroundColor == .automatic {
            HStack(spacing: 5) {
                SettingsColorDot(color: .codexGreen)
                SettingsColorDot(color: .codexAmber)
                SettingsColorDot(color: .codexRed)
                SettingsColorDot(color: .codexMuted)
            }
        } else {
            SettingsColorDot(color: Color(nsColor: settings.petBackgroundColor.nsColor))
        }
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
        ZStack {
            if let image {
                Image(nsImage: image)
                    .resizable()
                    .interpolation(.none)
                    .scaledToFit()
                    .padding(4)
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
                displayHeight: 52
            )
        }
        .accessibilityLabel(pet.displayName)
    }
}

private struct BundledCodexlingPetThumbnail: View {
    @State private var image: NSImage?

    var body: some View {
        ZStack {
            if let image {
                Image(nsImage: image)
                    .resizable()
                    .interpolation(.none)
                    .scaledToFit()
                    .padding(4)
            } else {
                Image(systemName: "sparkles")
                    .foregroundStyle(Color.codexPrimary)
            }
        }
        .task {
            guard let directory = CodexlingPetInstaller.bundledPetDirectory() else { return }
            image = PetSpriteSheet(url: directory.appendingPathComponent("spritesheet.webp"))?.frame(
                row: 0,
                column: 0,
                displayHeight: 52
            )
        }
        .accessibilityLabel("Codexling Pet 预览")
    }
}

private struct CodexlingPetInstallButtonStyle: ButtonStyle {
    @Environment(\.isEnabled) private var isEnabled
    @Environment(\.colorScheme) private var colorScheme

    func makeBody(configuration: Configuration) -> some View {
        let isDark = colorScheme == .dark
        let backgroundColor: Color = if isDark {
            configuration.isPressed ? Color.white.opacity(0.18) : Color.white.opacity(0.11)
        } else {
            configuration.isPressed ? Color.codexPrimary.opacity(0.78) : Color.codexPrimary
        }
        let foregroundColor: Color = if isDark {
            Color.white.opacity(isEnabled ? 0.96 : 0.42)
        } else {
            Color.white.opacity(isEnabled ? 1 : 0.58)
        }

        configuration.label
            .font(.system(size: 12, weight: .semibold))
            .foregroundStyle(foregroundColor)
            .padding(.horizontal, 12)
            .frame(height: 34)
            .background(
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .fill(backgroundColor.opacity(isEnabled ? 1 : 0.60))
            )
            .overlay(
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .stroke(
                        isDark ? Color.white.opacity(isEnabled ? 0.16 : 0.08) : Color.black.opacity(0.08),
                        lineWidth: 0.8
                    )
            )
            .scaleEffect(configuration.isPressed ? 0.96 : 1)
            .animation(.easeOut(duration: 0.12), value: configuration.isPressed)
    }
}

private struct SettingsSection<Content: View>: View {
    let title: String
    var subtitle: String? = nil
    @ViewBuilder let content: Content

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            VStack(alignment: .leading, spacing: 3) {
                Text(title)
                    .font(.system(size: 14, weight: .semibold))
                if let subtitle {
                    Text(subtitle)
                        .font(.system(size: 11))
                        .foregroundStyle(Color.codexMuted)
                }
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
        .padding(.horizontal, 16)
        .padding(.vertical, 15)
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
                Image(systemName: "chevron.down")
                    .font(.system(size: 10, weight: .semibold))
                    .foregroundStyle(Color.codexMuted)
            }
            .font(.system(size: 13, weight: .medium))
        }
        .menuStyle(.borderlessButton)
        .menuIndicator(.hidden)
        .fixedSize(horizontal: true, vertical: false)
    }
}

private struct SettingsColorDot: View {
    let color: Color

    var body: some View {
        Circle()
            .fill(color)
            .frame(width: 11, height: 11)
            .overlay(Circle().stroke(Color.codexLine.opacity(0.72), lineWidth: 0.6))
    }
}

private struct SettingsSwitch: View {
    @Binding var isOn: Bool
    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        Button {
            withAnimation(.easeOut(duration: 0.16)) {
                isOn.toggle()
            }
        } label: {
            ZStack(alignment: isOn ? .trailing : .leading) {
                Capsule()
                    .fill(isOn ? Color.accentColor : inactiveTrack)
                Circle()
                    .fill(Color.white)
                    .frame(width: 18, height: 18)
                    .padding(3)
                    .shadow(color: Color.black.opacity(0.16), radius: 1.5, y: 1)
            }
            .frame(width: 42, height: 24)
            .contentShape(Capsule())
        }
        .buttonStyle(.plain)
        .accessibilityLabel("活动状态流光")
        .accessibilityValue(isOn ? "已开启" : "已关闭")
        .accessibilityAddTraits(.isButton)
    }

    private var inactiveTrack: Color {
        colorScheme == .dark
            ? Color(red: 0.30, green: 0.31, blue: 0.32)
            : Color(red: 0.78, green: 0.79, blue: 0.80)
    }
}

private struct SettingsRowDivider: View {
    var body: some View {
        Rectangle()
            .fill(Color.codexLine.opacity(0.82))
            .frame(height: 0.7)
    }
}

private extension View {
    func settingsGroupSurface() -> some View {
        background(Color.codexCard.opacity(0.76), in: RoundedRectangle(cornerRadius: 12, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .stroke(Color.codexLine.opacity(0.88), lineWidth: 0.8)
            )
    }
}

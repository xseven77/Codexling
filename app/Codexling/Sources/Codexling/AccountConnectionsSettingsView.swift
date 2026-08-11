import SwiftUI
@preconcurrency import AppKit
import SwiftUI

private enum ConnectionPickerTab: String, CaseIterable, Identifiable {
    case agent
    case apiKey

    var id: String { rawValue }
    var title: String { self == .agent ? "Agent 账号" : "API Key" }
}

private enum ConnectionModalPage {
    case picker
    case deepSeek
}

/// Dashboard-owned modal matching the connection picker demonstrated by the
/// landing Preview. It intentionally stays inside the dashboard instead of
/// navigating to Settings or presenting a native macOS sheet.
struct AccountConnectionsModalView: View {
    @Environment(\.colorScheme) private var colorScheme
    @Bindable var store: MultiAgentSettingsStore
    let onClose: () -> Void

    @State private var selectedTab: ConnectionPickerTab = .agent
    @State private var page: ConnectionModalPage = .picker
    @State private var label = ""
    @State private var apiKey = ""

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            modalHeader

            switch page {
            case .picker:
                pickerContent
            case .deepSeek:
                deepSeekForm
            }
        }
        .padding(16)
        .frame(maxWidth: 330)
        .background(modalSurface, in: RoundedRectangle(cornerRadius: 20, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 20, style: .continuous)
                .strokeBorder(modalBorder, lineWidth: 1)
        }
        .shadow(color: .black.opacity(colorScheme == .dark ? 0.52 : 0.24), radius: 28, y: 14)
        .accessibilityElement(children: .contain)
        .accessibilityLabel("添加账号或 API Key")
        .onDisappear {
            store.cancelCurrentCodexOAuth()
        }
    }

    private var modalHeader: some View {
        HStack(alignment: .top, spacing: 12) {
            VStack(alignment: .leading, spacing: 4) {
                Text(page == .picker ? "NEW CONNECTION" : "NEW CREDENTIAL")
                    .font(.system(size: 9, weight: .bold))
                    .tracking(1.5)
                    .foregroundStyle(Color.codexGreen)
                Text(headerTitle)
                    .font(.system(size: 17, weight: .bold))
                Text(headerSubtitle)
                    .font(.system(size: 10))
                    .foregroundStyle(Color.codexMuted)
                    .padding(.top, 2)
            }
            Spacer(minLength: 8)
            Button(action: closeModal) {
                Image(systemName: "xmark")
                    .font(.system(size: 12, weight: .medium))
                    .foregroundStyle(Color.codexMuted)
                    .frame(width: 38, height: 38)
                    .contentShape(Circle())
                    .background(closeButtonSurface, in: Circle())
            }
            .buttonStyle(CodexPressableCircleStyle())
            .accessibilityLabel("关闭添加连接")
        }
    }

    private var headerTitle: String {
        switch page {
        case .picker: "添加账号或 API Key"
        case .deepSeek: "添加 DeepSeek API Key"
        }
    }

    private var headerSubtitle: String {
        switch page {
        case .picker: "同一种 Agent 可以登录多个账号。"
        case .deepSeek: "Key 只存入 macOS Keychain，用于官方余额接口。"
        }
    }

    private var pickerContent: some View {
        VStack(spacing: 12) {
            HStack(spacing: 4) {
                ForEach(ConnectionPickerTab.allCases) { tab in
                    Button {
                        selectedTab = tab
                    } label: {
                        Text(tab.title)
                            .font(.system(size: 10, weight: .semibold))
                            .frame(maxWidth: .infinity)
                            .frame(height: 30)
                            .contentShape(Rectangle())
                            .background(
                                selectedTab == tab ? selectedTabSurface : Color.clear,
                                in: RoundedRectangle(cornerRadius: 9, style: .continuous)
                            )
                    }
                    .buttonStyle(CodexPressableStyle(cornerRadius: 9))
                    .frame(maxWidth: .infinity)
                    .foregroundStyle(selectedTab == tab ? Color.codexInk : Color.codexMuted)
                }
            }
            .padding(4)
            .background(segmentedSurface, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
            .padding(.top, 14)

            if selectedTab == .agent {
                connectionOption(
                    asset: .codex,
                    title: "登录另一个 Codex 账号",
                    subtitle: "通过官方 OAuth 授权",
                    supportsOAuthCancellation: true
                ) {
                    resetFields()
                    Task {
                        if await store.addCodexAccount() {
                            onClose()
                        }
                    }
                }
            } else {
                connectionOption(
                    asset: .deepSeek,
                    title: "添加 DeepSeek API Key",
                    subtitle: "查询官方账户余额"
                ) {
                    resetFields()
                    page = .deepSeek
                }
            }
            if let message = store.lastMessage,
               message.contains("失败") || message.contains("取消") {
                Text(message)
                    .font(.system(size: 9))
                    .foregroundStyle(message.contains("失败") ? Color.codexRed : Color.codexMuted)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
    }

    private func connectionOption(
        asset: BrandAssetID,
        title: String,
        subtitle: String,
        supportsOAuthCancellation: Bool = false,
        action: @escaping () -> Void
    ) -> some View {
        ZStack(alignment: .trailing) {
            Button(action: action) {
                HStack(spacing: 10) {
                    BrandIconView(asset: asset, size: 38, cornerRadius: 10)
                    VStack(alignment: .leading, spacing: 2) {
                        Text(title)
                            .font(.system(size: 11, weight: .semibold))
                        Text(subtitle)
                            .font(.system(size: 9))
                            .foregroundStyle(Color.codexMuted)
                    }
                    Spacer()
                    if supportsOAuthCancellation && store.isCodexOAuthInProgress {
                        Color.clear.frame(width: 58, height: 1)
                    } else if store.isMutatingConnections {
                        ProgressView().controlSize(.small)
                    } else {
                        Image(systemName: "chevron.right")
                            .font(.system(size: 10, weight: .semibold))
                            .foregroundStyle(Color.codexMuted)
                    }
                }
                .padding(.horizontal, 10)
                .frame(height: 58)
                .contentShape(Rectangle())
                .background(optionSurface, in: RoundedRectangle(cornerRadius: 13, style: .continuous))
                .overlay {
                    RoundedRectangle(cornerRadius: 13, style: .continuous)
                        .strokeBorder(Color.codexLine, lineWidth: 1)
                }
            }
            .buttonStyle(CodexPressableCardStyle(cornerRadius: 13))
            .disabled(store.isMutatingConnections)

            if supportsOAuthCancellation && store.isCodexOAuthInProgress {
                Button {
                    store.cancelCurrentCodexOAuth()
                } label: {
                    HStack(spacing: 5) {
                        Image(systemName: "xmark")
                            .font(.system(size: 8, weight: .bold))
                        Text("取消")
                    }
                    .font(.system(size: 10, weight: .semibold))
                    .foregroundStyle(Color.codexRed)
                    .padding(.horizontal, 9)
                    .frame(height: 30)
                    .background(Color.codexRed.opacity(0.08), in: Capsule())
                }
                .buttonStyle(CodexPressableStyle(cornerRadius: 15))
                .padding(.trailing, 9)
                .accessibilityLabel("取消 Codex OAuth 登录")
            }
        }
    }

    private var deepSeekForm: some View {
        VStack(alignment: .leading, spacing: 12) {
            TextField("连接名称", text: $label)
                .textFieldStyle(.roundedBorder)
            PlainTextField(text: $apiKey, placeholder: "sk-…")
                .frame(height: 28)
            Text("Key 明文显示，可选中复制", tableName: nil, bundle: nil, comment: "")
                .font(.system(size: 9))
                .foregroundStyle(Color.codexMuted)
            if let message = store.lastMessage, message.contains("失败") {
                Text(message)
                    .font(.system(size: 9))
                    .foregroundStyle(Color.red)
            }
            HStack(spacing: 8) {
                Button { page = .picker } label: {
                    Text("返回")
                        .font(.system(size: 11, weight: .medium))
                        .padding(.horizontal, 14)
                        .frame(height: 32)
                        .background(segmentedSurface, in: RoundedRectangle(cornerRadius: 7, style: .continuous))
                }
                .buttonStyle(CodexPressableStyle(cornerRadius: 7))
                Spacer()
                Button {
                    Task {
                        if await store.addDeepSeekConnection(label: label, apiKey: apiKey) {
                            onClose()
                        }
                    }
                } label: {
                    HStack(spacing: 6) {
                        if store.isMutatingConnections {
                            ProgressView().controlSize(.small)
                        } else {
                            Text("验证并添加")
                        }
                    }
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(Color.white)
                    .padding(.horizontal, 15)
                    .frame(height: 32)
                    .background(Color.accentColor, in: RoundedRectangle(cornerRadius: 7, style: .continuous))
                }
                .buttonStyle(CodexPressableStyle(cornerRadius: 7, ink: .softLight))
                .disabled(store.isMutatingConnections || apiKey.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            }
        }
        .padding(.top, 16)
    }

    private func resetFields() {
        label = ""
        apiKey = ""
    }

    private func closeModal() {
        store.cancelCurrentCodexOAuth()
        onClose()
    }

    private var modalSurface: Color {
        colorScheme == .dark
            ? Color(red: 0.205, green: 0.205, blue: 0.218)
            : Color(red: 0.985, green: 0.985, blue: 0.980)
    }

    private var modalBorder: Color {
        colorScheme == .dark ? Color.white.opacity(0.28) : Color.black.opacity(0.12)
    }

    private var segmentedSurface: Color {
        colorScheme == .dark ? Color.black.opacity(0.35) : Color.black.opacity(0.055)
    }

    private var selectedTabSurface: Color {
        colorScheme == .dark ? Color.white.opacity(0.10) : Color.white.opacity(0.95)
    }

    private var optionSurface: Color {
        colorScheme == .dark ? Color.white.opacity(0.035) : Color.white.opacity(0.62)
    }

    private var closeButtonSurface: Color {
        colorScheme == .dark ? Color.black.opacity(0.12) : Color.black.opacity(0.035)
    }
}

// MARK: - Plain TextField (NSTextField wrapper)

/// 用原生 NSTextField 包装的文本输入框。Overlay/modal 中
/// SwiftUI 的 TextField 快捷键可能失效；通过 NSTextField 子类
/// 的 performKeyEquivalent 手动接管 Cmd+C/V/X/A。
private struct PlainTextField: NSViewRepresentable {
    @Binding var text: String
    let placeholder: String

    func makeCoordinator() -> Coordinator {
        Coordinator(self)
    }

    func makeNSView(context: Context) -> NSTextField {
        let field = KeyShortcutTextField()
        field.placeholderString = placeholder
        field.isBezeled = true
        field.bezelStyle = .roundedBezel
        field.delegate = context.coordinator
        field.font = NSFont.systemFont(ofSize: NSFont.systemFontSize)
        field.lineBreakMode = .byTruncatingTail
        return field
    }

    func updateNSView(_ nsView: NSTextField, context: Context) {
        if nsView.stringValue != text {
            nsView.stringValue = text
        }
    }

    /// 重写 performKeyEquivalent 接管快捷键，天然在 MainActor 无警告。
    private final class KeyShortcutTextField: NSTextField {
        override func performKeyEquivalent(with event: NSEvent) -> Bool {
            guard event.modifierFlags.intersection(.deviceIndependentFlagsMask) == .command,
                  let chars = event.charactersIgnoringModifiers?.lowercased()
            else { return super.performKeyEquivalent(with: event) }

            switch chars {
            case "c":
                currentEditor()?.copy(nil)
                return true
            case "v":
                currentEditor()?.paste(nil)
                return true
            case "x":
                currentEditor()?.cut(nil)
                return true
            case "a":
                currentEditor()?.selectAll(nil)
                return true
            default:
                break
            }
            return super.performKeyEquivalent(with: event)
        }
    }

    final class Coordinator: NSObject, NSTextFieldDelegate {
        let parent: PlainTextField

        init(_ parent: PlainTextField) {
            self.parent = parent
        }

        func controlTextDidChange(_ notification: Notification) {
            guard let field = notification.object as? NSTextField else { return }
            parent.text = field.stringValue
        }
    }
}

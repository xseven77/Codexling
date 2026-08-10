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
            Button(action: onClose) {
                Image(systemName: "xmark")
                    .font(.system(size: 12, weight: .medium))
                    .frame(width: 30, height: 30)
            }
            .buttonStyle(.plain)
            .foregroundStyle(Color.codexMuted)
            .background(closeButtonSurface, in: Circle())
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
                    .buttonStyle(.plain)
                    .frame(maxWidth: .infinity)
                    .contentShape(RoundedRectangle(cornerRadius: 9, style: .continuous))
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
                    subtitle: "通过官方 OAuth 授权"
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
               message.contains("失败") {
                Text(message)
                    .font(.system(size: 9))
                    .foregroundStyle(Color.codexRed)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
    }

    private func connectionOption(
        asset: BrandAssetID,
        title: String,
        subtitle: String,
        action: @escaping () -> Void
    ) -> some View {
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
                if store.isMutatingConnections {
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
        .buttonStyle(.plain)
        .disabled(store.isMutatingConnections)
    }

    private var deepSeekForm: some View {
        VStack(alignment: .leading, spacing: 12) {
            TextField("连接名称", text: $label)
                .textFieldStyle(.roundedBorder)
            SecureField("sk-…", text: $apiKey)
                .textFieldStyle(.roundedBorder)
            if let message = store.lastMessage, message.contains("失败") {
                Text(message)
                    .font(.system(size: 9))
                    .foregroundStyle(Color.red)
            }
            HStack(spacing: 8) {
                Button("返回") { page = .picker }
                    .buttonStyle(.bordered)
                Spacer()
                Button {
                    Task {
                        if await store.addDeepSeekConnection(label: label, apiKey: apiKey) {
                            onClose()
                        }
                    }
                } label: {
                    if store.isMutatingConnections {
                        ProgressView().controlSize(.small)
                    } else {
                        Text("验证并添加")
                    }
                }
                .buttonStyle(.borderedProminent)
                .disabled(store.isMutatingConnections || apiKey.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            }
        }
        .padding(.top, 16)
    }

    private func resetFields() {
        label = ""
        apiKey = ""
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

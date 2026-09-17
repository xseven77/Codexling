import AppKit
import CoreImage.CIFilterBuiltins
import SwiftUI

// MARK: - QR Code View

private struct QRCodeView: View {
    let content: String
    let size: CGFloat

    var body: some View {
        if let image = generateQRCode(from: content) {
            Image(nsImage: image)
                .interpolation(.none)
                .resizable()
                .scaledToFit()
                .frame(width: size, height: size)
                .padding(10)
                .background(Color.white)
                .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
                .overlay(
                    RoundedRectangle(cornerRadius: 12, style: .continuous)
                        .stroke(Color.black.opacity(0.08), lineWidth: 1)
                )
                .shadow(color: Color.black.opacity(0.12), radius: 6, x: 0, y: 2)
        } else {
            Rectangle()
                .fill(Color.codexMist)
                .frame(width: size, height: size)
                .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
                .overlay(
                    Text("无法生成二维码")
                        .font(.system(size: 11))
                        .foregroundStyle(Color.codexMuted)
                )
        }
    }

    private func generateQRCode(from string: String) -> NSImage? {
        guard let data = string.data(using: .utf8) else { return nil }
        let filter = CIFilter.qrCodeGenerator()
        filter.setValue(data, forKey: "inputMessage")
        filter.setValue("M", forKey: "inputCorrectionLevel")

        guard let outputImage = filter.outputImage else { return nil }
        let transform = CGAffineTransform(scaleX: 6, y: 6)
        let scaledImage = outputImage.transformed(by: transform)

        let rep = NSCIImageRep(ciImage: scaledImage)
        let nsImage = NSImage(size: rep.size)
        nsImage.addRepresentation(rep)
        return nsImage
    }
}

// MARK: - Mobile Companion Settings View

struct MobileCompanionSettingsView: View {
    @State private var syncManager = MobileSyncManager.shared
    @State private var pluginInstaller = WebPluginInstaller.shared
    @State private var pluginStatus: WebPluginStatus = WebPluginInstaller.shared.currentStatus()
    @State private var isDownloadingPlugin = false
    @State private var downloadProgress: Double = 0.0
    @State private var actionMessage: String?
    @State private var isErrorMessage = false
    @State private var showsTokenRegenerateAlert = false

    var onShowToast: (String, String) -> Void = { _, _ in }

    var body: some View {
        VStack(alignment: .leading, spacing: 22) {
            serverAndPairingSection
            pluginManagementSection
        }
        .padding(.bottom, 24)
        .onAppear {
            refreshStatus()
        }
    }

    // MARK: - Section 1: Server & Pairing

    private var serverAndPairingSection: some View {
        SettingsSection(
            title: "局域网同步服务与移动端配对",
            subtitle: "通过局域网广播 Agent 状态、额度与伴生宠物，手机扫码免安装即开"
        ) {
            VStack(alignment: .leading, spacing: 16) {
                // 1. 服务控制与运行指示
                HStack(spacing: 12) {
                    Toggle("启用移动端同步服务", isOn: $syncManager.isEnabled)
                        .toggleStyle(.switch)
                        .font(.system(size: 13, weight: .medium))

                    Spacer()

                    HStack(spacing: 6) {
                        Circle()
                            .fill(syncManager.isRunning ? Color.codexGreen : Color.codexMuted.opacity(0.4))
                            .frame(width: 8, height: 8)

                        Text(syncManager.isRunning ? "服务正常运行中" : "已停止")
                            .font(.system(size: 12, weight: .medium))
                            .foregroundStyle(syncManager.isRunning ? Color.codexGreen : Color.codexMuted)

                        Text("·")
                            .foregroundStyle(Color.codexMuted)

                        Text("端口 \(syncManager.port)")
                            .font(.system(size: 11.5, design: .monospaced))
                            .foregroundStyle(Color.codexMuted)
                    }
                    .padding(.horizontal, 10)
                    .padding(.vertical, 4)
                    .background(Color.codexMist.opacity(0.5))
                    .clipShape(Capsule())
                }

                if let err = syncManager.serverError {
                    HStack(spacing: 6) {
                        Image(systemName: "exclamationmark.triangle.fill")
                            .foregroundStyle(Color.codexRed)
                        Text("服务启动异常: \(err)")
                            .font(.system(size: 11.5))
                            .foregroundStyle(Color.codexRed)
                    }
                    .padding(8)
                    .background(Color.codexRed.opacity(0.08))
                    .clipShape(RoundedRectangle(cornerRadius: 6))
                }

                Divider()
                    .overlay(Color.codexLine.opacity(0.6))

                // 2. 二维码与局域网直链
                if syncManager.isEnabled && syncManager.isRunning {
                    HStack(alignment: .top, spacing: 20) {
                        QRCodeView(content: syncManager.webURLString, size: 140)

                        VStack(alignment: .leading, spacing: 10) {
                            Text("手机扫码一键连接")
                                .font(.system(size: 13, weight: .bold))
                                .foregroundStyle(Color.codexInk)

                            Text("在同一 Wi-Fi 局域网下，使用 iPhone 相机或任意移动端浏览器扫描左侧二维码，即可直接打开 1:1 伴生看盘界面，无需安装 App。")
                                .font(.system(size: 12))
                                .foregroundStyle(Color.codexMuted)
                                .lineSpacing(3)

                            // 访问链接展示与快捷复制
                            VStack(alignment: .leading, spacing: 6) {
                                Text("局域网直连网址:")
                                    .font(.system(size: 11, weight: .medium))
                                    .foregroundStyle(Color.codexMuted)

                                HStack(spacing: 8) {
                                    Text(syncManager.webURLString)
                                        .font(.system(size: 11, design: .monospaced))
                                        .foregroundStyle(Color.codexInk)
                                        .lineLimit(1)
                                        .truncationMode(.middle)
                                        .padding(.horizontal, 8)
                                        .padding(.vertical, 5)
                                        .frame(maxWidth: .infinity, alignment: .leading)
                                        .background(Color.codexMist)
                                        .clipShape(RoundedRectangle(cornerRadius: 6))

                                    Button {
                                        NSPasteboard.general.clearContents()
                                        NSPasteboard.general.setString(syncManager.webURLString, forType: .string)
                                        onShowToast("已复制移动端访问网址", "doc.on.doc")
                                    } label: {
                                        HStack(spacing: 4) {
                                            Image(systemName: "doc.on.doc")
                                            Text("复制")
                                        }
                                        .font(.system(size: 11.5))
                                    }
                                    .buttonStyle(.bordered)

                                    Button {
                                        if let url = URL(string: syncManager.webURLString) {
                                            NSWorkspace.shared.open(url)
                                        }
                                    } label: {
                                        Image(systemName: "arrow.up.forward.square")
                                    }
                                    .buttonStyle(.bordered)
                                    .help("在默认浏览器中打开预览")
                                }
                            }

                            HStack(spacing: 12) {
                                Button(role: .destructive) {
                                    showsTokenRegenerateAlert = true
                                } label: {
                                    HStack(spacing: 4) {
                                        Image(systemName: "arrow.triangle.2.circlepath")
                                        Text("重新生成配对 Token")
                                    }
                                    .font(.system(size: 11))
                                }
                                .buttonStyle(.borderless)
                                .foregroundStyle(Color.codexMuted)
                            }
                            .padding(.top, 4)
                        }
                    }
                    .padding(14)
                    .background(Color.codexMist.opacity(0.35))
                    .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
                } else {
                    HStack(spacing: 10) {
                        Image(systemName: "power.circle")
                            .font(.system(size: 24))
                            .foregroundStyle(Color.codexMuted)

                        Text("同步服务未开启，开启后即可在此查看局域网配对二维码与直连网址。")
                            .font(.system(size: 12))
                            .foregroundStyle(Color.codexMuted)
                    }
                    .padding(.vertical, 12)
                }
            }
        }
        .alert("重新生成配对 Token？", isPresented: $showsTokenRegenerateAlert) {
            Button("取消", role: .cancel) {}
            Button("重新生成", role: .destructive) {
                syncManager.regenerateToken()
                onShowToast("已生成全新配对 Token，历史二维码已失效", "checkmark.shield")
            }
        } message: {
            Text("重新生成后，之前已连接或保存旧 Token 的设备将无法访问，需要重新扫码连接。")
        }
    }

    // MARK: - Section 2: Plugin Management

    private var pluginManagementSection: some View {
        SettingsSection(
            title: "Web 伴生前端插件",
            subtitle: "管理桌面端私有托管的 1:1 移动看板 Web Core 静态资源包"
        ) {
            VStack(alignment: .leading, spacing: 14) {
                // 插件状态卡片
                HStack(spacing: 14) {
                    Image(systemName: pluginStatus.isInstalled ? "shippingbox.fill" : "shippingbox")
                        .font(.system(size: 24))
                        .foregroundStyle(pluginStatus.isInstalled ? Color.codexGreen : Color.codexAmber)
                        .frame(width: 40, height: 40)
                        .background((pluginStatus.isInstalled ? Color.codexGreen : Color.codexAmber).opacity(0.12))
                        .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))

                    VStack(alignment: .leading, spacing: 3) {
                        HStack(spacing: 8) {
                            Text(pluginStatus.isInstalled ? "官方 Web 伴生插件已就绪" : "未安装 Web 前端插件")
                                .font(.system(size: 13, weight: .bold))
                                .foregroundStyle(Color.codexInk)

                            if pluginStatus.isInstalled {
                                Text("v\(pluginStatus.displayVersion)")
                                    .font(.system(size: 10.5, weight: .bold, design: .monospaced))
                                    .padding(.horizontal, 6)
                                    .padding(.vertical, 2)
                                    .foregroundStyle(Color.codexGreen)
                                    .background(Color.codexGreen.opacity(0.12))
                                    .clipShape(Capsule())
                            }
                        }

                        Text(
                            pluginStatus.isInstalled
                                ? "资源体积 \(pluginStatus.displaySizeString) · 支持 10 款伴生宠物与 Canvas 双正弦液态波浪"
                                : "未安装时访问 58350 根路由将展示友好引导页，API 数据广播正常工作。"
                        )
                        .font(.system(size: 11.5))
                        .foregroundStyle(Color.codexMuted)
                    }

                    Spacer()

                    // 一键网络安装 / 更新按钮
                    Button {
                        downloadAndInstallPlugin()
                    } label: {
                        HStack(spacing: 6) {
                            if isDownloadingPlugin {
                                ProgressView()
                                    .controlSize(.small)
                                Text("下载安装中...")
                            } else {
                                Image(systemName: pluginStatus.isInstalled ? "arrow.triangle.2.circlepath" : "arrow.down.circle.fill")
                                Text(pluginStatus.isInstalled ? "检查更新" : "一键从网络安装")
                            }
                        }
                        .font(.system(size: 12, weight: .medium))
                        .padding(.horizontal, 14)
                        .padding(.vertical, 7)
                        .foregroundStyle(Color.codexOnPrimary)
                        .background(Color.codexPrimary, in: RoundedRectangle(cornerRadius: 8, style: .continuous))
                    }
                    .buttonStyle(.plain)
                    .disabled(isDownloadingPlugin)
                }
                .padding(12)
                .background(Color.codexMist.opacity(0.35))
                .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))

                if let message = actionMessage {
                    HStack(spacing: 6) {
                        Image(systemName: isErrorMessage ? "exclamationmark.triangle.fill" : "checkmark.circle.fill")
                            .foregroundStyle(isErrorMessage ? Color.codexRed : Color.codexGreen)

                        Text(message)
                            .font(.system(size: 11.5))
                            .foregroundStyle(isErrorMessage ? Color.codexRed : Color.codexGreen)
                    }
                    .padding(.horizontal, 4)
                }

                // 辅助操作
                HStack(spacing: 12) {
                    Button {
                        importLocalPluginZip()
                    } label: {
                        HStack(spacing: 5) {
                            Image(systemName: "folder.badge.gearshape")
                            Text("从本地 .zip 导入...")
                        }
                        .font(.system(size: 11.5))
                        .padding(.horizontal, 10)
                        .padding(.vertical, 5)
                        .background(Color.codexMist.opacity(0.4), in: RoundedRectangle(cornerRadius: 6, style: .continuous))
                    }
                    .buttonStyle(.plain)
                    .disabled(isDownloadingPlugin)

                    Button {
                        NSWorkspace.shared.selectFile(nil, inFileViewerRootedAtPath: pluginInstaller.pluginDirectory.path)
                    } label: {
                        HStack(spacing: 5) {
                            Image(systemName: "folder")
                            Text("在访达中打开目录")
                        }
                        .font(.system(size: 11.5))
                        .padding(.horizontal, 10)
                        .padding(.vertical, 5)
                        .background(Color.codexMist.opacity(0.4), in: RoundedRectangle(cornerRadius: 6, style: .continuous))
                    }
                    .buttonStyle(.plain)

                    if pluginStatus.isInstalled {
                        Button(role: .destructive) {
                            uninstallPlugin()
                        } label: {
                            Text("移除插件")
                                .font(.system(size: 11.5))
                                .foregroundStyle(Color.codexRed)
                                .padding(.horizontal, 10)
                                .padding(.vertical, 5)
                                .background(Color.codexRed.opacity(0.12), in: RoundedRectangle(cornerRadius: 6, style: .continuous))
                        }
                        .buttonStyle(.plain)
                        .disabled(isDownloadingPlugin)
                    }
                }
            }
        }
    }

    // MARK: - Actions

    private func refreshStatus() {
        pluginStatus = pluginInstaller.currentStatus()
    }

    private func downloadAndInstallPlugin() {
        isDownloadingPlugin = true
        actionMessage = "正在连接 GitHub Release 下载最新插件包..."
        isErrorMessage = false

        Task {
            do {
                try await pluginInstaller.downloadAndInstall()
                await MainActor.run {
                    self.isDownloadingPlugin = false
                    self.refreshStatus()
                    self.actionMessage = "插件安装成功！当前版本 v\(self.pluginStatus.displayVersion)"
                    self.isErrorMessage = false
                    self.onShowToast("Web 伴生插件已成功安装", "checkmark.circle.fill")
                }
            } catch {
                await MainActor.run {
                    self.isDownloadingPlugin = false
                    self.actionMessage = "安装失败: \(error.localizedDescription)"
                    self.isErrorMessage = true
                }
            }
        }
    }

    private func importLocalPluginZip() {
        let panel = NSOpenPanel()
        panel.title = "选择 Web 伴生插件压缩包 (.zip)"
        panel.prompt = "导入插件"
        panel.allowedContentTypes = [.zip]
        panel.allowsMultipleSelection = false
        panel.canChooseDirectories = false

        guard panel.runModal() == .OK, let fileURL = panel.url else { return }

        do {
            try pluginInstaller.install(fromLocalZip: fileURL)
            refreshStatus()
            actionMessage = "本地插件导入成功！版本 v\(pluginStatus.displayVersion)"
            isErrorMessage = false
            onShowToast("本地插件导入成功", "checkmark.circle.fill")
        } catch {
            actionMessage = "导入失败: \(error.localizedDescription)"
            isErrorMessage = true
        }
    }

    private func uninstallPlugin() {
        do {
            try pluginInstaller.uninstall()
            refreshStatus()
            actionMessage = "已移除 Web 伴生插件，服务现使用内置默认页。"
            isErrorMessage = false
            onShowToast("已移除 Web 插件", "trash")
        } catch {
            actionMessage = "移除失败: \(error.localizedDescription)"
            isErrorMessage = true
        }
    }
}

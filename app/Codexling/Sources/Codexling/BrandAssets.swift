import AppKit
import SwiftUI

enum BrandAssetID: String, Sendable {
    case codex
    case hermesAgent = "hermes-agent"
    case deepSeek = "deepseek"

    static func agent(_ id: AgentID) -> BrandAssetID {
        switch id {
        case .codex: .codex
        case .hermes: .hermesAgent
        case .deepseekHarness: .deepSeek
        default: .codex
        }
    }
}

enum BrandAssetCatalog {
    static func image(for id: BrandAssetID, prefersColor: Bool = true) -> NSImage? {
        guard let root = Bundle.main.resourceURL?
            .appendingPathComponent("BrandAssets/catalog", isDirectory: true)
            .appendingPathComponent(id.rawValue, isDirectory: true) else { return nil }
        let candidates = prefersColor
            ? ["color.svg", "icon.svg", "app-icon.png"]
            : ["icon.svg", "color.svg", "app-icon.png"]
        for file in candidates {
            let url = root.appendingPathComponent(file)
            if let image = NSImage(contentsOf: url) { return image }
        }
        return nil
    }
}

struct BrandIconView: View {
    let asset: BrandAssetID
    var size: CGFloat = 38
    var cornerRadius: CGFloat = 10

    var body: some View {
        Group {
            if let image = BrandAssetCatalog.image(for: asset) {
                Image(nsImage: image)
                    .resizable()
                    .scaledToFit()
                    .padding(contentInset)
            } else {
                Image(systemName: "app.dashed")
                    .font(.system(size: size * 0.42, weight: .medium))
                    .foregroundStyle(Color.codexMuted)
            }
        }
        .frame(width: size, height: size)
        .background(Color.codexCard, in: RoundedRectangle(cornerRadius: cornerRadius, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                .strokeBorder(Color.codexLine.opacity(0.75), lineWidth: 0.7)
        }
        .accessibilityHidden(true)
    }

    private var contentInset: CGFloat {
        // Codex's color SVG already includes its own white tile and optical
        // padding. Keeping the generic inset makes the terminal chevron blur
        // into that tile at compact sizes and look like a clipped corner.
        asset == .codex ? size * 0.10 : size * 0.16
    }
}

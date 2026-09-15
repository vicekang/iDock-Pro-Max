import AppKit
import SwiftUI

enum IDockBrand {
    static let name = "iDock Pro Max"
    static let releasesURL = URL(string: "https://github.com/vicekang/celldock-codex/releases")!
}

/// Window backing sits beneath the glass navigation, never above it.
struct IDockWindowBackdrop: View {
    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency

    var body: some View {
        Group {
            if reduceTransparency {
                Color(nsColor: .windowBackgroundColor)
            } else {
                IDockWindowMaterial()
            }
        }
        .ignoresSafeArea()
        .allowsHitTesting(false)
    }
}

private struct IDockWindowMaterial: NSViewRepresentable {
    func makeNSView(context: Context) -> NSVisualEffectView {
        let view = NSVisualEffectView()
        view.material = .underWindowBackground
        view.blendingMode = .behindWindow
        view.state = .followsWindowActiveState
        return view
    }

    func updateNSView(_ view: NSVisualEffectView, context: Context) {}
}

/// A quiet reading surface, distinct from the floating glass control layer.
struct IDockContentSurface: View {
    @Environment(\.colorScheme) private var scheme
    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency
    @Environment(\.colorSchemeContrast) private var contrast

    var body: some View {
        RoundedRectangle(cornerRadius: 24, style: .continuous)
            .fill(Color(nsColor: .windowBackgroundColor)
                .opacity(reduceTransparency ? 1 : (scheme == .dark ? 0.92 : 0.88)))
            .overlay {
                RoundedRectangle(cornerRadius: 24, style: .continuous)
                    .strokeBorder(Color.primary.opacity(contrast == .increased ? 0.4 : 0.055), lineWidth: 0.5)
            }
            .allowsHitTesting(false)
    }
}

struct IDockSelectionSurface: View {
    var cornerRadius: CGFloat = 14

    var body: some View {
        Color.clear
            .adaptiveGlassSurface(cornerRadius: cornerRadius,
                                  tint: Color.accentColor.opacity(0.16),
                                  isInteractive: true)
            .allowsHitTesting(false)
    }
}

struct IDockWordmark: View {
    var body: some View {
        HStack(spacing: 8) {
            Image(systemName: "antenna.radiowaves.left.and.right")
                .font(.system(size: 14, weight: .semibold))
                .foregroundStyle(Color.accentColor)
            Text(verbatim: IDockBrand.name)
                .font(.system(size: 13, weight: .semibold))
        }
        .accessibilityElement(children: .combine)
    }
}

struct IDockGroupBoxStyle: GroupBoxStyle {
    func makeBody(configuration: Configuration) -> some View {
        VStack(alignment: .leading, spacing: 16) {
            configuration.label.font(.headline)
            configuration.content
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .adaptiveTranslucentCard(cornerRadius: 20, padding: 18)
    }
}

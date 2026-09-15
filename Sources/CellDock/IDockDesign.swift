import AppKit
import SwiftUI

enum IDockBrand {
    static let name = "iDock Pro Max"
    static let releasesURL = URL(string: "https://github.com/vicekang/iDock-Pro-Max/releases")!
}

/// Keep legacy vibrancy out of the native sidebar's material hierarchy.
struct IDockWindowBackdrop: View {
    var body: some View {
        Color(nsColor: .windowBackgroundColor)
            .ignoresSafeArea()
            .allowsHitTesting(false)
    }
}

/// A quiet reading surface, distinct from the floating glass control layer.
struct IDockContentSurface: View {
    var body: some View {
        Color(nsColor: .windowBackgroundColor)
            .allowsHitTesting(false)
    }
}

struct IDockSelectionSurface: View {
    var cornerRadius: CGFloat = 8

    var body: some View {
        RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
            .fill(Color.accentColor.opacity(0.13))
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
        .adaptiveTranslucentCard(cornerRadius: 12, padding: 18)
        .accessibilityElement(children: .contain)
    }
}

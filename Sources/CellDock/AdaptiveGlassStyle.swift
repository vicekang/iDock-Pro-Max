import SwiftUI

enum AdaptiveGlassTreatment {
    case regular
    case clear
}

enum AdaptiveGlassButtonKind {
    case regular
    case prominent
    case accented
}

struct AdaptiveGlassBackdrop: View {
    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency
    let treatment: AdaptiveGlassTreatment

    init(treatment: AdaptiveGlassTreatment = .regular) {
        self.treatment = treatment
    }

    @ViewBuilder
    var body: some View {
        if reduceTransparency {
            Color(nsColor: .windowBackgroundColor)
        } else if #available(macOS 26.0, *) {
            switch treatment {
            case .regular:
                Rectangle()
                    .fill(Color.clear)
                    .glassEffect(.regular, in: Rectangle())
                    .overlay {
                        backdropGradient(whiteOpacity: 0.10, accentOpacity: 0.035)
                    }
            case .clear:
                Rectangle()
                    .fill(Color.clear)
                    .glassEffect(.clear, in: Rectangle())
                    .overlay {
                        backdropGradient(whiteOpacity: 0.055, accentOpacity: 0.018)
                    }
            }
        } else {
            Rectangle()
                .fill(.ultraThinMaterial)
        }
    }

    private func backdropGradient(
        whiteOpacity: Double,
        accentOpacity: Double
    ) -> some View {
        LinearGradient(
            colors: [
                Color.white.opacity(whiteOpacity),
                Color.clear,
                Color.accentColor.opacity(accentOpacity)
            ],
            startPoint: .topLeading,
            endPoint: .bottomTrailing
        )
        .allowsHitTesting(false)
    }
}

struct AdaptiveGlassContainer<Content: View>: View {
    private let spacing: CGFloat?
    private let content: Content

    init(spacing: CGFloat? = nil, @ViewBuilder content: () -> Content) {
        self.spacing = spacing
        self.content = content()
    }

    @ViewBuilder
    var body: some View {
        if #available(macOS 26.0, *) {
            GlassEffectContainer(spacing: spacing) {
                content
            }
        } else {
            content
        }
    }
}

struct AdaptiveGlassToggleStyle: ToggleStyle {
    func makeBody(configuration: Configuration) -> some View {
        // System switches honor labelsHidden, keyboard input and accessibility
        // while adopting the current macOS control material automatically.
        SwitchToggleStyle().makeBody(configuration: configuration)
    }
}

extension ToggleStyle where Self == AdaptiveGlassToggleStyle {
    static var adaptiveGlass: AdaptiveGlassToggleStyle { AdaptiveGlassToggleStyle() }
}

private struct AdaptiveGlassSurfaceModifier: ViewModifier {
    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency
    @Environment(\.colorSchemeContrast) private var contrast
    let cornerRadius: CGFloat
    let padding: CGFloat
    let treatment: AdaptiveGlassTreatment
    let tint: Color?
    let isInteractive: Bool

    @ViewBuilder
    func body(content: Content) -> some View {
        if reduceTransparency {
            let shape = RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
            content.padding(padding)
                .background {
                    shape.fill(Color(nsColor: .controlBackgroundColor))
                        .overlay { shape.fill(tint ?? .clear) }
                        .allowsHitTesting(false)
                }
                .overlay {
                    shape.strokeBorder(Color.primary.opacity(contrast == .increased ? 0.5 : 0.16), lineWidth: 1)
                        .allowsHitTesting(false)
                }
        } else if #available(macOS 26.0, *) {
            glassSurface(content: content)
        } else {
            let shape = RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
            content
                .padding(padding)
                .background {
                    ZStack {
                        switch treatment {
                        case .regular:
                            shape.fill(.regularMaterial)
                        case .clear:
                            shape.fill(.ultraThinMaterial)
                        }

                        if let tint {
                            shape.fill(tint)
                        }
                    }
                    .allowsHitTesting(false)
                }
                .overlay {
                    shape
                        .strokeBorder(Color.white.opacity(0.30), lineWidth: 0.5)
                        .allowsHitTesting(false)
                }
        }
    }

    @available(macOS 26.0, *)
    @ViewBuilder
    private func glassSurface(content: Content) -> some View {
        let shape = RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
        switch (treatment, tint) {
        case let (.regular, .some(tint)):
            content
                .padding(padding)
                .glassEffect(.regular.tint(tint).interactive(isInteractive), in: shape)
        case (.regular, .none):
            content
                .padding(padding)
                .glassEffect(.regular.interactive(isInteractive), in: shape)
        case let (.clear, .some(tint)):
            content
                .padding(padding)
                .glassEffect(.clear.tint(tint).interactive(isInteractive), in: shape)
        case (.clear, .none):
            content
                .padding(padding)
                .glassEffect(.clear.interactive(isInteractive), in: shape)
        }
    }
}

private struct AdaptiveConcentricGlassSurfaceModifier: ViewModifier {
    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency
    let minimumCornerRadius: CGFloat
    let padding: CGFloat
    let treatment: AdaptiveGlassTreatment
    let tint: Color?
    let isInteractive: Bool

    @ViewBuilder
    func body(content: Content) -> some View {
        if #available(macOS 26.0, *), !reduceTransparency {
            glassSurface(content: content)
        } else {
            content.modifier(
                AdaptiveGlassSurfaceModifier(
                    cornerRadius: minimumCornerRadius,
                    padding: padding,
                    treatment: treatment,
                    tint: tint,
                    isInteractive: isInteractive
                )
            )
        }
    }

    @available(macOS 26.0, *)
    @ViewBuilder
    private func glassSurface(content: Content) -> some View {
        #if CELLDOCK_LEGACY_GLASS_SDK
        let shape = RoundedRectangle(cornerRadius: minimumCornerRadius)
        #else
        let shape = ConcentricRectangle(
            corners: .concentric(minimum: .fixed(minimumCornerRadius)),
            isUniform: true
        )
        #endif
        switch (treatment, tint) {
        case let (.regular, .some(tint)):
            content
                .padding(padding)
                .glassEffect(.regular.tint(tint).interactive(isInteractive), in: shape)
        case (.regular, .none):
            content
                .padding(padding)
                .glassEffect(.regular.interactive(isInteractive), in: shape)
        case let (.clear, .some(tint)):
            content
                .padding(padding)
                .glassEffect(.clear.tint(tint).interactive(isInteractive), in: shape)
        case (.clear, .none):
            content
                .padding(padding)
                .glassEffect(.clear.interactive(isInteractive), in: shape)
        }
    }
}

private struct AdaptiveGlassButtonModifier: ViewModifier {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var isHovered = false

    let kind: AdaptiveGlassButtonKind

    @ViewBuilder
    func body(content: Content) -> some View {
        if #available(macOS 26.0, *) {
            switch kind {
            case .regular:
                content.buttonStyle(.glass)
            case .prominent:
                content.buttonStyle(.glassProminent)
            case .accented:
                #if CELLDOCK_LEGACY_GLASS_SDK
                content.buttonStyle(.glass).tint(Color.accentColor)
                #else
                content.buttonStyle(.glass(.regular.tint(Color.accentColor)))
                #endif
            }
        } else {
            switch kind {
            case .regular:
                hoverFeedback(content.buttonStyle(.bordered))
            case .prominent, .accented:
                hoverFeedback(content.buttonStyle(.borderedProminent))
            }
        }
    }

    private func hoverFeedback<Content: View>(_ content: Content) -> some View {
        content
            .scaleEffect(isHovered && !reduceMotion ? 1.025 : 1)
            .brightness(isHovered ? 0.045 : 0)
            .shadow(
                color: Color.black.opacity(isHovered ? 0.16 : 0),
                radius: isHovered ? 8 : 0,
                y: isHovered ? 3 : 0
            )
            .animation(.easeOut(duration: 0.13), value: isHovered)
            .onHover { hovering in
                isHovered = hovering
            }
    }
}

private struct AdaptiveTranslucentCardModifier: ViewModifier {
    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency
    @Environment(\.colorSchemeContrast) private var contrast

    let cornerRadius: CGFloat
    let padding: CGFloat

    func body(content: Content) -> some View {
        let shape = RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
        content
            .padding(padding)
            .background {
                shape.fill(
                    Color(nsColor: .controlBackgroundColor)
                        .opacity(reduceTransparency ? 1 : (colorScheme == .dark ? 0.75 : 1))
                )
            }
            .overlay {
                shape.strokeBorder(
                    Color.primary.opacity(contrast == .increased ? 0.4 : 0.045),
                    lineWidth: 0.6
                )
            }
    }
}

extension View {
    func adaptiveGlassSurface(
        cornerRadius: CGFloat,
        padding: CGFloat = 0,
        treatment: AdaptiveGlassTreatment = .regular,
        tint: Color? = nil,
        isInteractive: Bool = false
    ) -> some View {
        modifier(
            AdaptiveGlassSurfaceModifier(
                cornerRadius: cornerRadius,
                padding: padding,
                treatment: treatment,
                tint: tint,
                isInteractive: isInteractive
            )
        )
    }

    func adaptiveGlassCard(
        cornerRadius: CGFloat = 18,
        treatment: AdaptiveGlassTreatment = .regular
    ) -> some View {
        adaptiveGlassSurface(
            cornerRadius: cornerRadius,
            padding: 13,
            treatment: treatment
        )
    }

    func adaptiveConcentricGlassSurface(
        minimumCornerRadius: CGFloat,
        padding: CGFloat = 0,
        treatment: AdaptiveGlassTreatment = .regular,
        tint: Color? = nil,
        isInteractive: Bool = false
    ) -> some View {
        modifier(
            AdaptiveConcentricGlassSurfaceModifier(
                minimumCornerRadius: minimumCornerRadius,
                padding: padding,
                treatment: treatment,
                tint: tint,
                isInteractive: isInteractive
            )
        )
    }

    func adaptiveGlassButton(_ kind: AdaptiveGlassButtonKind = .regular) -> some View {
        modifier(AdaptiveGlassButtonModifier(kind: kind))
    }

    func adaptiveTranslucentCard(
        cornerRadius: CGFloat = 18,
        padding: CGFloat = 13
    ) -> some View {
        modifier(
            AdaptiveTranslucentCardModifier(
                cornerRadius: cornerRadius,
                padding: padding
            )
        )
    }
}

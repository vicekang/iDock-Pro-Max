import Foundation
import AppKit
import SwiftUI

enum CommunicationUI {
    static let railWidth: CGFloat = 76
    static let sidebarWidth: CGFloat = 280
    static let sidebarMinimumWidth: CGFloat = 260
    static let sidebarMaximumWidth: CGFloat = 420

    static func listTimestamp(_ date: Date, now: Date = Date()) -> String {
        let calendar = Calendar.current
        let timeFormatter = DateFormatter()
        timeFormatter.locale = AppLanguage.storedPreference.locale
        timeFormatter.timeStyle = .short
        let time = timeFormatter.string(from: date)
        if calendar.isDateInToday(date) { return time }
        if calendar.isDateInYesterday(date) { return L10n.tr("昨天") }
        let dateFormatter = DateFormatter()
        dateFormatter.locale = AppLanguage.storedPreference.locale
        dateFormatter.setLocalizedDateFormatFromTemplate("MMMd")
        return dateFormatter.string(from: date)
    }
}

/// Native split navigation supplies the floating Liquid Glass sidebar on
/// macOS 26. Do not place a legacy sidebar material underneath its content.
struct ResizableCommunicationSplit<Sidebar: View, Detail: View>: View {
    @Binding var sidebarWidth: CGFloat
    @State private var initialSidebarWidth: CGFloat
    private let sidebar: Sidebar
    private let detail: Detail

    init(
        sidebarWidth: Binding<CGFloat>,
        @ViewBuilder sidebar: () -> Sidebar,
        @ViewBuilder detail: () -> Detail
    ) {
        _sidebarWidth = sidebarWidth
        _initialSidebarWidth = State(initialValue: max(CommunicationUI.sidebarMinimumWidth, sidebarWidth.wrappedValue))
        self.sidebar = sidebar()
        self.detail = detail()
    }

    var body: some View {
        NavigationSplitView(columnVisibility: .constant(.all)) {
            sidebar
                .frame(
                    minWidth: CommunicationUI.sidebarMinimumWidth,
                    idealWidth: initialSidebarWidth,
                    maxWidth: CommunicationUI.sidebarMaximumWidth,
                    maxHeight: .infinity
                )
                .navigationSplitViewColumnWidth(
                    min: CommunicationUI.sidebarMinimumWidth,
                    ideal: initialSidebarWidth,
                    max: CommunicationUI.sidebarMaximumWidth
                )
                .background {
                    CommunicationSplitWidthObserver(width: $sidebarWidth)
                }
        } detail: {
            detail.frame(minWidth: 420, maxWidth: .infinity, maxHeight: .infinity)
        }
        .navigationSplitViewStyle(.balanced)
        .toolbar(removing: .sidebarToggle)
    }
}

/// Native pane widths include the system glass inset. Observe the split view,
/// rather than saving SwiftUI's narrower content measurement on every new page.
private struct CommunicationSplitWidthObserver: NSViewRepresentable {
    @Binding var width: CGFloat

    func makeNSView(context: Context) -> SplitWidthView {
        let view = SplitWidthView()
        view.preferredWidth = width
        view.onResize = { width = $0 }
        return view
    }

    func updateNSView(_ view: SplitWidthView, context: Context) {
        view.preferredWidth = width
        view.onResize = { width = $0 }
    }

    final class SplitWidthView: NSView {
        var preferredWidth: CGFloat = CommunicationUI.sidebarWidth
        var onResize: ((CGFloat) -> Void)?
        private weak var observedSplit: NSSplitView?
        private var observer: NSObjectProtocol?
        private var restoring = false

        override func hitTest(_ point: NSPoint) -> NSView? { nil }

        override func viewDidMoveToWindow() {
            super.viewDidMoveToWindow()
            guard window != nil else { return }
            DispatchQueue.main.async { [weak self] in self?.attach() }
        }

        private func attach() {
            var ancestor = superview
            while let view = ancestor {
                if let split = view as? NSSplitView, split.isVertical,
                   split.arrangedSubviews.count >= 2 {
                    guard observedSplit !== split else { return }
                    if let observer { NotificationCenter.default.removeObserver(observer) }
                    observedSplit = split
                    restoring = true
                    split.layoutSubtreeIfNeeded()
                    let available = max(CommunicationUI.sidebarMinimumWidth, split.bounds.width - 420 - split.dividerThickness)
                    let requested = min(CommunicationUI.sidebarMaximumWidth, available,
                                        max(CommunicationUI.sidebarMinimumWidth, preferredWidth))
                    split.setPosition(requested, ofDividerAt: 0)
                    observer = NotificationCenter.default.addObserver(
                        forName: NSSplitView.didResizeSubviewsNotification,
                        object: split, queue: .main
                    ) { [weak self] _ in
                        MainActor.assumeIsolated { self?.saveWidth() }
                    }
                    DispatchQueue.main.async { [weak self] in self?.restoring = false }
                    return
                }
                ancestor = view.superview
            }
        }

        private func saveWidth() {
            guard !restoring, let split = observedSplit,
                  split.window?.inLiveResize != true,
                  let pane = split.arrangedSubviews.first else { return }
            let measured = pane.frame.width
            guard measured >= CommunicationUI.sidebarMinimumWidth,
                  measured <= CommunicationUI.sidebarMaximumWidth,
                  abs(measured - preferredWidth) > 1 else { return }
            DispatchQueue.main.async { [weak self] in self?.onResize?(measured) }
        }

        deinit {
            if let observer { NotificationCenter.default.removeObserver(observer) }
        }
    }
}

private struct CommunicationSearchFieldModifier: ViewModifier {
    func body(content: Content) -> some View {
        content
            .textFieldStyle(.plain)
            .padding(.horizontal, 10)
            .frame(height: 32)
            .adaptiveGlassSurface(
                cornerRadius: 16,
                treatment: .clear,
                isInteractive: true
            )
    }
}

private struct CommunicationSidebarColumnModifier: ViewModifier {
    func body(content: Content) -> some View {
        content
            .padding(.top, 16)
            .padding(.bottom, 4)
    }
}

private struct CommunicationDetailColumnModifier: ViewModifier {
    func body(content: Content) -> some View {
        content
            .background { IDockContentSurface() }
    }
}

private struct CommunicationInitialListFocusModifier: ViewModifier {
    let focus: FocusState<Bool>.Binding

    func body(content: Content) -> some View {
        content
            .focused(focus)
            .onAppear {
                focus.wrappedValue = true
            }
    }
}

private struct CommunicationModuleFloatingSidebarModifier: ViewModifier {
    func body(content: Content) -> some View {
        content
            .safeAreaInset(edge: .bottom, spacing: 0) {
                CommunicationModuleFloatingCard()
                .padding(.horizontal, 12)
                .padding(.vertical, 12)
            }
    }
}

private struct CommunicationModuleFloatingCard: View {
    var body: some View {
        AdaptiveGlassContainer(spacing: 0) {
            CommunicationModuleStatusMenu {
                CommunicationWindowController.shared.showPhone(section: .sim)
            }
        }
        .accessibilityElement(children: .contain)
    }
}

extension View {
    /// Native List selection owns focus, active/inactive color and contrast.
    /// Keep only content insets here; a second fill produces a double outline.
    func communicationListRowInsets() -> some View {
        padding(.horizontal, 8)
            .padding(.vertical, 2)
    }

    func communicationSidebarMaterial() -> some View {
        self
    }

    func communicationSearchField() -> some View {
        modifier(CommunicationSearchFieldModifier())
    }

    func communicationSidebarColumnStyle() -> some View {
        modifier(CommunicationSidebarColumnModifier())
    }

    func communicationDetailColumnStyle() -> some View {
        modifier(CommunicationDetailColumnModifier())
    }

    func communicationModuleFloatingSidebar() -> some View {
        modifier(CommunicationModuleFloatingSidebarModifier())
    }

    /// Kept as the common hook for native communication list selection.
    func communicationEmphasizedSelection() -> some View {
        self
    }

    func communicationInitialListFocus(
        _ focus: FocusState<Bool>.Binding
    ) -> some View {
        modifier(CommunicationInitialListFocusModifier(focus: focus))
    }

    @ViewBuilder
    func communicationSidebarScrollEdgeEffect() -> some View {
        if #available(macOS 26.0, *) {
            scrollEdgeEffectStyle(.soft, for: .all)
        } else {
            self
        }
    }
}

struct CommunicationGlassTabs<Selection: Hashable>: View {
    let items: [(Selection, String)]
    @Binding var selection: Selection

    var body: some View {
        Picker("", selection: $selection) {
            ForEach(Array(items.enumerated()), id: \.offset) { _, item in
                Text(L10n.tr(item.1)).tag(item.0)
            }
        }
        .labelsHidden()
        .pickerStyle(.segmented)
        .controlSize(.regular)
    }
}

/// Compact, icon-only action used by the communication list headers.
/// Its filled tint and capsule shape match the dialer's primary call action.
struct CommunicationIconActionButton: View {
    let systemImage: String
    let accessibilityLabel: String
    var tint: Color = .accentColor
    var width: CGFloat = 44
    var height: CGFloat = 30
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Image(systemName: systemImage)
                .font(.system(size: 15, weight: .semibold))
        }
        .buttonStyle(
            CommunicationIconActionButtonStyle(
                width: width,
                height: height,
                tint: tint
            )
        )
        .help(accessibilityLabel)
        .accessibilityLabel(accessibilityLabel)
    }
}

private struct CommunicationIconActionButtonStyle: ButtonStyle {
    @Environment(\.isEnabled) private var isEnabled
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    let width: CGFloat
    let height: CGFloat
    let tint: Color

    func makeBody(configuration: Configuration) -> some View {
        let cornerRadius = height / 2
        let isPressed = configuration.isPressed && !reduceMotion

        configuration.label
            .foregroundStyle(.white)
            .frame(width: width, height: height)
            .contentShape(
                RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
            )
            .adaptiveGlassSurface(
                cornerRadius: cornerRadius,
                treatment: .regular,
                tint: tint.opacity(isEnabled ? 0.82 : 0.34),
                isInteractive: isEnabled
            )
            .scaleEffect(isPressed ? 0.96 : 1)
            .brightness(configuration.isPressed ? -0.04 : 0)
            .opacity(isEnabled ? 1 : 0.48)
            .animation(.easeOut(duration: 0.09), value: configuration.isPressed)
    }
}

struct CircularLiquidCallButton: View {
    let title: String
    let systemImage: String
    var tint: Color = .accentColor
    var selected = false
    var prominent = false
    var role: ButtonRole? = nil
    var isEnabled = true
    var diameter: CGFloat = 66
    var showsTitle = true
    let action: () -> Void

    var body: some View {
        Button(role: role, action: action) {
            VStack(spacing: 8) {
                Image(systemName: systemImage)
                    .font(.system(size: diameter * 0.32, weight: .semibold))
                    .foregroundStyle(
                        prominent ? Color.white : (selected ? tint : Color.primary)
                    )
                    .frame(width: diameter, height: diameter)
                    .background {
                        Circle()
                            .fill(semanticBaseFill)
                            .allowsHitTesting(false)
                    }
                    .adaptiveGlassSurface(
                        cornerRadius: diameter / 2,
                        treatment: prominent || selected ? .regular : .clear,
                        tint: controlTint,
                        isInteractive: isEnabled
                    )
                    .contentShape(Circle())

                if showsTitle {
                    Text(L10n.tr(title))
                        .font(.caption)
                        .foregroundStyle(.primary)
                        .lineLimit(1)
                }
            }
        }
        .buttonStyle(CircularLiquidCallPressStyle())
        .disabled(!isEnabled)
        .help(title)
        .frame(minWidth: diameter)
        .opacity(isEnabled ? 1 : 0.46)
        .accessibilityLabel(title)
        .accessibilityAddTraits(selected ? .isSelected : [])
    }

    private var controlTint: Color? {
        if prominent { return tint }
        if selected { return tint.opacity(0.18) }
        return nil
    }

    private var semanticBaseFill: Color {
        if prominent { return tint.opacity(0.68) }
        if selected { return tint.opacity(0.06) }
        return .clear
    }
}

private struct CircularLiquidCallPressStyle: ButtonStyle {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .scaleEffect(configuration.isPressed && !reduceMotion ? 0.95 : 1)
            .brightness(configuration.isPressed ? -0.035 : 0)
            .animation(.easeOut(duration: 0.09), value: configuration.isPressed)
    }
}

import AppKit
import SwiftUI

/// Colors of the settings window, taken from the "Настройки" artboards; sizes follow the home window.
enum SettingsStyle {
    static func primary(_ s: ColorScheme) -> Color { s == .dark ? Glass.hex(0xF5F5F7) : Glass.hex(0x1D1D1F) }
    /// Unselected segments, status text, folder path.
    static func secondary(_ s: ColorScheme) -> Color { s == .dark ? Glass.hex(0xB9BCCB) : Glass.hex(0x3C3C43) }
    /// The dim "· detail" after a row title, the clear-shortcut cross.
    static func detail(_ s: ColorScheme) -> Color { s == .dark ? Glass.hex(0x8E91A3) : Glass.hex(0x5A5F70) }
    static func header(_ s: ColorScheme) -> Color { s == .dark ? Glass.hex(0xB9BCCB) : Glass.hex(0x2C3E5C) }
    static func footer(_ s: ColorScheme) -> Color { s == .dark ? Glass.hex(0x9FA3B6) : Glass.hex(0x2C3346) }
    static func title(_ s: ColorScheme) -> Color { s == .dark ? Glass.hex(0xD6D8E2) : Glass.hex(0x2C2C30) }
    /// Switches that are on, the upload server, the main button.
    static func accent(_ s: ColorScheme) -> Color { s == .dark ? Glass.hex(0x3A6BFF) : Glass.hex(0x1F4F9A) }
    static func accentGlow(_ s: ColorScheme) -> Color { s == .dark ? Glass.hex(0x3A6BFF, 0.4) : Glass.hex(0x1F4F9A, 0.3) }
    /// Keyboard focus ring of fields.
    static func focus(_ s: ColorScheme) -> Color { s == .dark ? Glass.hex(0x5B8CFF) : Glass.hex(0x2F62E8) }
    static func divider(_ s: ColorScheme) -> Color { s == .dark ? .white.opacity(0.1) : Glass.hex(0x102A54, 0.12) }
    static let lightShadow = Glass.hex(0x102A54, 0.12)
    static let smallShadow = Glass.hex(0x102A54, 0.1)

    enum Icon {
        case blue, green, purple, orange, teal, red

        func color(_ s: ColorScheme) -> Color {
            let dark = s == .dark
            switch self {
            case .blue: return Glass.hex(dark ? 0x8FB4FF : 0x2F62E8)
            case .green: return Glass.hex(dark ? 0x6FE0A4 : 0x178A52)
            case .purple: return Glass.hex(dark ? 0xC7A6FF : 0x8A44D8)
            case .orange: return Glass.hex(dark ? 0xFFB27A : 0xE0661A)
            case .teal: return Glass.hex(dark ? 0x8FD3FF : 0x1F6FA8)
            case .red: return Glass.hex(dark ? 0xFF5A64 : 0xD70015)
            }
        }
    }
}

/// Uppercase caption, a glass card with the rows, and an optional note below it, 10 pt apart.
struct GlassSection<Content: View, Footer: View>: View {
    let title: String?
    var detail: String?
    var leading: CGFloat = 14
    var trailing: CGFloat = 14
    var footerLineHeight: CGFloat = 1.5
    @ViewBuilder let content: Content
    @ViewBuilder let footer: Footer
    @Environment(\.colorScheme) private var scheme

    init(_ title: String? = nil, detail: String? = nil, leading: CGFloat = 14, trailing: CGFloat = 14,
         footerLineHeight: CGFloat = 1.5, @ViewBuilder content: () -> Content,
         @ViewBuilder footer: () -> Footer = { EmptyView() }) {
        self.title = title
        self.detail = detail
        self.leading = leading
        self.trailing = trailing
        self.footerLineHeight = footerLineHeight
        self.content = content()
        self.footer = footer()
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            if let title {
                HStack(spacing: 0) {
                    Text((title + (detail == nil ? "" : " — ")).uppercased())
                        .tracking(0.7)
                        .foregroundStyle(SettingsStyle.header(scheme))
                    if let detail {
                        Text(detail).foregroundStyle(SettingsStyle.primary(scheme)).lineLimit(1)
                    }
                }
                .font(.system(size: 11.5, weight: .semibold))
                .padding(.leading, 4)
            }
            VStack(spacing: 0) { content }
                .padding(.leading, leading)
                .padding(.trailing, trailing)
                .glassCard(scheme)
            footer
                .font(.system(size: 11))
                .foregroundStyle(SettingsStyle.footer(scheme))
                // CSS-like line height; SF's natural line on 11 pt is about 13.1 pt.
                .lineSpacing(11 * footerLineHeight - 13.1)
                .fixedSize(horizontal: false, vertical: true)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.horizontal, 8)
        }
        // Captions sit 8 pt further from the block above than the 14 pt rhythm.
        .padding(.top, title == nil ? 0 : 6)
    }
}

extension View {
    /// Same glass as the home window's cards.
    func glassCard(_ scheme: ColorScheme, radius: CGFloat = 18) -> some View {
        let shape = RoundedRectangle(cornerRadius: radius, style: .continuous)
        return background(shape.fill(Glass.fill(scheme)))
            .overlay(shape.strokeBorder(Glass.border(scheme)).allowsHitTesting(false))
            .shadow(color: Glass.shadow, radius: 6, y: 3)
    }
}

/// Row icon in a 16 pt box.
struct SettingsIcon: View {
    let symbol: String
    let tint: SettingsStyle.Icon
    @Environment(\.colorScheme) private var scheme

    var body: some View {
        let color = tint.color(scheme)
        Group {
            switch symbol {
            case "record":
                Circle().strokeBorder(color, lineWidth: 1.7)
                    .overlay(Circle().fill(color).frame(width: 6, height: 6))
                    .frame(width: 16, height: 16)
            case "app":
                Image(nsImage: NSApp.applicationIconImage).resizable().frame(width: 20, height: 20).padding(-2)
            default:
                Image(systemName: symbol).font(.system(size: 13.5, weight: .medium)).foregroundStyle(color)
            }
        }
        .frame(width: 16, height: 16)
    }
}

/// One line of a card: optional icon, title with an optional dim detail, trailing control.
struct GlassRow<Trailing: View>: View {
    var symbol: String?
    var tint: SettingsStyle.Icon = .blue
    let title: String
    var detail: String?
    var height: CGFloat = 44
    var showsDivider = true
    @ViewBuilder let trailing: Trailing
    @Environment(\.colorScheme) private var scheme

    var body: some View {
        HStack(spacing: 10) {
            if let symbol { SettingsIcon(symbol: symbol, tint: tint) }
            (Text(title).font(.system(size: 13, weight: .medium)).foregroundColor(SettingsStyle.primary(scheme))
             + Text(detail.map { " · \($0)" } ?? "").font(.system(size: 13)).foregroundColor(SettingsStyle.detail(scheme)))
                .lineLimit(1)
                .layoutPriority(1)
            Spacer(minLength: 0)
            trailing
        }
        .frame(minHeight: height)
        .overlay(alignment: .bottom) {
            if showsDivider { Rectangle().fill(SettingsStyle.divider(scheme)).frame(height: 0.5) }
        }
    }
}

/// 38 × 22 switch with an 18 pt knob.
struct GlassSwitch: View {
    @Binding var isOn: Bool
    @Environment(\.colorScheme) private var scheme

    var body: some View {
        let dark = scheme == .dark
        Button { isOn.toggle() } label: {
            ZStack(alignment: isOn ? .trailing : .leading) {
                Capsule().fill(isOn ? SettingsStyle.accent(scheme)
                                    : (dark ? Color.white.opacity(0.12) : Glass.hex(0x102A54, 0.18)))
                    .overlay(Capsule().strokeBorder(dark && !isOn ? Color.white.opacity(0.16) : .clear, lineWidth: 0.5))
                Circle()
                    .fill(dark && !isOn ? Glass.hex(0xD6D8E2) : .white)
                    .frame(width: 18, height: 18)
                    .shadow(color: .black.opacity(0.3), radius: 1.5, y: 1)
                    .padding(2)
            }
            .frame(width: 38, height: 22)
            .shadow(color: isOn && dark ? Glass.hex(0x3A6BFF, 0.45) : .clear, radius: 6)
            .contentShape(Capsule())
        }
        .buttonStyle(.hand(.plain))
        .animation(.spring(duration: 0.22), value: isOn)
    }
}

/// Segmented picker: a sunken track with the chosen option raised.
struct GlassSegmented<Value: Hashable>: View {
    enum Kind {
        /// Settings tabs: 26 pt items, 16 pt side padding, a lighter track.
        case tabs
        /// Pickers inside rows: 23 pt items.
        case row
    }

    let options: [Value]
    @Binding var selection: Value
    let title: (Value) -> String
    var kind: Kind = .row
    var itemWidth: CGFloat?
    @Environment(\.colorScheme) private var scheme

    var body: some View {
        let dark = scheme == .dark
        let tabs = kind == .tabs
        let itemRadius: CGFloat = tabs ? 12 : 9
        let trackRadius: CGFloat = tabs ? 15 : 11
        HStack(spacing: 0) {
            ForEach(options, id: \.self) { option in
                let selected = option == selection
                let shape = RoundedRectangle(cornerRadius: itemRadius, style: .continuous)
                Button { selection = option } label: {
                    Text(title(option))
                        .font(.system(size: tabs ? 12.5 : 12, weight: selected ? .semibold : .medium))
                        .foregroundStyle(selected ? SettingsStyle.primary(scheme) : SettingsStyle.secondary(scheme))
                        .lineLimit(1)
                        .fixedSize()
                        .padding(.horizontal, itemWidth == nil ? (tabs ? 16 : 10) : 0)
                        .frame(width: itemWidth, height: tabs ? 26 : 23)
                        .background {
                            if selected {
                                shape.fill(dark ? Color.white.opacity(0.16) : .white)
                                    .overlay(shape.strokeBorder(dark ? Color.white.opacity(0.2) : .clear, lineWidth: 0.5))
                                    .shadow(color: dark ? (tabs ? .black.opacity(0.3) : .clear) : Glass.hex(0x102A54, 0.15),
                                            radius: tabs ? 4 : 2, y: tabs ? 2 : 1)
                            }
                        }
                        .contentShape(shape)
                }
                .buttonStyle(.hand(.plain))
            }
        }
        .padding(tabs ? 3 : 2.5)
        .background(RoundedRectangle(cornerRadius: trackRadius, style: .continuous)
            .fill(dark ? Color.white.opacity(0.06) : (tabs ? Color.white.opacity(0.4) : Glass.hex(0x102A54, 0.07))))
        .overlay(RoundedRectangle(cornerRadius: trackRadius, style: .continuous)
            .strokeBorder(dark ? Color.white.opacity(tabs ? 0.14 : 0.12) : Color.white.opacity(0.6), lineWidth: 0.5)
            .allowsHitTesting(false))
        .animation(.spring(duration: 0.2), value: selection)
    }
}

/// 28 pt text field sunk into the card, with a focus ring (a halo in light, a glow in dark).
struct GlassField: View {
    let placeholder: String
    @Binding var text: String
    var secure = false
    var width: CGFloat = 240
    @Environment(\.colorScheme) private var scheme
    @FocusState private var focused: Bool

    var body: some View {
        let dark = scheme == .dark
        let shape = RoundedRectangle(cornerRadius: 10, style: .continuous)
        let fill: Color = dark ? (focused ? Glass.hex(0x3A6BFF, 0.1) : Color.black.opacity(0.12))
                               : (focused ? Color.white.opacity(0.6) : Glass.hex(0x102A54, 0.05))
        Group {
            if secure {
                SecureField("", text: $text, prompt: prompt)
            } else {
                TextField("", text: $text, prompt: prompt)
            }
        }
        .textFieldStyle(.plain)
        .focused($focused)
        .font(.system(size: 13, weight: .medium))
        .foregroundStyle(SettingsStyle.primary(scheme))
        .padding(.horizontal, 11)
        .frame(width: width, height: 28)
        .background(shape.fill(fill))
        .overlay(InsetShadow(radius: 10, shade: dark ? Color.black.opacity(0.35) : Glass.hex(0x102A54, 0.14),
                             highlight: dark ? Color.white.opacity(0.14) : Color.white.opacity(0.8))
            .allowsHitTesting(false))
        .overlay(shape.strokeBorder(focused ? (dark ? Glass.hex(0x5B8CFF, 0.7) : Glass.hex(0x2F62E8, 0.6)) : .clear,
                                    lineWidth: 1).allowsHitTesting(false))
        .background(shape.inset(by: -3).fill(focused && !dark ? Glass.hex(0x2F62E8, 0.14) : .clear))
        .shadow(color: focused && dark ? Glass.hex(0x3A6BFF, 0.35) : .clear, radius: 7)
        .animation(.easeOut(duration: 0.15), value: focused)
    }

    private var prompt: Text {
        Text(placeholder).foregroundColor(SettingsStyle.detail(scheme))
    }
}

/// Soft shade along the top inner edge and a hairline highlight along the bottom one
/// (CSS `inset 0 1px 2px <shade>, inset 0 -0.5px 0 <highlight>`).
private struct InsetShadow: View {
    let radius: CGFloat
    let shade: Color
    let highlight: Color

    var body: some View {
        let shape = RoundedRectangle(cornerRadius: radius, style: .continuous)
        ZStack {
            shape.strokeBorder(LinearGradient(colors: [shade, .clear],
                                              startPoint: .top, endPoint: .init(x: 0.5, y: 0.14)), lineWidth: 1.5)
                .blur(radius: 0.6)
            shape.strokeBorder(LinearGradient(colors: [.clear, highlight],
                                              startPoint: .init(x: 0.5, y: 0.9), endPoint: .bottom), lineWidth: 0.5)
        }
        .clipShape(shape)
    }
}

/// Secondary capsule button: "Choose…" (26 pt) and "Restore defaults" (30 pt, card-like).
struct GlassButton: View {
    let title: String
    var symbol: String?
    var large = false
    let action: () -> Void
    @Environment(\.colorScheme) private var scheme
    @State private var hovering = false

    var body: some View {
        let dark = scheme == .dark
        let base = large ? 0.6 : 0.7
        Button(action: action) {
            HStack(spacing: 6) {
                if let symbol { Image(systemName: symbol).font(.system(size: 11.5, weight: .semibold)) }
                Text(title).font(.system(size: 12, weight: .medium))
            }
            .foregroundStyle(SettingsStyle.primary(scheme))
            .padding(.horizontal, large ? 14 : 12)
            .frame(height: large ? 30 : 26)
            .background(Capsule().fill(dark ? Color.white.opacity(hovering ? 0.14 : 0.08)
                                            : Color.white.opacity(hovering ? 0.85 : base)))
            .overlay(Capsule().strokeBorder(dark ? Color.white.opacity(0.16) : Color.white.opacity(base), lineWidth: 0.5))
            .shadow(color: dark ? .clear : (large ? SettingsStyle.lightShadow : SettingsStyle.smallShadow),
                    radius: large ? 11 : 1.5, y: large ? 8 : 1)
            .contentShape(Capsule())
        }
        .buttonStyle(.hand(.plain))
        .onHover { hovering = $0 }
    }
}

/// Filled accent capsule for the main action of a card.
struct GlassPrimaryButton: View {
    let title: String
    let action: () -> Void
    @Environment(\.colorScheme) private var scheme
    @Environment(\.isEnabled) private var isEnabled

    var body: some View {
        Button(action: action) {
            Text(title)
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(.white)
                .padding(.horizontal, 14)
                .frame(height: 27)
                .background(Capsule().fill(SettingsStyle.accent(scheme)))
                .shadow(color: SettingsStyle.accentGlow(scheme), radius: 5, y: 3)
                .opacity(isEnabled ? 1 : 0.45)
                .contentShape(Capsule())
        }
        .buttonStyle(.hand(.plain))
    }
}

/// 28 × 24 glass button, used for adding and removing servers.
struct GlassIconButton: View {
    let symbol: String
    let help: String
    let action: () -> Void
    @Environment(\.colorScheme) private var scheme
    @Environment(\.isEnabled) private var isEnabled

    var body: some View {
        let dark = scheme == .dark
        let shape = RoundedRectangle(cornerRadius: 8, style: .continuous)
        Button(action: action) {
            Image(systemName: symbol)
                .font(.system(size: 11.5, weight: .semibold))
                .foregroundStyle(SettingsStyle.primary(scheme))
                .frame(width: 28, height: 24)
                .background(shape.fill(dark ? Color.white.opacity(0.08) : Color.white.opacity(0.7)))
                .overlay(shape.strokeBorder(dark ? Color.white.opacity(0.16) : Color.white.opacity(0.7), lineWidth: 0.5))
                .shadow(color: dark ? .clear : SettingsStyle.smallShadow, radius: 1.5, y: 1)
                .opacity(isEnabled ? 1 : 0.45)
                .contentShape(shape)
        }
        .buttonStyle(.hand(.plain))
        .help(help)
    }
}

/// Sends scroll-wheel events straight to the scroll view under the pointer. AppKit otherwise
/// hit-tests the window for every wheel event, and in a long SwiftUI form that walks every control
/// twice (the hosting view, then the scroll view's document) — most of the CPU spent while scrolling.
final class ScrollRoutingWindow: NSWindow {
    private weak var scrollView: NSScrollView?

    override func sendEvent(_ event: NSEvent) {
        if event.type == .scrollWheel, let scroll = scrollView ?? contentView.flatMap(Self.findScrollView) {
            scrollView = scroll
            if scroll.bounds.contains(scroll.convert(event.locationInWindow, from: nil)) {
                scroll.scrollWheel(with: event)
                return
            }
        }
        super.sendEvent(event)
    }

    private static func findScrollView(in view: NSView) -> NSScrollView? {
        for sub in view.subviews {
            if let scroll = sub as? NSScrollView { return scroll }
            if let found = findScrollView(in: sub) { return found }
        }
        return nil
    }
}

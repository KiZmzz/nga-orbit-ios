import SwiftUI
import UIKit
import Foundation

/// User-facing appearance choice. The default follows the iPhone setting.
enum AppearancePreference: String, CaseIterable, Identifiable {
    case system, light, dark
    var id: String { rawValue }
    var title: String {
        switch self { case .system: "跟随系统"; case .light: "浅色"; case .dark: "深色" }
    }
    var colorScheme: ColorScheme? {
        switch self { case .system: nil; case .light: .light; case .dark: .dark }
    }
}

/// "版块星河" design tokens.
///
/// Every board is its own world. On the home screen the user's boards are rendered as a
/// constellation — each a "star" card carrying a stable colour derived from its `fid`.
/// The brand teal threads the whole app as the anchor; everything else stays quiet so the
/// constellation is the one memorable thing. Light and dark are both supported through
/// adaptive colors resolved from the selected or system trait collection.
enum AppTheme {

    // MARK: Brand anchor

    /// NGA brand teal. Used for primary actions and the connection hero.
    static let brand = adaptive(
        light: c(0x08, 0x7F, 0x8C),
        dark: c(0x2E, 0xB4, 0xA9)
    )

    /// A deeper teal for gradients / pressed states.
    static let brandDeep = adaptive(
        light: c(0x06, 0x5F, 0x6B),
        dark: c(0x18, 0x7E, 0x78)
    )

    // MARK: Surfaces

    /// Page canvas — a warm paper in light, deep ink in dark. Not stark white.
    static let page = adaptive(
        light: c(0xF4, 0xF2, 0xEC),
        dark: c(0x10, 0x17, 0x1A)
    )

    /// Card / surface fill.
    static let card = adaptive(
        light: c(0xFF, 0xFF, 0xFF),
        dark: c(0x1A, 0x23, 0x27)
    )

    /// A slightly recessed surface for quiet inner chips.
    static let cardSoft = adaptive(
        light: c(0xEC, 0xEA, 0xE2),
        dark: c(0x22, 0x2D, 0x31)
    )

    // MARK: Labels

    /// Primary ink — a teal-tinted near-black in light, near-white in dark.
    static let ink = adaptive(
        light: c(0x15, 0x29, 0x2D),
        dark: c(0xE6, 0xED, 0xEA)
    )

    /// Secondary text.
    static let inkSoft = adaptive(
        light: c(0x5D, 0x6F, 0x72),
        dark: c(0x90, 0xA1, 0xA0)
    )

    /// Hairline separators.
    static let line = adaptive(
        light: c(0xE0, 0xDC, 0xD0),
        dark: c(0x28, 0x33, 0x38)
    )

    // MARK: Status accents

    /// Connected / logged-in.
    static let online = adaptive(light: c(0x3F, 0xB2, 0x7A), dark: c(0x4F, 0xC9, 0x8B))
    /// Needs attention (verification, network).
    static let alert = adaptive(light: c(0xF0, 0xA0, 0x3C), dark: c(0xF4, 0xB4, 0x54))

    /// Warm editorial accent reserved for forum state, selected filters and reader actions.
    /// It deliberately differs from the product-wide teal, so reading screens have their own rhythm.
    static let forumAccent = adaptive(light: c(0xC9, 0x72, 0x13), dark: c(0xFF, 0xB3, 0x4C))
    static let forumAccentSoft = forumAccent.opacity(0.16)
    static let quietChrome = adaptive(light: c(0x5C, 0x70, 0x89), dark: c(0xA8, 0xB7, 0xCC))

    // MARK: Board "star" colours

    /// Curated constellation palette. Each entry pairs a light and dark tone.
    private static let starPalette: [(light: UIColor, dark: UIColor)] = [
        (c(0x2F, 0xB4, 0x9B), c(0x3B, 0xC9, 0xAE)), // emerald
        (c(0xE0, 0xA0, 0x3C), c(0xF0, 0xB3, 0x54)), // amber
        (c(0xE5, 0x62, 0x5A), c(0xF0, 0x7A, 0x6E)), // coral
        (c(0x8B, 0x7B, 0xE8), c(0xA3, 0x9A, 0xF2)), // violet
        (c(0x4A, 0x9F, 0xE8), c(0x6B, 0xB4, 0xF5)), // sky
        (c(0xE0, 0x7A, 0x9B), c(0xF0, 0x8C, 0xAE)), // rose
        (c(0x5F, 0x6E, 0x7A), c(0x8A, 0x9A, 0xA6)), // slate
        (c(0xA9, 0xBB, 0x3A), c(0xC2, 0xD3, 0x55)), // lime
    ]

    /// Stable "star" colour for a board, derived deterministically from its `fid`.
    /// Same fid always maps to the same colour; neighbouring fids spread across the palette.
    static func starColor(for id: Int) -> Color {
        let index = Int(id.magnitude % UInt(starPalette.count))
        let pair = starPalette[index]
        return adaptive(light: pair.light, dark: pair.dark)
    }

    /// The board's tinted surface — a soft wash of its star colour.
    static func starWash(for id: Int) -> Color { starColor(for: id).opacity(0.14) }

    /// The board's icon image on NGA's CDN; falls back to a coloured orb when it fails.
    static func boardIconURL(for id: Int) -> URL {
        URL(string: "https://img4.nga.cn/proxy/cache_attach/ficon/\(id)u.png")!
    }

    /// Match board names to bundled editorial artwork. These are thematic rather
    /// than decorative: unrecognised boards keep their own colour identity.
    static func boardArtworkName(for boardName: String?) -> String? {
        guard let name = boardName else { return nil }
        if ["黑锋", "死亡骑士", "鲜血专精", "冰霜专精", "邪恶专精"].contains(where: name.contains) {
            return "BoardDeathKnight"
        }
        if name.contains("伊利达雷") || name.contains("恶魔猎手") { return "BoardDemonHunter" }
        if name.contains("论坛开发") { return "BoardDevelopment" }
        if ["猎手大厅", "猎人大厅", "猎人区"].contains(where: name.contains) { return "BoardHunter" }
        if name.contains("圣光") || name.contains("圣骑士") { return "BoardPaladin" }
        if name.contains("晴风村") { return "BoardVillage" }
        if name.contains("艾泽拉斯议事厅") || name == "魔兽世界" {
            return "BoardAzeroth"
        }
        return nil
    }

    /// Resolve a copied bundle resource by path instead of relying on the asset
    /// catalogue name lookup. This also works for PNGs compressed by CopyPNGFile.
    static func bundledArtwork(named name: String) -> UIImage? {
        guard let path = Bundle.main.path(forResource: name, ofType: "png") else { return nil }
        return UIImage(contentsOfFile: path)
    }

    static func boardArtwork(for boardName: String?) -> UIImage? {
        guard let name = boardArtworkName(for: boardName) else { return nil }
        return bundledArtwork(named: name)
    }

    /// A short "time ago" label for post/topic timestamps.
    static func timeAgo(_ date: Date) -> String {
        let seconds = Date().timeIntervalSince(date)
        if seconds < 60 { return "刚刚" }
        if seconds < 3600 { return "\(Int(seconds / 60)) 分钟前" }
        if seconds < 86400 { return "\(Int(seconds / 3600)) 小时前" }
        if seconds < 86400 * 7 { return "\(Int(seconds / 86400)) 天前" }
        return date.formatted(.dateTime.month().day())
    }

    static func postTime(_ date: Date) -> String {
        date.formatted(.dateTime.year().month(.twoDigits).day(.twoDigits).hour(.twoDigits(amPM: .omitted)).minute(.twoDigits))
    }

    /// A deterministic accent colour for a name (author avatar).
    static func color(for name: String) -> Color {
        let seed = name.unicodeScalars.reduce(0) { $0 + Int($1.value) }
        return starColor(for: seed)
    }

    /// Initial character for an avatar orb.
    static func initial(_ name: String) -> String {
        name.trimmingCharacters(in: .whitespaces).first.map(String.init) ?? "?"
    }

    // MARK: Geometry

    static let radiusCard: CGFloat = 20
    static let radiusSmall: CGFloat = 14
    static let pad: CGFloat = 16

    // MARK: Glass scene

    /// Backdrop gradient — the frosted panels blur this, which is what makes them read as glass.
    static let sceneTop = adaptive(light: c(0xEC, 0xF3, 0xF0), dark: c(0x0C, 0x18, 0x26))
    static let sceneBottom = adaptive(light: c(0xD7, 0xE5, 0xE3), dark: c(0x08, 0x11, 0x1B))
    static let scene = LinearGradient(colors: [sceneTop, sceneBottom], startPoint: .top, endPoint: .bottom)

    /// Low-contrast atmospheric light used behind the glass. It gives the
    /// material something to refract without competing with forum content.
    static let oceanGlow = adaptive(
        light: c(0x5B, 0xB8, 0xAF).withAlphaComponent(0.24),
        dark: c(0x1D, 0x87, 0x82).withAlphaComponent(0.30)
    )
    static let amberGlow = adaptive(
        light: c(0xF0, 0xB4, 0x61).withAlphaComponent(0.18),
        dark: c(0xD3, 0x8D, 0x3D).withAlphaComponent(0.16)
    )

    /// Glass panel fill + hairline, tuned per appearance.
    static let glassFill = adaptive(light: UIColor(white: 1, alpha: 0.46), dark: c(0x16, 0x24, 0x34).withAlphaComponent(0.86))
    static let glassStroke = adaptive(light: UIColor(white: 1, alpha: 0.65), dark: c(0x30, 0x42, 0x58).withAlphaComponent(0.84))

    // MARK: Helpers

    private static func c(_ r: CGFloat, _ g: CGFloat, _ b: CGFloat) -> UIColor {
        UIColor(red: r / 255, green: g / 255, blue: b / 255, alpha: 1)
    }

    /// A color that adapts to the system light/dark appearance.
    private static func adaptive(light: UIColor, dark: UIColor) -> Color {
        Color(uiColor: UIColor { traits in traits.userInterfaceStyle == .dark ? dark : light })
    }
}

// MARK: - Page canvas helper

extension View {
    /// Set the page canvas behind a scroll view so the navy/paper shows through.
    func pageCanvas() -> some View {
        background(AppTheme.page.ignoresSafeArea())
    }

    /// Render the glass scene (a soft gradient) as the root backdrop, so frosted panels show.
    func sceneCanvas() -> some View {
        background {
            ZStack {
                AppTheme.scene
                Circle()
                    .fill(AppTheme.oceanGlow)
                    .frame(width: 330, height: 330)
                    .blur(radius: 72)
                    .offset(x: -150, y: -280)
                Circle()
                    .fill(AppTheme.amberGlow)
                    .frame(width: 260, height: 260)
                    .blur(radius: 78)
                    .offset(x: 180, y: 310)
            }
            .ignoresSafeArea()
        }
    }

    /// A frosted glass surface: translucent material, a hairline border and a light sheen.
    /// Clipped to the rounded shape so inner content (icons, buttons) never bulges past the edges.
    func glassSurface(radius: CGFloat = 22, fill: Color? = nil) -> some View {
        let fill = fill ?? AppTheme.glassFill
        return self
            .background(
                ZStack {
                    RoundedRectangle(cornerRadius: radius, style: .continuous).fill(.ultraThinMaterial)
                    RoundedRectangle(cornerRadius: radius, style: .continuous).fill(fill)
                    // Specular sheen running top-left to centre — the "liquid" highlight.
                    LinearGradient(colors: [.white.opacity(0.22), .clear],
                                   startPoint: .topLeading, endPoint: .center)
                        .clipShape(RoundedRectangle(cornerRadius: radius, style: .continuous))
                }
            )
            .clipShape(RoundedRectangle(cornerRadius: radius, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: radius, style: .continuous)
                    .stroke(AppTheme.glassStroke, lineWidth: 1)
            )
            .shadow(color: Color.black.opacity(0.07), radius: 16, x: 0, y: 8)
    }

}

/// A circular avatar with a deterministic colour and an initial.
struct AvatarCircle: View {
    let name: String
    var size: CGFloat = 42
    var body: some View {
        let color = AppTheme.color(for: name)
        ZStack {
            Circle().fill(color.opacity(0.18))
            Text(AppTheme.initial(name))
                .font(.system(size: max(13, size * 0.4), weight: .bold))
                .foregroundStyle(color)
        }
        .frame(width: size, height: size)
    }
}

/// An avatar: the real user image when available, otherwise a coloured initial circle.
struct AvatarView: View {
    let url: URL?
    let name: String
    var size: CGFloat = 42
    var body: some View {
        if let url {
            AsyncImage(url: url) { phase in
                if let img = phase.image {
                    img.resizable().scaledToFill().frame(width: size, height: size).clipShape(Circle())
                } else {
                    AvatarCircle(name: name, size: size)
                }
            }
            .id(url.absoluteString)
        } else {
            AvatarCircle(name: name, size: size)
        }
    }
}

//
//  AppSettings.swift
//  ZStream
//
//  Created by Francesco Macaluso on 7/15/26.
//

import SwiftUI

/// Users preferences that affect API calls
final class AppSettings: ObservableObject {
    @Published var locale: String = "en-US"
    @Published var kidMode: Bool = false

    /// The selected app theme, persisted by id.
    @Published var themeID: String {
        didSet { UserDefaults.standard.set(themeID, forKey: Self.themeKey) }
    }

    /// User-preferred order (by SourceInfo.id) to try sources in. Sources not
    /// listed here (e.g. newly added ones) are tried last, in catalog order.
    @Published var sourceOrder: [String] {
        didSet { UserDefaults.standard.set(sourceOrder, forKey: Self.sourceOrderKey) }
    }

    /// When true, the player asks the user which source to use every time
    /// instead of walking the source order automatically.
    @Published var manualSourceSelection: Bool {
        didSet { UserDefaults.standard.set(manualSourceSelection, forKey: Self.manualSourceSelectionKey) }
    }

    /// When true, whichever source last worked for a given title is tried
    /// first, ahead of `sourceOrder`.
    @Published var prioritizeLastUsedSource: Bool {
        didSet { UserDefaults.standard.set(prioritizeLastUsedSource, forKey: Self.prioritizeLastUsedSourceKey) }
    }

    private static let themeKey = "app.theme.id"
    private static let sourceOrderKey = "app.source.order"
    private static let manualSourceSelectionKey = "app.source.manualSelection"
    private static let prioritizeLastUsedSourceKey = "app.source.prioritizeLastUsed"

    init() {
        themeID = UserDefaults.standard.string(forKey: Self.themeKey) ?? ThemeCatalog.default.id
        sourceOrder = UserDefaults.standard.array(forKey: Self.sourceOrderKey) as? [String] ?? []
        manualSourceSelection = UserDefaults.standard.bool(forKey: Self.manualSourceSelectionKey)
        prioritizeLastUsedSource = UserDefaults.standard.bool(forKey: Self.prioritizeLastUsedSourceKey)
    }

    var theme: AppTheme { ThemeCatalog.theme(id: themeID) }
}

/// A visual theme: an accent (primary) color plus a two-stop background gradient
/// that tints the whole app, not just the hero.
struct AppTheme: Identifiable, Equatable {
    let id: String
    let name: String
    let accent: Color
    let backgroundTop: Color
    let backgroundBottom: Color

    var backgroundGradient: LinearGradient {
        LinearGradient(
            colors: [backgroundTop, backgroundBottom],
            startPoint: .top,
            endPoint: .bottom
        )
    }
}

enum ThemeCatalog {
    static let indigo = AppTheme(
        id: "indigo",
        name: "Indigo",
        accent: Color(red: 0.36, green: 0.36, blue: 0.92),
        backgroundTop: Color(red: 0.075, green: 0.086, blue: 0.180),
        backgroundBottom: Color(red: 0.020, green: 0.024, blue: 0.055)
    )

    static let midnight = AppTheme(
        id: "midnight",
        name: "Midnight",
        accent: Color(red: 0.23, green: 0.51, blue: 0.96),
        backgroundTop: Color(red: 0.043, green: 0.086, blue: 0.165),
        backgroundBottom: Color(red: 0.008, green: 0.024, blue: 0.055)
    )

    static let crimson = AppTheme(
        id: "crimson",
        name: "Crimson",
        accent: Color(red: 0.90, green: 0.28, blue: 0.30),
        backgroundTop: Color(red: 0.145, green: 0.055, blue: 0.075),
        backgroundBottom: Color(red: 0.055, green: 0.016, blue: 0.024)
    )

    static let emerald = AppTheme(
        id: "emerald",
        name: "Emerald",
        accent: Color(red: 0.06, green: 0.72, blue: 0.51),
        backgroundTop: Color(red: 0.035, green: 0.110, blue: 0.086),
        backgroundBottom: Color(red: 0.010, green: 0.039, blue: 0.031)
    )

    static let sunset = AppTheme(
        id: "sunset",
        name: "Sunset",
        accent: Color(red: 0.98, green: 0.45, blue: 0.09),
        backgroundTop: Color(red: 0.145, green: 0.075, blue: 0.055),
        backgroundBottom: Color(red: 0.055, green: 0.024, blue: 0.020)
    )

    static let graphite = AppTheme(
        id: "graphite",
        name: "Graphite",
        accent: Color(red: 0.60, green: 0.62, blue: 0.68),
        backgroundTop: Color(red: 0.105, green: 0.110, blue: 0.125),
        backgroundBottom: Color(red: 0.024, green: 0.024, blue: 0.031)
    )

    static let all: [AppTheme] = [indigo, midnight, crimson, emerald, sunset, graphite]

    static let `default` = indigo

    static func theme(id: String) -> AppTheme {
        all.first { $0.id == id } ?? `default`
    }
}

/// The app's ambient background: a dark base with a few soft, heavily-blurred
/// radial "blobs" of the theme's accent/tint colors. Because it's a single
/// surface, any view placed in front can dissolve into it seamlessly.
struct ThemeBackground: View {
    let theme: AppTheme
    var blurRadius: CGFloat = 70

    var body: some View {
        GeometryReader { geo in
            let w = geo.size.width
            let h = geo.size.height
            ZStack {
                theme.backgroundBottom

                blob(theme.accent.opacity(0.38), diameter: w * 1.05, x: w * 0.18, y: h * 0.10)
                blob(theme.backgroundTop, diameter: w * 1.25, x: w * 0.92, y: h * 0.24)
                blob(theme.accent.opacity(0.22), diameter: w * 0.95, x: w * 0.80, y: h * 0.92)
                blob(theme.backgroundTop.opacity(0.9), diameter: w * 0.9, x: w * 0.10, y: h * 0.75)
            }
            .blur(radius: blurRadius)
            .drawingGroup()
        }
        .ignoresSafeArea()
    }

    private func blob(_ color: Color, diameter: CGFloat, x: CGFloat, y: CGFloat) -> some View {
        Circle()
            .fill(
                RadialGradient(
                    colors: [color, color.opacity(0)],
                    center: .center,
                    startRadius: 0,
                    endRadius: diameter / 2
                )
            )
            .frame(width: diameter, height: diameter)
            .position(x: x, y: y)
    }
}

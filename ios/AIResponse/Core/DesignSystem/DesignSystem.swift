import SwiftUI
import UIKit

enum DS {
    enum ColorToken {
        static let primary = Color(hex: "#4E49E7")
        static let primaryPressed = Color(hex: "#433ED0")
        static let primarySoft = dynamicColor(light: "#EEF0FF", dark: "#20285A")
        static let aiAccent = Color(hex: "#22C7E8")

        static let canvas = dynamicColor(light: "#F7F8FC", dark: "#0F1322")
        static let surface = dynamicColor(light: "#FFFFFF", dark: "#151B2E")
        static let elevated = dynamicColor(light: "#FCFCFE", dark: "#1A2239")

        static let textPrimary = dynamicColor(light: "#151A2D", dark: "#F2F5FF")
        static let textSecondary = dynamicColor(light: "#5B647B", dark: "#B4BDD3")
        static let textTertiary = dynamicColor(light: "#8B94A8", dark: "#8F98B2")

        static let border = dynamicColor(light: "#E7EAF2", dark: "#27304A")
        static let success = Color(hex: "#1FA971")
        static let warning = Color(hex: "#D79A2B")
        static let error = Color(hex: "#C64545")
    }

    enum Spacing {
        static let x4: CGFloat = 4
        static let x8: CGFloat = 8
        static let x12: CGFloat = 12
        static let x16: CGFloat = 16
        static let x20: CGFloat = 20
        static let x24: CGFloat = 24
        static let x32: CGFloat = 32
        static let x40: CGFloat = 40
    }

    enum Radius {
        static let sm: CGFloat = 12
        static let md: CGFloat = 16
        static let lg: CGFloat = 20
        static let xl: CGFloat = 22
        static let pill: CGFloat = 999
    }

    enum Typography {
        static let displayLarge = Font.system(size: 34, weight: .bold, design: .rounded)
        static let title1 = Font.system(size: 28, weight: .semibold, design: .rounded)
        static let title2 = Font.system(size: 22, weight: .semibold, design: .rounded)
        static let heading = Font.system(size: 18, weight: .semibold, design: .default)
        static let body = Font.system(size: 16, weight: .regular, design: .default)
        static let bodyMedium = Font.system(size: 16, weight: .medium, design: .default)
        static let caption = Font.system(size: 13, weight: .medium, design: .default)
        static let micro = Font.system(size: 11, weight: .medium, design: .default)
    }

    enum Shadow {
        static let card = ShadowStyle(color: Color.black.opacity(0.08), radius: 16, x: 0, y: 4)
        static let floating = ShadowStyle(color: Color.black.opacity(0.12), radius: 24, x: 0, y: 8)
    }
}

struct ShadowStyle {
    let color: Color
    let radius: CGFloat
    let x: CGFloat
    let y: CGFloat
}

extension View {
    func dsCardStyle() -> some View {
        self
            .padding(DS.Spacing.x16)
            .background(DS.ColorToken.surface)
            .clipShape(RoundedRectangle(cornerRadius: DS.Radius.md, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: DS.Radius.md, style: .continuous)
                    .stroke(DS.ColorToken.border, lineWidth: 1)
            )
            .shadow(
                color: DS.Shadow.card.color,
                radius: DS.Shadow.card.radius,
                x: DS.Shadow.card.x,
                y: DS.Shadow.card.y
            )
    }
}

private func dynamicColor(light: String, dark: String) -> Color {
    Color(
        UIColor { trait in
            if trait.userInterfaceStyle == .dark {
                return UIColor(hex: dark)
            }
            return UIColor(hex: light)
        }
    )
}

extension Color {
    init(hex: String) {
        self.init(UIColor(hex: hex))
    }
}

extension UIColor {
    convenience init(hex: String) {
        let cleaned = hex.replacingOccurrences(of: "#", with: "")
        var value: UInt64 = 0
        Scanner(string: cleaned).scanHexInt64(&value)

        let r = CGFloat((value >> 16) & 0xFF) / 255.0
        let g = CGFloat((value >> 8) & 0xFF) / 255.0
        let b = CGFloat(value & 0xFF) / 255.0

        self.init(red: r, green: g, blue: b, alpha: 1)
    }
}

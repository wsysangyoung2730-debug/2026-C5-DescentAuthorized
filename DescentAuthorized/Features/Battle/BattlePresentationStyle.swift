import SwiftUI

enum DAColor {
    static let background = Color(red: 8 / 255, green: 11 / 255, blue: 16 / 255)
    static let panel = Color(red: 11 / 255, green: 16 / 255, blue: 23 / 255)
    static let card = Color(red: 13 / 255, green: 18 / 255, blue: 26 / 255)
    static let divider = Color(red: 42 / 255, green: 53 / 255, blue: 66 / 255)
    static let body = Color(red: 216 / 255, green: 226 / 255, blue: 232 / 255)
    static let secondary = Color(red: 126 / 255, green: 141 / 255, blue: 155 / 255)
    static let magic = Color(red: 123 / 255, green: 93 / 255, blue: 211 / 255)
    static let magicGlow = Color(red: 192 / 255, green: 166 / 255, blue: 250 / 255)
    static let attack = Color(red: 196 / 255, green: 69 / 255, blue: 63 / 255)
    static let defense = Color(red: 111 / 255, green: 182 / 255, blue: 217 / 255)
    static let dispel = Color(red: 201 / 255, green: 162 / 255, blue: 39 / 255)
    static let gold = Color(red: 213 / 255, green: 174 / 255, blue: 67 / 255)
}

struct DAStatusPanel: ViewModifier {
    var accent: Color = DAColor.divider

    func body(content: Content) -> some View {
        content
            .padding(10)
            .background(DAColor.panel.opacity(0.9))
            .clipShape(RoundedRectangle(cornerRadius: 6))
            .overlay {
                RoundedRectangle(cornerRadius: 6)
                    .stroke(accent.opacity(0.65), lineWidth: 1)
            }
    }
}

extension View {
    func daStatusPanel(accent: Color = DAColor.divider) -> some View {
        modifier(DAStatusPanel(accent: accent))
    }
}

struct BattleResourceReadout: View {
    let mana: Double
    let strokes: Int

    var body: some View {
        HStack(spacing: 14) {
            resource(icon: "scribble.variable", title: "마나", value: "\(Int(mana.rounded()))")
            Rectangle().fill(DAColor.divider).frame(width: 1, height: 28)
            resource(icon: "pencil.and.outline", title: "남은 획", value: "\(strokes)")
        }
        .daStatusPanel(accent: DAColor.magic)
        .accessibilityElement(children: .combine)
    }

    private func resource(icon: String, title: String, value: String) -> some View {
        HStack(spacing: 7) {
            Image(systemName: icon).foregroundStyle(DAColor.magicGlow)
            VStack(alignment: .leading, spacing: 1) {
                Text(title).font(.caption2).foregroundStyle(DAColor.secondary)
                Text(value).font(.subheadline.monospacedDigit().weight(.bold))
            }
        }
    }
}

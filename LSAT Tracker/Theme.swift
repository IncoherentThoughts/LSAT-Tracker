import SwiftUI

extension Color {
    init(hex: String) {
        let hex = hex.trimmingCharacters(in: CharacterSet.alphanumerics.inverted)
        var int: UInt64 = 0
        Scanner(string: hex).scanHexInt64(&int)
        let a, r, g, b: UInt64
        switch hex.count {
        case 3:
            (a, r, g, b) = (255, (int >> 8) * 17, (int >> 4 & 0xF) * 17, (int & 0xF) * 17)
        case 6:
            (a, r, g, b) = (255, int >> 16, int >> 8 & 0xFF, int & 0xFF)
        case 8:
            (a, r, g, b) = (int >> 24, int >> 16 & 0xFF, int >> 8 & 0xFF, int & 0xFF)
        default:
            (a, r, g, b) = (255, 0, 0, 0)
        }
        self.init(
            .sRGB,
            red: Double(r) / 255,
            green: Double(g) / 255,
            blue: Double(b) / 255,
            opacity: Double(a) / 255
        )
    }

    // MARK: - LSAT Timer Palette
    static let toffeeBrown   = Color(hex: "#9E6240")  // primary text, icons
    static let lightBronze   = Color(hex: "#DEA47E")  // secondary — muted labels, inactive elements
    static let rosyCopper    = Color(hex: "#CD4631")  // active states, progress bars, accents
    static let eggshell      = Color(hex: "#F8F2DC")  // app background
    static let skyReflection = Color(hex: "#81ADC8")  // achievement callouts, streaks, highlights
}

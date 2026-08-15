import SwiftUI

struct SessionAvatar: View {
    let title: String
    var size: CGFloat = 42

    var body: some View {
        Text(initials)
            .font(.system(size: size * 0.36, weight: .semibold))
            .foregroundStyle(.white)
            .frame(width: size, height: size)
            .background(avatarGradient, in: Circle())
    }

    private var initials: String {
        let words = title
            .split(whereSeparator: { $0.isWhitespace || $0 == "-" || $0 == "_" })
            .prefix(2)
        let letters = words.compactMap { $0.first }.map { String($0).uppercased() }
        return letters.isEmpty ? "OC" : letters.joined()
    }

    private var avatarGradient: LinearGradient {
        let palettes: [(Color, Color)] = [
            (.blue, .purple),
            (.pink, .orange),
            (.teal, .blue),
            (.indigo, .mint),
            (.orange, .red),
            (.green, .teal),
        ]
        let paletteIndex = Int(opencodeStableHash(title) % UInt64(palettes.count))
        let palette = palettes[paletteIndex]
        return LinearGradient(colors: [palette.0, palette.1], startPoint: .topLeading, endPoint: .bottomTrailing)
    }
}

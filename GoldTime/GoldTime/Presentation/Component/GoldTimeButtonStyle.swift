import SwiftUI

struct GoldTimeButtonStyle: ButtonStyle {
    let background: Color
    let foreground: Color
    var cornerRadius: CGFloat = 16

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.headline)
            .padding(.vertical, 14)
            .foregroundStyle(foreground)
            .background(background.opacity(configuration.isPressed ? 0.82 : 1))
            .clipShape(RoundedRectangle(cornerRadius: cornerRadius))
    }
}

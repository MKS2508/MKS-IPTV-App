import SwiftUI

// MARK: - Button Components for AddDownloadView

enum DownloadButtonType {
    case primary
    case secondary
    case cancel
}

struct DownloadButtonStyle: ButtonStyle {
    var type: DownloadButtonType
    
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .padding()
            .frame(maxWidth: .infinity)
            .background(backgroundColor(configuration.isPressed))
            .foregroundColor(foregroundColor)
            .cornerRadius(8)
            .scaleEffect(configuration.isPressed ? 0.95 : 1)
    }
    
    private func backgroundColor(_ isPressed: Bool) -> Color {
        switch type {
        case .primary:
            return isPressed ? Color.accentColor.opacity(0.8) : Color.accentColor
        case .secondary:
            return isPressed ? Color.secondary.opacity(0.15) : Color.secondary.opacity(0.1)
        case .cancel:
            return isPressed ? Color.secondary.opacity(0.05) : Color.secondary.opacity(0.1)
        }
    }
    
    private var foregroundColor: Color {
        switch type {
        case .primary:
            return .white
        case .secondary, .cancel:
            return .secondary
        }
    }
}
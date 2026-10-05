import SwiftUI
import UIKit

/// Palette taken from the app icon: a royal-blue gradient with an amber accent.
enum Theme {
    static let blueLight = Color(red: 0.12, green: 0.45, blue: 0.94)
    static let blueDeep = Color(red: 0.08, green: 0.22, blue: 0.66)
    static let amber = Color(red: 1.0, green: 0.77, blue: 0.0)

    static var brandGradient: LinearGradient {
        LinearGradient(
            colors: [blueLight, blueDeep],
            startPoint: .topLeading,
            endPoint: .bottomTrailing
        )
    }

    static let cardRadius: CGFloat = 20
}

// MARK: - Haptics

@MainActor
enum Haptics {
    static func tap() {
        UIImpactFeedbackGenerator(style: .light).impactOccurred()
    }

    static func select() {
        UISelectionFeedbackGenerator().selectionChanged()
    }

    static func success() {
        UINotificationFeedbackGenerator().notificationOccurred(.success)
    }

    static func warning() {
        UINotificationFeedbackGenerator().notificationOccurred(.warning)
    }
}

// MARK: - Cards

extension View {
    /// A soft, rounded surface that lifts off the grouped background.
    func cardStyle(padding: CGFloat = 14) -> some View {
        self
            .padding(padding)
            .background(
                Color(.secondarySystemGroupedBackground),
                in: RoundedRectangle(cornerRadius: Theme.cardRadius, style: .continuous)
            )
            .shadow(color: Color.black.opacity(0.07), radius: 10, x: 0, y: 4)
    }
}

// MARK: - Button styles

/// The big blue gradient call-to-action.
struct PrimaryButtonStyle: ButtonStyle {
    var cornerRadius: CGFloat = 16
    @Environment(\.isEnabled) private var isEnabled

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.headline)
            .foregroundStyle(.white)
            .padding(.vertical, 15)
            .frame(maxWidth: .infinity)
            .background(Theme.brandGradient, in: RoundedRectangle(cornerRadius: cornerRadius, style: .continuous))
            .shadow(color: Theme.blueDeep.opacity(0.35), radius: 10, x: 0, y: 5)
            .opacity(isEnabled ? 1 : 0.45)
            .scaleEffect(configuration.isPressed ? 0.97 : 1)
            .animation(.spring(response: 0.25, dampingFraction: 0.7), value: configuration.isPressed)
    }
}

/// A quieter button for secondary actions: material background, primary-colored label.
struct SecondaryButtonStyle: ButtonStyle {
    var cornerRadius: CGFloat = 16
    var fillsWidth = true
    @Environment(\.isEnabled) private var isEnabled

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.subheadline.weight(.semibold))
            .foregroundStyle(Color.accentColor)
            .padding(.vertical, 12)
            .padding(.horizontal, 14)
            .frame(maxWidth: fillsWidth ? .infinity : nil)
            .background(
                Color.accentColor.opacity(0.12),
                in: RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
            )
            .opacity(isEnabled ? 1 : 0.45)
            .scaleEffect(configuration.isPressed ? 0.97 : 1)
            .animation(.spring(response: 0.25, dampingFraction: 0.7), value: configuration.isPressed)
    }
}

/// No chrome at all, just a little squish when pressed — for tappable cards.
struct PressableButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .scaleEffect(configuration.isPressed ? 0.97 : 1)
            .animation(.spring(response: 0.25, dampingFraction: 0.7), value: configuration.isPressed)
    }
}

extension ButtonStyle where Self == PrimaryButtonStyle {
    static var primary: PrimaryButtonStyle { PrimaryButtonStyle() }
}

extension ButtonStyle where Self == PressableButtonStyle {
    static var pressable: PressableButtonStyle { PressableButtonStyle() }
}

extension ButtonStyle where Self == SecondaryButtonStyle {
    static var secondary: SecondaryButtonStyle { SecondaryButtonStyle() }
}

// MARK: - Small reusable pieces

/// Round avatar with the first letter of the email.
struct AvatarView: View {
    let email: String
    var size: CGFloat = 34

    var body: some View {
        Text(String(email.first ?? "?").uppercased())
            .font(.system(size: size * 0.45, weight: .bold, design: .rounded))
            .foregroundStyle(.white)
            .frame(width: size, height: size)
            .background(Theme.brandGradient, in: Circle())
    }
}

/// The app's logo mark, drawn from SF Symbols so it needs no image asset.
struct LogoMark: View {
    var size: CGFloat = 88

    var body: some View {
        ZStack {
            RoundedRectangle(cornerRadius: size * 0.24, style: .continuous)
                .fill(Color.white)
                .shadow(color: Color.black.opacity(0.18), radius: 14, x: 0, y: 8)
            Image(systemName: "doc.text.viewfinder")
                .font(.system(size: size * 0.5, weight: .semibold))
                .foregroundStyle(Theme.brandGradient)
        }
        .frame(width: size, height: size)
    }
}

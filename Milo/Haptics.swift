import UIKit

/// Tactile feedback on the moments that matter: a log landing, an allergy
/// warning, a stepper tick. Cheap calls, native feel.
enum Haptics {
    static func success() { UINotificationFeedbackGenerator().notificationOccurred(.success) }
    static func warning() { UINotificationFeedbackGenerator().notificationOccurred(.warning) }
    static func tap()     { UIImpactFeedbackGenerator(style: .light).impactOccurred() }
}

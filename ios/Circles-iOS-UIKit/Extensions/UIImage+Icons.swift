import UIKit

// Shared semantic icons — one definition so every surface shows the same
// symbol and fallback behavior.
extension UIImage {

    /// Check-in: a person walking through a door (figure.walk.arrival,
    /// SF Symbols 5 / iOS 17). Wes's call 2026-08-17: reads as "arriving at
    /// a place" far better than the old checkmark, which looked like a
    /// generic confirm. iOS 16 devices fall back to the checkmark.
    static var checkInIcon: UIImage? {
        UIImage(systemName: "figure.walk.arrival") ?? UIImage(systemName: "checkmark.circle")
    }
}

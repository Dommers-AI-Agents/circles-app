import UIKit

/// Shared "report incorrect place info" flow. Venue fields are read-only for
/// users (Google Places is the source of truth), so flagging is how bad data
/// gets fixed: the report is stored and the admin is emailed.
extension UIViewController {

    func promptFlagPlaceInfo(placeId: String, placeName: String) {
        showTextInput(
            title: "Report incorrect info",
            message: "What's wrong with \(placeName)'s information? (e.g. wrong address, closed permanently, wrong phone number)",
            placeholder: "Describe the problem"
        ) { [weak self] message in
            guard let self = self,
                  let message = message?.trimmingCharacters(in: .whitespacesAndNewlines),
                  !message.isEmpty else { return }

            let loading = AlertPresenter.showLoading(message: "Sending...", from: self)
            PlaceService.shared.flagPlaceInfo(placeId: placeId, message: message) { [weak self] result in
                DispatchQueue.main.async {
                    loading.dismiss(animated: true) {
                        guard let self = self else { return }
                        switch result {
                        case .success:
                            self.showSuccess("Thanks — we'll review it and fix the listing.")
                        case .failure(let error):
                            self.showError(error)
                        }
                    }
                }
            }
        }
    }
}

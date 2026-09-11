import UIKit

protocol PlaceNotesEditControllerDelegate: AnyObject {
    /// The place on screen.
    func currentPlace(for controller: PlaceNotesEditController) -> Place
    /// Our own save of this venue when the screen shows someone else's copy.
    func mySaveOfVenue(for controller: PlaceNotesEditController) -> Place?
    /// Our save record arrived — remember it and show its private note.
    func notesEdit(_ controller: PlaceNotesEditController, didLoadMySave mine: Place)
    /// Notes were saved server-side; `updatedPlace` is the record they live on.
    func notesEdit(_ controller: PlaceNotesEditController, didSave privateNotes: String, updatedPlace: Place)
}

/// The place page's private notes: which save record they belong to, the
/// editor sheet, and the save. Notes live on the viewer's OWN save — when
/// the screen shows another user's copy of a venue, that's a different
/// record than the place on screen.
final class PlaceNotesEditController {
    private unowned let presenter: UIViewController
    weak var delegate: PlaceNotesEditControllerDelegate?

    init(presenter: UIViewController) {
        self.presenter = presenter
    }

    /// When this screen shows ANOTHER user's copy of a venue, our private
    /// note (if any) lives on OUR save record. Resolve it so the notes
    /// section shows and edits the right thing.
    func loadMySaveOfVenueIfNeeded() {
        guard let place = delegate?.currentPlace(for: self) else { return }
        guard !place.isAddedByCurrentUser,
              let globalPlaceId = place.globalPlaceId ?? place.googlePlaceId else { return }
        PlaceService.shared.fetchMySaveOfVenue(globalPlaceId: globalPlaceId) { [weak self] result in
            DispatchQueue.main.async {
                guard let self = self, case .success(let mine) = result else { return }
                self.delegate?.notesEdit(self, didLoadMySave: mine)
            }
        }
    }

    /// The save record private notes belong to: our own save when the screen
    /// shows someone else's copy of the venue
    private var notesTargetPlace: Place? {
        guard let place = delegate?.currentPlace(for: self) else { return nil }
        if place.isAddedByCurrentUser { return place }
        return delegate?.mySaveOfVenue(for: self)
    }

    func presentEditor() {
        let notesEditorVC = NotesEditorViewController(
            privateNotes: notesTargetPlace?.privateNotes ?? "",
            isPrivateNotesEnabled: notesTargetPlace != nil
        )

        notesEditorVC.onSave = { [weak self] privateNotes in
            self?.save(privateNotes: privateNotes)
        }

        let navController = UINavigationController(rootViewController: notesEditorVC)
        presenter.present(navController, animated: true)
    }

    private func save(privateNotes: String) {
        guard let target = notesTargetPlace else { return }

        // Show loading indicator
        let loadingAlert = AlertPresenter.showLoading(message: "Saving Notes...", from: presenter)

        // Call PlaceService to update notes on Firebase
        PlaceService.shared.updatePlace(
            id: target.id,
            privateNotes: privateNotes
        ) { [weak self] result in
            guard let self = self else { return }

            // Ensure all UI updates happen on the main thread
            DispatchQueue.main.async {
                loadingAlert.dismiss(animated: true) {
                    switch result {
                    case .success(let updatedPlace):
                        self.delegate?.notesEdit(self, didSave: privateNotes, updatedPlace: updatedPlace)
                    case .failure(let error):
                        // Show error alert
                        self.presenter.showError("Failed to save notes: \(error.localizedDescription)")
                    }
                }
            }
        }
    }
}

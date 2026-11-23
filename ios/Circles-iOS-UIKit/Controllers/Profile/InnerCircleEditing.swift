import UIKit

/// Every way an Inner Circle list is made, renamed, deleted or has its people
/// changed — the prompts, the warnings and the writes, in one place.
///
/// Two surfaces edit the same lists: the Settings screens
/// (`InnerCircleListsViewController`, `InnerCircleListViewController`) and the
/// rings on My Network → My People → Inner Circles. What deleting a list or
/// taking someone off it means is not obvious and must be said the same way
/// on both, so neither retypes it.
enum InnerCircleEditing {

    // MARK: - Words both surfaces use

    static let emptyListWarning = "Nobody yet — the same as Private until you add someone"

    static func peopleCount(_ count: Int) -> String {
        count == 1 ? "1 person" : "\(count) people"
    }

    /// The line under a list's name.
    static func summary(memberCount: Int) -> String {
        memberCount == 0 ? emptyListWarning : peopleCount(memberCount)
    }

    // MARK: - Lists

    /// Asks for a name and creates the list. `then` gets the fresh lists and
    /// the list just made.
    static func promptNewList(existingCount: Int,
                              maxLists: Int,
                              from viewController: UIViewController,
                              then: @escaping (InnerCircleList, InnerCircleNamedList) -> Void) {
        guard existingCount < maxLists else {
            viewController.showError("You can keep up to \(maxLists) lists.")
            return
        }
        AlertPresenter.showTextInput(
            title: "New list",
            message: "Name it for the people on it — Family, Gym crew, Work.",
            placeholder: "Name",
            confirmTitle: "Create",
            from: viewController
        ) { [weak viewController] name in
            guard let viewController,
                  let name = name?.trimmingCharacters(in: .whitespacesAndNewlines), !name.isEmpty else { return }
            run("Creating…", from: viewController) { done in
                InnerCircleService.shared.createList(name: name, userIds: [], completion: done)
            } then: { list in
                guard let created = (list.lists ?? []).last else { return }
                then(list, created)
            }
        }
    }

    static func promptRename(listId: String,
                             currentName: String,
                             from viewController: UIViewController,
                             then: @escaping (InnerCircleList) -> Void) {
        AlertPresenter.showTextInput(
            title: "Rename \(currentName)",
            message: nil,
            placeholder: "Name",
            initialText: currentName,
            confirmTitle: "Save",
            from: viewController
        ) { [weak viewController] name in
            guard let viewController,
                  let name = name?.trimmingCharacters(in: .whitespacesAndNewlines),
                  !name.isEmpty, name != currentName else { return }
            run("Saving…", from: viewController, { done in
                InnerCircleService.shared.updateList(id: listId, name: name, completion: done)
            }, then: then)
        }
    }

    static func confirmDelete(_ list: InnerCircleNamedList,
                              from viewController: UIViewController,
                              then: @escaping (InnerCircleList) -> Void) {
        let people = peopleCount(list.userIds.count)
        AlertPresenter.showConfirmation(
            title: "Delete \(list.name)?",
            message: "Anything you've set to this list stops being visible to those \(people), including things they can see now. Nobody is removed from your connections.",
            confirmTitle: "Delete",
            isDestructive: true,
            from: viewController,
            onConfirm: { [weak viewController] in
                guard let viewController else { return }
                run("Deleting…", from: viewController, { done in
                    InnerCircleService.shared.deleteList(id: list.id, completion: done)
                }, then: then)
            }
        )
    }

    // MARK: - People

    /// The connections picker, seeded with who is on the list now, so it is
    /// the whole list (people can be unchecked here too) and what comes back
    /// is the complete new membership.
    static func presentPeoplePicker(listName: String,
                                    currentMembers: [User],
                                    maxSize: Int,
                                    from viewController: UIViewController,
                                    onChosen: @escaping ([String]) -> Void) {
        let picker = TagPeoplePickerViewController()
        picker.title = "Add to \(listName)"
        picker.initialSelection = currentMembers.map {
            TaggedMomentUser(id: $0.id, displayName: $0.displayName, profilePicture: $0.profilePicture)
        }
        picker.selectionLimit = maxSize
        picker.limitMessage = "A list can hold up to \(maxSize) people"
        picker.emptyStateOverride = "Only your connections can be on a list. Connect with someone first, then add them here."
        picker.onDone = { chosen in onChosen(chosen.map { $0.id }) }
        viewController.present(UINavigationController(rootViewController: picker), animated: true)
    }

    static func confirmRemove(_ person: User,
                              listName: String,
                              from viewController: UIViewController,
                              onConfirm: @escaping () -> Void) {
        AlertPresenter.showConfirmation(
            title: "Remove \(person.displayName)?",
            message: "They'll stop seeing anything you've set to \(listName), including things they can see now.",
            confirmTitle: "Remove",
            from: viewController,
            onConfirm: onConfirm
        )
    }

    /// Replaces who is on a named list. `userIds` must be the list's COMPLETE
    /// new membership: the server overwrites, it does not merge.
    static func setMembers(listId: String,
                           userIds: [String],
                           from viewController: UIViewController,
                           then: @escaping (InnerCircleList) -> Void) {
        run("Saving…", from: viewController, { done in
            InnerCircleService.shared.updateList(id: listId, userIds: userIds, completion: done)
        }, then: then)
    }

    // MARK: - One shape for every write

    /// A spinner (which also blocks a second tap while the save is out), then
    /// the fresh lists or the server's own words about why not.
    static func run(_ message: String,
                    from viewController: UIViewController,
                    _ work: (@escaping (Result<InnerCircleList, Error>) -> Void) -> Void,
                    then: ((InnerCircleList) -> Void)? = nil) {
        let loading = AlertPresenter.showLoading(message: message, from: viewController)
        work { [weak viewController] result in
            DispatchQueue.main.async {
                loading.dismiss(animated: true) {
                    switch result {
                    case .success(let list):
                        then?(list)
                    case .failure(let error):
                        // Not a connection, over the cap: showError surfaces
                        // the server's wording verbatim.
                        viewController?.showError(error)
                    }
                }
            }
        }
    }
}

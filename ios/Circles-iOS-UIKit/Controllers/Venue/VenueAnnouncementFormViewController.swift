import UIKit

/// Post or edit one announcement: a headline, the details, and an optional
/// last day — or, switched to an event, when it happens and whether it's
/// free (events also show under "Happening nearby" on the Locals tab and
/// come down on their own when they're over). Existing announcements can be
/// deleted from here too.
final class VenueAnnouncementFormViewController: BaseViewController {

    private let venueId: String
    private let existing: VenueAnnouncement?
    private var draft: VenueAnnouncementEdit
    /// The venue's full announcement list after the save or delete
    var onSaved: (([VenueAnnouncement]) -> Void)?

    override var loadsDataOnViewDidLoad: Bool { false }
    override var showsLoadingIndicator: Bool { false }

    private lazy var titleField = VenueFormLayout.textField(placeholder: "Happy Hour", text: draft.title)
    private lazy var messageView = VenueFormLayout.textView(text: draft.message)
    private let endsSwitch = UISwitch()
    private let endsPicker: UIDatePicker = {
        let picker = UIDatePicker()
        picker.datePickerMode = .date
        picker.preferredDatePickerStyle = .inline
        picker.minimumDate = Date()
        return picker
    }()
    private let endsHint = VenueFormLayout.hintLabel()
    private var endsSection: UIStackView!

    // Event
    private let eventSwitch = UISwitch()
    private let eventStartPicker = VenueAnnouncementFormViewController.timePicker()
    private let eventEndSwitch = UISwitch()
    private let eventEndPicker = VenueAnnouncementFormViewController.timePicker()
    private let freeSwitch = UISwitch()
    private let eventHint = VenueFormLayout.hintLabel()
    private var eventDetails: UIStackView!
    private var eventEndRow: UIView!

    private static func timePicker() -> UIDatePicker {
        let picker = UIDatePicker()
        picker.datePickerMode = .dateAndTime
        picker.preferredDatePickerStyle = .compact
        picker.minuteInterval = 15
        picker.minimumDate = Date().addingTimeInterval(-3600)
        picker.tintColor = Constants.Colors.primary
        return picker
    }

    /// The next whole hour, at least an hour out
    private static func defaultEventStart() -> Date {
        let calendar = Calendar.current
        let hour = calendar.dateInterval(of: .hour, for: Date().addingTimeInterval(3600))?.start ?? Date()
        return calendar.date(byAdding: .hour, value: 1, to: hour) ?? hour
    }
    private let problemLabel = VenueFormLayout.problemLabel()
    private lazy var saveButton = UIButton.primaryButton(title: existing == nil ? "Post announcement" : "Save changes")
    private lazy var deleteButton = UIButton.dangerButton(title: "Delete announcement")

    init(venueId: String, announcement: VenueAnnouncement? = nil) {
        self.venueId = venueId
        self.existing = announcement
        self.draft = announcement.map(VenueAnnouncementEdit.init(announcement:)) ?? VenueAnnouncementEdit()
        super.init(nibName: nil, bundle: nil)
        title = announcement == nil ? "New Announcement" : "Edit Announcement"
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func viewDidLoad() {
        super.viewDidLoad()
        view.backgroundColor = Constants.Colors.background
        let stack = VenueFormLayout.install(in: view)

        stack.addArrangedSubview(VenueFormLayout.hintLabel(
            "Shown on your place page and in your followers' feeds — deals, happy hours, events."))

        titleField.autocapitalizationType = .words
        titleField.delegate = self
        titleField.addTarget(self, action: #selector(fieldsChanged), for: .editingChanged)
        stack.addArrangedSubview(VenueFormLayout.field("Headline", titleField))

        messageView.delegate = self
        stack.addArrangedSubview(VenueFormLayout.field("Details", messageView,
            hint: VenueFormLayout.hintLabel("For example \u{201C}2-for-1 drinks, 3–5pm weekdays.\u{201D}")))

        // Event: when it happens, whether it's free
        eventSwitch.isOn = draft.isEvent
        eventSwitch.addTarget(self, action: #selector(eventToggled), for: .valueChanged)
        eventStartPicker.date = draft.eventStart ?? Self.defaultEventStart()
        eventStartPicker.addTarget(self, action: #selector(eventTimesChanged), for: .valueChanged)
        eventEndSwitch.isOn = draft.eventEnd != nil
        eventEndSwitch.addTarget(self, action: #selector(eventToggled), for: .valueChanged)
        eventEndPicker.date = draft.eventEnd ?? eventStartPicker.date.addingTimeInterval(2 * 3600)
        eventEndPicker.addTarget(self, action: #selector(fieldsChanged), for: .valueChanged)
        freeSwitch.isOn = draft.eventIsFree
        freeSwitch.addTarget(self, action: #selector(fieldsChanged), for: .valueChanged)
        eventEndRow = pickerRow("Ends", eventEndPicker)
        eventDetails = UIStackView(arrangedSubviews: [
            pickerRow("Starts", eventStartPicker),
            VenueFormLayout.toggleRow("Add an end time", eventEndSwitch),
            eventEndRow,
            VenueFormLayout.toggleRow("Free to attend", freeSwitch)
        ])
        eventDetails.axis = .vertical
        eventDetails.spacing = 8
        let eventSection = UIStackView(arrangedSubviews: [
            VenueFormLayout.toggleRow("This is an event", eventSwitch),
            eventHint,
            eventDetails
        ])
        eventSection.axis = .vertical
        eventSection.spacing = 6
        stack.addArrangedSubview(eventSection)

        endsSwitch.isOn = draft.endsOn != nil
        endsSwitch.addTarget(self, action: #selector(endsToggled), for: .valueChanged)
        endsPicker.date = max(draft.endsOn ?? Date().addingTimeInterval(7 * 24 * 60 * 60), Date())
        endsPicker.tintColor = Constants.Colors.primary
        endsPicker.addTarget(self, action: #selector(fieldsChanged), for: .valueChanged)
        endsSection = UIStackView(arrangedSubviews: [
            VenueFormLayout.toggleRow("Ends on a date", endsSwitch),
            endsHint,
            endsPicker
        ])
        endsSection.axis = .vertical
        endsSection.spacing = 6
        stack.addArrangedSubview(endsSection)

        stack.addArrangedSubview(problemLabel)
        saveButton.addTarget(self, action: #selector(saveTapped), for: .touchUpInside)
        stack.addArrangedSubview(saveButton)

        if existing != nil {
            deleteButton.addTarget(self, action: #selector(deleteTapped), for: .touchUpInside)
            stack.addArrangedSubview(deleteButton)
        } else {
            titleField.becomeFirstResponder()
        }
        renderEnds()
    }

    private func pickerRow(_ title: String, _ picker: UIDatePicker) -> UIView {
        let label = UILabel()
        label.text = title
        label.font = .systemFont(ofSize: 16)
        label.textColor = Constants.Colors.label
        let row = UIStackView(arrangedSubviews: [label, UIView(), picker])
        row.alignment = .center
        row.spacing = 8
        return row
    }

    @objc private func eventToggled() {
        fieldsChanged()
        UIView.animate(withDuration: 0.2) { self.renderEnds() }
    }

    /// Moving the start drags the end along when it would land before it
    @objc private func eventTimesChanged() {
        if eventEndPicker.date <= eventStartPicker.date {
            eventEndPicker.date = eventStartPicker.date.addingTimeInterval(2 * 3600)
        }
        fieldsChanged()
    }

    @objc private func endsToggled() {
        fieldsChanged()
        UIView.animate(withDuration: 0.2) { self.renderEnds() }
    }

    private func renderEnds() {
        let isEvent = eventSwitch.isOn
        eventDetails.isHidden = !isEvent
        eventEndRow.isHidden = !eventEndSwitch.isOn
        endsSection.isHidden = isEvent
        eventHint.text = isEvent
            ? "Shows under \u{201C}Happening nearby\u{201D} on the Locals tab and comes down on its own when it\u{2019}s over."
            : "Live music, trivia, a tasting? Make it an event so people nearby see it."
        endsPicker.isHidden = !endsSwitch.isOn
        if endsSwitch.isOn {
            let formatter = DateFormatter()
            formatter.dateStyle = .full
            endsHint.text = "Stays up through \(formatter.string(from: endsPicker.date)), then hides on its own."
        } else {
            endsHint.text = "Stays up until you delete it."
        }
    }

    @objc private func fieldsChanged() {
        draft.title = titleField.text ?? ""
        draft.message = messageView.text ?? ""
        draft.endsOn = endsSwitch.isOn ? endsPicker.date : nil
        draft.eventStart = eventSwitch.isOn ? Self.wholeMinute(eventStartPicker.date) : nil
        draft.eventEnd = eventSwitch.isOn && eventEndSwitch.isOn ? Self.wholeMinute(eventEndPicker.date) : nil
        draft.eventIsFree = freeSwitch.isOn
        problemLabel.isHidden = true
        renderEnds()
    }

    private static func wholeMinute(_ date: Date) -> Date {
        Date(timeIntervalSinceReferenceDate: (date.timeIntervalSinceReferenceDate / 60).rounded(.down) * 60)
    }

    private func showProblem(_ text: String) {
        problemLabel.text = text
        problemLabel.isHidden = false
    }

    @objc private func saveTapped() {
        fieldsChanged()
        if let problem = draft.problem() {
            showProblem(problem)
            return
        }
        view.endEditing(true)
        saveButton.isEnabled = false

        if let announcement = existing {
            let changes = draft.changes(from: announcement)
            guard !changes.isEmpty else {
                navigationController?.popViewController(animated: true)
                return
            }
            RewardsService.shared.updateAnnouncement(
                venueId: venueId,
                announcementId: announcement.announcementId,
                title: changes.title,
                message: changes.message,
                expiresAt: changes.expiresAt,
                clearExpiry: changes.clearExpiry,
                event: changes.event?.dictionary,
                clearEvent: changes.clearEvent,
                completion: finish
            )
        } else {
            RewardsService.shared.addAnnouncement(
                venueId: venueId,
                title: draft.trimmedTitle,
                message: draft.trimmedMessage,
                expiresAt: draft.expiresAt(),
                event: draft.eventPayload()?.dictionary,
                completion: finish
            )
        }
    }

    @objc private func deleteTapped() {
        guard let announcement = existing else { return }
        showConfirmation(
            title: "Delete \u{201C}\(announcement.title)\u{201D}?",
            message: "It disappears from your place page and followers' feeds right away.",
            confirmTitle: "Delete",
            isDestructive: true
        ) { [weak self] in
            guard let self = self else { return }
            self.deleteButton.isEnabled = false
            RewardsService.shared.deleteAnnouncement(venueId: self.venueId, announcementId: announcement.announcementId, completion: self.finish)
        }
    }

    private func finish(_ result: Result<[VenueAnnouncement], Error>) {
        DispatchQueue.main.async { [weak self] in
            guard let self = self else { return }
            self.saveButton.isEnabled = true
            self.deleteButton.isEnabled = true
            switch result {
            case .success(let announcements):
                self.onSaved?(announcements)
                self.navigationController?.popViewController(animated: true)
            case .failure(let error):
                self.showProblem((error as? APIError)?.serverMessage ?? error.localizedDescription)
            }
        }
    }
}

extension VenueAnnouncementFormViewController: UITextFieldDelegate, UITextViewDelegate {
    func textFieldShouldReturn(_ textField: UITextField) -> Bool {
        messageView.becomeFirstResponder()
        return true
    }

    func textViewDidChange(_ textView: UITextView) {
        fieldsChanged()
    }
}

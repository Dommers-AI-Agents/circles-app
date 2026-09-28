import UIKit

/// Add or edit one offer customers redeem with their points: what they get,
/// what it costs, and (for an existing offer) whether it's live right now.
final class VenueOfferFormViewController: BaseViewController {

    private let venueId: String
    private let existing: RewardOffer?
    private let earnRate: Int
    private var draft: VenueOfferEdit
    /// The venue's full offer list after the save
    var onSaved: (([RewardOffer]) -> Void)?

    override var loadsDataOnViewDidLoad: Bool { false }
    override var showsLoadingIndicator: Bool { false }

    private lazy var titleField = VenueFormLayout.textField(placeholder: "Free coffee", text: draft.title)
    private lazy var pointsField = VenueFormLayout.textField(placeholder: "100", text: draft.pointsText, keyboard: .numberPad)
    private let pointsHint = VenueFormLayout.hintLabel()
    private let activeSwitch = UISwitch()
    private let problemLabel = VenueFormLayout.problemLabel()
    private lazy var saveButton = UIButton.primaryButton(title: existing == nil ? "Add offer" : "Save changes")

    init(venueId: String, earnRate: Int, offer: RewardOffer? = nil) {
        self.venueId = venueId
        self.earnRate = earnRate
        self.existing = offer
        self.draft = offer.map(VenueOfferEdit.init(offer:)) ?? VenueOfferEdit()
        super.init(nibName: nil, bundle: nil)
        title = offer == nil ? "New Offer" : "Edit Offer"
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func viewDidLoad() {
        super.viewDidLoad()
        view.backgroundColor = Constants.Colors.background
        let stack = VenueFormLayout.install(in: view)

        stack.addArrangedSubview(VenueFormLayout.hintLabel(
            "Customers spend the points they earn at your store on offers. They tap Redeem at your counter and show you the confirmation screen; you hand over the reward."))

        titleField.autocapitalizationType = .sentences
        titleField.delegate = self
        titleField.addTarget(self, action: #selector(fieldsChanged), for: .editingChanged)
        stack.addArrangedSubview(VenueFormLayout.field("What the customer gets", titleField,
            hint: VenueFormLayout.hintLabel("For example \u{201C}Free coffee\u{201D} or \u{201C}10% off your order\u{201D}.")))

        pointsField.addTarget(self, action: #selector(fieldsChanged), for: .editingChanged)
        stack.addArrangedSubview(VenueFormLayout.field("Points it costs", pointsField, hint: pointsHint))

        if existing != nil {
            activeSwitch.isOn = draft.isActive
            activeSwitch.addTarget(self, action: #selector(fieldsChanged), for: .valueChanged)
            let toggle = UIStackView(arrangedSubviews: [
                VenueFormLayout.toggleRow("Available to customers", activeSwitch),
                VenueFormLayout.hintLabel("Turn this off to pause the offer without losing it. Customers won't see it until you turn it back on.")
            ])
            toggle.axis = .vertical
            toggle.spacing = 6
            stack.addArrangedSubview(toggle)
        }

        stack.addArrangedSubview(problemLabel)
        saveButton.addTarget(self, action: #selector(saveTapped), for: .touchUpInside)
        stack.addArrangedSubview(saveButton)

        updateHint()
        if existing == nil { titleField.becomeFirstResponder() }
    }

    @objc private func fieldsChanged() {
        draft.title = titleField.text ?? ""
        draft.pointsText = pointsField.text ?? ""
        draft.isActive = activeSwitch.isOn || existing == nil
        problemLabel.isHidden = true
        updateHint()
    }

    private func updateHint() {
        pointsHint.text = VenueOfferEdit.visitsHint(pointsCost: draft.pointsCost, earnRate: earnRate)
            ?? "Customers earn \(earnRate) points each time they scan your register card."
    }

    @objc private func saveTapped() {
        fieldsChanged()
        if let problem = draft.problem {
            problemLabel.text = problem
            problemLabel.isHidden = false
            return
        }
        guard let cost = draft.pointsCost else { return }

        view.endEditing(true)
        saveButton.isEnabled = false
        let done: (Result<[RewardOffer], Error>) -> Void = { [weak self] result in
            DispatchQueue.main.async {
                guard let self = self else { return }
                self.saveButton.isEnabled = true
                switch result {
                case .success(let offers):
                    self.onSaved?(offers)
                    self.navigationController?.popViewController(animated: true)
                case .failure(let error):
                    self.problemLabel.text = (error as? APIError)?.serverMessage ?? error.localizedDescription
                    self.problemLabel.isHidden = false
                }
            }
        }

        if let offer = existing {
            let changes = draft.changes(from: offer)
            guard !changes.isEmpty else {
                navigationController?.popViewController(animated: true)
                return
            }
            RewardsService.shared.updateOffer(
                venueId: venueId,
                offerId: offer.offerId,
                title: changes.title,
                pointsCost: changes.pointsCost,
                active: changes.active,
                completion: done
            )
        } else {
            RewardsService.shared.addOffer(venueId: venueId, title: draft.trimmedTitle, pointsCost: cost, completion: done)
        }
    }
}

extension VenueOfferFormViewController: UITextFieldDelegate {
    func textFieldShouldReturn(_ textField: UITextField) -> Bool {
        pointsField.becomeFirstResponder()
        return true
    }
}

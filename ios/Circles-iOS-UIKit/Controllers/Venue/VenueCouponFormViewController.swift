import UIKit

/// Add or edit one coupon: what it gives, the fine print, the last day, an
/// optional online code (for the store's own ordering site), a campaign
/// name for the numbers, how many may claim it, and whether it's on.
final class VenueCouponFormViewController: BaseViewController {

    private let venueId: String
    private let existing: VenueCoupon?
    private var draft: VenueCouponEdit
    /// The store's full coupon list after the save, and the new coupon when one was made
    var onSaved: (([VenueCoupon], VenueCoupon?) -> Void)?

    override var loadsDataOnViewDidLoad: Bool { false }
    override var showsLoadingIndicator: Bool { false }

    private lazy var titleField = VenueFormLayout.textField(placeholder: "20% off any pickup order", text: draft.title)
    private lazy var detailView = VenueFormLayout.textView(text: draft.detail)
    private lazy var codeField = VenueFormLayout.textField(placeholder: "TGOSTVQC", text: draft.onlineCode)
    private lazy var campaignField = VenueFormLayout.textField(placeholder: "November mailer", text: draft.campaign)
    private lazy var maxField = VenueFormLayout.textField(placeholder: "Open to everyone", text: draft.maxClaimsText, keyboard: .numberPad)
    private let endsPicker: UIDatePicker = {
        let picker = UIDatePicker()
        picker.datePickerMode = .date
        picker.preferredDatePickerStyle = .compact
        picker.minimumDate = Date()
        picker.tintColor = Constants.Colors.primary
        return picker
    }()
    private let activeSwitch = UISwitch()
    private let problemLabel = VenueFormLayout.problemLabel()
    private lazy var saveButton = UIButton.primaryButton(title: existing == nil ? "Add coupon" : "Save changes")

    init(venueId: String, coupon: VenueCoupon? = nil) {
        self.venueId = venueId
        self.existing = coupon
        self.draft = coupon.map(VenueCouponEdit.init(coupon:)) ?? VenueCouponEdit()
        super.init(nibName: nil, bundle: nil)
        title = coupon == nil ? "New Coupon" : "Edit Coupon"
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    override func viewDidLoad() {
        super.viewDidLoad()
        view.backgroundColor = Constants.Colors.background
        let stack = VenueFormLayout.install(in: view)

        stack.addArrangedSubview(VenueFormLayout.hintLabel(StoreCouponCopy.explanation))

        titleField.autocapitalizationType = .sentences
        titleField.addTarget(self, action: #selector(fieldsChanged), for: .editingChanged)
        stack.addArrangedSubview(VenueFormLayout.field("What the coupon gives", titleField,
            hint: VenueFormLayout.hintLabel("The big line on the flyer, like \u{201C}20% off any pickup order\u{201D} or \u{201C}Free garlic knots with any pizza\u{201D}.")))

        detailView.delegate = self
        stack.addArrangedSubview(VenueFormLayout.field("Fine print (optional)", detailView,
            hint: VenueFormLayout.hintLabel("\u{201C}Max $20. Pickup only. One per order.\u{201D}")))

        endsPicker.date = draft.expiresAt
        endsPicker.addTarget(self, action: #selector(fieldsChanged), for: .valueChanged)
        stack.addArrangedSubview(VenueFormLayout.field("Last day", VenueFormLayout.toggleRowLike("Good through", endsPicker),
            hint: VenueFormLayout.hintLabel("People who claimed it get a reminder before it ends.")))

        codeField.autocapitalizationType = .allCharacters
        codeField.autocorrectionType = .no
        codeField.addTarget(self, action: #selector(fieldsChanged), for: .editingChanged)
        stack.addArrangedSubview(VenueFormLayout.field("Online code (optional)", codeField,
            hint: VenueFormLayout.hintLabel("The code your own ordering site takes. It shows on the coupon so they can type it there.")))

        campaignField.autocapitalizationType = .sentences
        campaignField.addTarget(self, action: #selector(fieldsChanged), for: .editingChanged)
        stack.addArrangedSubview(VenueFormLayout.field("Campaign (optional)", campaignField,
            hint: VenueFormLayout.hintLabel("Where this QR goes: the November mailer, door hangers, the bag. Insights shows the numbers by campaign.")))

        maxField.addTarget(self, action: #selector(fieldsChanged), for: .editingChanged)
        stack.addArrangedSubview(VenueFormLayout.field("How many may claim it", maxField,
            hint: VenueFormLayout.hintLabel("Leave it blank for no limit. One claim per person either way.")))

        if existing != nil {
            activeSwitch.isOn = draft.isActive
            activeSwitch.addTarget(self, action: #selector(fieldsChanged), for: .valueChanged)
            let toggle = UIStackView(arrangedSubviews: [
                VenueFormLayout.toggleRow("On", activeSwitch),
                VenueFormLayout.hintLabel("Off pauses the QR without losing the coupon. People who already claimed it keep theirs.")
            ])
            toggle.axis = .vertical
            toggle.spacing = 6
            stack.addArrangedSubview(toggle)
        }

        stack.addArrangedSubview(problemLabel)
        saveButton.addTarget(self, action: #selector(saveTapped), for: .touchUpInside)
        stack.addArrangedSubview(saveButton)

        if existing == nil { titleField.becomeFirstResponder() }
    }

    @objc private func fieldsChanged() {
        draft.title = titleField.text ?? ""
        draft.detail = detailView.text ?? ""
        draft.onlineCode = codeField.text ?? ""
        draft.campaign = campaignField.text ?? ""
        draft.maxClaimsText = maxField.text ?? ""
        draft.expiresAt = endsPicker.date
        draft.isActive = existing == nil || activeSwitch.isOn
        problemLabel.isHidden = true
    }

    @objc private func saveTapped() {
        fieldsChanged()
        if let problem = draft.problem() {
            problemLabel.text = problem
            problemLabel.isHidden = false
            return
        }
        view.endEditing(true)
        saveButton.isEnabled = false
        let done: (Result<VenueCouponSaved, Error>) -> Void = { [weak self] result in
            DispatchQueue.main.async {
                guard let self else { return }
                self.saveButton.isEnabled = true
                switch result {
                case .success(let saved):
                    let created = self.existing == nil ? saved.coupon : nil
                    self.onSaved?(saved.coupons, created)
                    self.navigationController?.popViewController(animated: true)
                case .failure(let error):
                    self.problemLabel.text = FriendlyError.message(for: error)
                    self.problemLabel.isHidden = false
                }
            }
        }
        if let coupon = existing {
            RewardsService.shared.updateCoupon(venueId: venueId, couponId: coupon.couponId, body: draft.asBody, completion: done)
        } else {
            RewardsService.shared.createCoupon(venueId: venueId, draft: draft, completion: done)
        }
    }
}

extension VenueCouponFormViewController: UITextViewDelegate {
    func textViewDidChange(_ textView: UITextView) { fieldsChanged() }
}

extension VenueFormLayout {
    /// Title on the left, a compact control (a date picker) on the right
    static func toggleRowLike(_ title: String, _ control: UIView) -> UIView {
        let label = UILabel()
        label.text = title
        label.font = .systemFont(ofSize: 15, weight: .semibold)
        let row = UIStackView(arrangedSubviews: [label, control])
        row.alignment = .center
        return row
    }
}

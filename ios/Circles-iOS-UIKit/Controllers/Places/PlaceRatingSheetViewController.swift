import UIKit

/// One-tap 0–10 rating sheet: tap a pill and `onContinue` fires with the
/// score, or Skip for nil. Used on Save (Add Place — the save continues),
/// from the place page (change your rating) and after a check-in
/// ("How was it this time?"). Reviews are not collected here — they are
/// comments on the venue.
class PlaceRatingSheetViewController: UIViewController {

    /// Called after the sheet dismisses.
    var onContinue: ((_ rating: Int?) -> Void)?

    private let placeName: String
    private let titleText: String
    private let subtitleText: String
    private let currentRating: Int?

    init(placeName: String, title: String? = nil, subtitle: String? = nil, currentRating: Int? = nil) {
        self.placeName = placeName
        self.titleText = title ?? "How was \(placeName)?"
        self.subtitleText = subtitle ?? "Tap a rating to save"
        self.currentRating = currentRating
        super.init(nibName: nil, bundle: nil)
    }

    /// Standard presentation: compact page sheet (240pt detent on iOS 16+).
    static func present(_ sheet: PlaceRatingSheetViewController, from presenter: UIViewController) {
        sheet.modalPresentationStyle = .pageSheet
        if let sheetController = sheet.sheetPresentationController {
            if #available(iOS 16.0, *) {
                sheetController.detents = [.custom { _ in 240 }]
            } else {
                sheetController.detents = [.medium()]
            }
            sheetController.prefersGrabberVisible = true
        }
        presenter.present(sheet, animated: true)
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    // MARK: - UI

    private lazy var titleLabel: UILabel = {
        let label = UILabel()
        label.text = titleText
        label.font = UIFont.systemFont(ofSize: 20, weight: .bold)
        label.textColor = Constants.Colors.label
        label.numberOfLines = 2
        label.textAlignment = .center
        return label
    }()

    private lazy var ratingPromptLabel: UILabel = {
        let label = UILabel()
        label.text = subtitleText
        label.font = UIFont.systemFont(ofSize: 14, weight: .medium)
        label.textColor = Constants.Colors.secondaryLabel
        label.textAlignment = .center
        return label
    }()

    private lazy var ratingStack: UIStackView = {
        let stack = UIStackView()
        stack.axis = .horizontal
        stack.spacing = 4
        stack.distribution = .fillEqually
        for value in 0...10 {
            let button = UIButton(type: .system)
            button.setTitle("\(value)", for: .normal)
            button.titleLabel?.font = UIFont.systemFont(ofSize: 16, weight: .semibold)
            button.setTitleColor(Constants.Colors.label, for: .normal)
            button.backgroundColor = Constants.Colors.secondaryBackground
            button.layer.cornerRadius = 8
            if value == currentRating {
                // The score they gave last time, outlined so "keep it" is obvious
                button.layer.borderWidth = 2
                button.layer.borderColor = Constants.Colors.primary.cgColor
            }
            button.tag = value
            button.heightAnchor.constraint(equalToConstant: 44).isActive = true
            button.addTarget(self, action: #selector(ratingPillTapped(_:)), for: .touchUpInside)
            stack.addArrangedSubview(button)
        }
        return stack
    }()

    private lazy var skipButton: UIButton = {
        let button = UIButton(type: .system)
        button.setTitle("Skip", for: .normal)
        button.titleLabel?.font = UIFont.systemFont(ofSize: 16, weight: .medium)
        button.setTitleColor(Constants.Colors.secondaryLabel, for: .normal)
        button.addTarget(self, action: #selector(skipTapped), for: .touchUpInside)
        return button
    }()

    // MARK: - Lifecycle

    override func viewDidLoad() {
        super.viewDidLoad()
        view.backgroundColor = Constants.Colors.background

        let stack = UIStackView(arrangedSubviews: [
            titleLabel, ratingPromptLabel, ratingStack, skipButton
        ])
        stack.axis = .vertical
        stack.spacing = 16
        stack.setCustomSpacing(6, after: titleLabel)
        stack.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(stack)

        NSLayoutConstraint.activate([
            stack.topAnchor.constraint(equalTo: view.topAnchor, constant: 28),
            stack.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: 20),
            stack.trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: -20)
        ])
    }

    // MARK: - Actions

    @objc private func ratingPillTapped(_ sender: UIButton) {
        // Flash the selection so the tap reads, then continue the save
        sender.backgroundColor = Constants.Colors.primary
        sender.setTitleColor(.white, for: .normal)
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.15) { [weak self] in
            self?.finish(rating: sender.tag)
        }
    }

    @objc private func skipTapped() {
        finish(rating: nil)
    }

    private func finish(rating: Int?) {
        // Dismiss first — the presenter immediately shows its own
        // "Checking..." alert and can't while this sheet is up
        dismiss(animated: true) { [onContinue] in
            onContinue?(rating)
        }
    }
}

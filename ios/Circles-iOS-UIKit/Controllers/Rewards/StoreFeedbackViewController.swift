import UIKit

/// "Tell <store> privately" (2026-11-02): 1–5 stars and an optional note that
/// only the store's team reads (Manage Store → Private feedback, plus a push).
/// Not a public review — that's the place's comments.
final class StoreFeedbackViewController: BaseViewController, UITextViewDelegate {

    private let venueId: String
    private let venueName: String
    private var rating = 0

    override var loadsDataOnViewDidLoad: Bool { false }
    override var showsLoadingIndicator: Bool { false }

    private lazy var starButtons: [UIButton] = (1...5).map { index in
        let button = UIButton.iconButton(systemName: "star", pointSize: 30)
        button.tag = index
        button.tintColor = .systemOrange
        button.accessibilityLabel = "\(index) star\(index == 1 ? "" : "s")"
        button.addTarget(self, action: #selector(starTapped(_:)), for: .touchUpInside)
        return button
    }

    private let noteView: UITextView = {
        let view = UITextView()
        view.font = .systemFont(ofSize: 16)
        view.backgroundColor = .secondarySystemBackground
        view.layer.cornerRadius = 10
        view.textContainerInset = UIEdgeInsets(top: 10, left: 8, bottom: 10, right: 8)
        view.heightAnchor.constraint(equalToConstant: 120).isActive = true
        return view
    }()

    private let placeholderLabel: UILabel = {
        let label = UILabel()
        label.text = "Anything they should know? (optional)"
        label.font = .systemFont(ofSize: 16)
        label.textColor = .tertiaryLabel
        label.translatesAutoresizingMaskIntoConstraints = false
        return label
    }()

    private lazy var sendButton = UIButton.primaryButton(title: "Send to \(venueName)")

    init(venueId: String, venueName: String) {
        self.venueId = venueId
        self.venueName = venueName
        super.init(nibName: nil, bundle: nil)
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    override func viewDidLoad() {
        super.viewDidLoad()
        view.backgroundColor = .systemBackground

        let titleLabel = UILabel()
        titleLabel.text = "Tell \(venueName) privately"
        titleLabel.font = .systemFont(ofSize: 22, weight: .bold)
        titleLabel.textColor = Constants.Colors.label
        titleLabel.numberOfLines = 0

        let bodyLabel = UILabel()
        bodyLabel.text = "Only \(venueName)'s team sees this. It isn't posted anywhere."
        bodyLabel.font = .systemFont(ofSize: 15)
        bodyLabel.textColor = .secondaryLabel
        bodyLabel.numberOfLines = 0

        let stars = UIStackView(arrangedSubviews: starButtons)
        stars.spacing = 8
        stars.distribution = .fillEqually
        let starsRow = UIStackView(arrangedSubviews: [stars, UIView()])

        noteView.delegate = self
        noteView.addSubview(placeholderLabel)

        let stack = UIStackView(arrangedSubviews: [titleLabel, bodyLabel, starsRow, noteView, sendButton])
        stack.axis = .vertical
        stack.spacing = 16
        stack.setCustomSpacing(6, after: titleLabel)
        stack.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(stack)
        NSLayoutConstraint.activate([
            stack.topAnchor.constraint(equalTo: view.safeAreaLayoutGuide.topAnchor, constant: 28),
            stack.leadingAnchor.constraint(equalTo: view.safeAreaLayoutGuide.leadingAnchor, constant: 24),
            stack.trailingAnchor.constraint(equalTo: view.safeAreaLayoutGuide.trailingAnchor, constant: -24),
            placeholderLabel.topAnchor.constraint(equalTo: noteView.topAnchor, constant: 10),
            placeholderLabel.leadingAnchor.constraint(equalTo: noteView.leadingAnchor, constant: 13)
        ])

        sendButton.addTarget(self, action: #selector(sendTapped), for: .touchUpInside)
        updateStars()
    }

    @objc private func starTapped(_ sender: UIButton) {
        rating = sender.tag
        updateStars()
    }

    private func updateStars() {
        let config = UIImage.SymbolConfiguration(pointSize: 30, weight: .medium)
        starButtons.forEach { button in
            button.setImage(UIImage(systemName: button.tag <= rating ? "star.fill" : "star", withConfiguration: config), for: .normal)
        }
        sendButton.isEnabled = rating > 0
        sendButton.alpha = rating > 0 ? 1 : 0.4
    }

    func textViewDidChange(_ textView: UITextView) {
        placeholderLabel.isHidden = !textView.text.isEmpty
    }

    @objc private func sendTapped() {
        guard rating > 0 else { return }
        sendButton.isEnabled = false
        let note = noteView.text.trimmingCharacters(in: .whitespacesAndNewlines)
        RewardsService.shared.sendStoreFeedback(venueId: venueId, rating: rating, note: note) { [weak self] result in
            DispatchQueue.main.async {
                guard let self else { return }
                switch result {
                case .success:
                    let host = self.presentingViewController
                    let name = self.venueName
                    self.dismiss(animated: true) {
                        if let host { AlertPresenter.showSuccess(message: "Sent to \(name). Thanks!", from: host) }
                    }
                case .failure(let error):
                    self.sendButton.isEnabled = true
                    self.showError(error)
                }
            }
        }
    }
}

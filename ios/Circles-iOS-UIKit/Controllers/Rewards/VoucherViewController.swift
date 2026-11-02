import UIKit

/// Full-screen reward ticket shown to staff at the counter: the offer, a
/// short code and a 15-minute countdown. Staff tap "Given" on it when they
/// hand the reward over (2026-11-01); a ticket that runs out unclaimed says
/// the points are back (the server refunds them).
class VoucherViewController: BaseViewController {

    // MARK: - Properties

    private var voucher: RewardVoucher
    private var countdownTimer: Timer?
    private var expiryDate: Date

    override var loadsDataOnViewDidLoad: Bool { false }

    // MARK: - UI Elements

    private let cardView: UIView = {
        let view = UIView()
        view.translatesAutoresizingMaskIntoConstraints = false
        view.backgroundColor = .white
        view.layer.cornerRadius = 20
        view.layer.shadowColor = UIColor.black.cgColor
        view.layer.shadowOpacity = 0.2
        view.layer.shadowRadius = 12
        view.layer.shadowOffset = CGSize(width: 0, height: 6)
        return view
    }()

    private let checkmarkImageView: UIImageView = {
        let imageView = UIImageView()
        imageView.translatesAutoresizingMaskIntoConstraints = false
        imageView.image = UIImage(systemName: "checkmark.seal.fill")
        imageView.tintColor = .systemGreen
        imageView.contentMode = .scaleAspectFit
        return imageView
    }()

    private let venueLabel: UILabel = {
        let label = UILabel()
        label.translatesAutoresizingMaskIntoConstraints = false
        label.font = UIFont.systemFont(ofSize: 18, weight: .semibold)
        label.textColor = .darkGray
        label.textAlignment = .center
        label.numberOfLines = 0
        return label
    }()

    private let offerLabel: UILabel = {
        let label = UILabel()
        label.translatesAutoresizingMaskIntoConstraints = false
        label.font = UIFont.systemFont(ofSize: 28, weight: .bold)
        label.textColor = .black
        label.textAlignment = .center
        label.numberOfLines = 0
        return label
    }()

    private let codeLabel: UILabel = {
        let label = UILabel()
        label.translatesAutoresizingMaskIntoConstraints = false
        label.font = UIFont.monospacedSystemFont(ofSize: 44, weight: .heavy)
        label.textColor = Constants.Colors.primary
        label.textAlignment = .center
        return label
    }()

    private let staffInstructionLabel: UILabel = {
        let label = UILabel()
        label.translatesAutoresizingMaskIntoConstraints = false
        label.text = "Show this screen to staff. They tap Given when they hand it over.\nYou can close it and come back: it waits on the store\u{2019}s page and in Store Rewards."
        label.font = UIFont.systemFont(ofSize: 15)
        label.textColor = .gray
        label.textAlignment = .center
        label.numberOfLines = 0
        return label
    }()

    private let countdownLabel: UILabel = {
        let label = UILabel()
        label.translatesAutoresizingMaskIntoConstraints = false
        label.font = UIFont.monospacedDigitSystemFont(ofSize: 32, weight: .bold)
        label.textColor = .white
        label.textAlignment = .center
        return label
    }()

    private let closeButton: UIButton = {
        let button = UIButton(type: .system)
        button.translatesAutoresizingMaskIntoConstraints = false
        let config = UIImage.SymbolConfiguration(pointSize: 28, weight: .semibold)
        button.setImage(UIImage(systemName: "xmark.circle.fill", withConfiguration: config), for: .normal)
        button.tintColor = .white
        button.accessibilityLabel = "Close"
        return button
    }()

    // The factory secondaryButton is primary-on-clear — invisible against this
    // screen's primary-colored background, so style the close action manually
    private let doneButton: UIButton = {
        let button = UIButton(type: .system)
        button.setTitle("Done", for: .normal)
        button.setTitleColor(Constants.Colors.primary, for: .normal)
        button.backgroundColor = .white
        button.layer.cornerRadius = 10
        button.titleLabel?.font = UIFont.systemFont(ofSize: 16, weight: .semibold)
        button.translatesAutoresizingMaskIntoConstraints = false
        button.heightAnchor.constraint(equalToConstant: 50).isActive = true
        return button
    }()

    /// The staff's button; the customer never needs it
    private let givenButton: UIButton = {
        let button = UIButton(type: .system)
        button.setTitle("Staff: tap when given", for: .normal)
        button.setTitleColor(.white, for: .normal)
        button.backgroundColor = .systemGreen
        button.layer.cornerRadius = 10
        button.titleLabel?.font = UIFont.systemFont(ofSize: 17, weight: .bold)
        button.translatesAutoresizingMaskIntoConstraints = false
        button.heightAnchor.constraint(equalToConstant: 54).isActive = true
        return button
    }()

    // MARK: - Init

    init(voucher: RewardVoucher) {
        self.voucher = voucher
        self.expiryDate = voucher.expiryDate ?? Date().addingTimeInterval(15 * 60)
        super.init(nibName: nil, bundle: nil)
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    // MARK: - Lifecycle

    override func viewDidLoad() {
        super.viewDidLoad()
        view.backgroundColor = Constants.Colors.primary

        setupUI()
        venueLabel.text = voucher.venueName
        offerLabel.text = voucher.offerTitle
        codeLabel.text = voucher.voucherCode

        if voucher.status == "given" {
            showGiven()
            return
        }
        // Keep the screen awake while staff verify the voucher
        UIApplication.shared.isIdleTimerDisabled = true
        startCountdown()
    }

    override func viewWillDisappear(_ animated: Bool) {
        super.viewWillDisappear(animated)
        UIApplication.shared.isIdleTimerDisabled = false
        countdownTimer?.invalidate()
        countdownTimer = nil
    }

    // MARK: - Setup

    private func setupUI() {
        view.addSubview(countdownLabel)
        view.addSubview(cardView)
        cardView.addSubview(checkmarkImageView)
        cardView.addSubview(venueLabel)
        cardView.addSubview(offerLabel)
        cardView.addSubview(codeLabel)
        cardView.addSubview(staffInstructionLabel)
        view.addSubview(givenButton)
        view.addSubview(doneButton)
        view.addSubview(closeButton)

        givenButton.addTarget(self, action: #selector(givenTapped), for: .touchUpInside)
        doneButton.addTarget(self, action: #selector(doneTapped), for: .touchUpInside)
        closeButton.addTarget(self, action: #selector(doneTapped), for: .touchUpInside)

        NSLayoutConstraint.activate([
            closeButton.topAnchor.constraint(equalTo: view.safeAreaLayoutGuide.topAnchor, constant: 16),
            closeButton.trailingAnchor.constraint(equalTo: view.safeAreaLayoutGuide.trailingAnchor, constant: -20),
            closeButton.widthAnchor.constraint(equalToConstant: 40),
            closeButton.heightAnchor.constraint(equalToConstant: 40),

            countdownLabel.topAnchor.constraint(equalTo: view.safeAreaLayoutGuide.topAnchor, constant: 30),
            countdownLabel.centerXAnchor.constraint(equalTo: view.centerXAnchor),

            cardView.centerYAnchor.constraint(equalTo: view.centerYAnchor, constant: -20),
            cardView.leadingAnchor.constraint(equalTo: view.safeAreaLayoutGuide.leadingAnchor, constant: 24),
            cardView.trailingAnchor.constraint(equalTo: view.safeAreaLayoutGuide.trailingAnchor, constant: -24),

            checkmarkImageView.topAnchor.constraint(equalTo: cardView.topAnchor, constant: 28),
            checkmarkImageView.centerXAnchor.constraint(equalTo: cardView.centerXAnchor),
            checkmarkImageView.widthAnchor.constraint(equalToConstant: 56),
            checkmarkImageView.heightAnchor.constraint(equalToConstant: 56),

            venueLabel.topAnchor.constraint(equalTo: checkmarkImageView.bottomAnchor, constant: 14),
            venueLabel.leadingAnchor.constraint(equalTo: cardView.leadingAnchor, constant: 20),
            venueLabel.trailingAnchor.constraint(equalTo: cardView.trailingAnchor, constant: -20),

            offerLabel.topAnchor.constraint(equalTo: venueLabel.bottomAnchor, constant: 8),
            offerLabel.leadingAnchor.constraint(equalTo: cardView.leadingAnchor, constant: 20),
            offerLabel.trailingAnchor.constraint(equalTo: cardView.trailingAnchor, constant: -20),

            codeLabel.topAnchor.constraint(equalTo: offerLabel.bottomAnchor, constant: 20),
            codeLabel.centerXAnchor.constraint(equalTo: cardView.centerXAnchor),

            staffInstructionLabel.topAnchor.constraint(equalTo: codeLabel.bottomAnchor, constant: 20),
            staffInstructionLabel.leadingAnchor.constraint(equalTo: cardView.leadingAnchor, constant: 20),
            staffInstructionLabel.trailingAnchor.constraint(equalTo: cardView.trailingAnchor, constant: -20),
            staffInstructionLabel.bottomAnchor.constraint(equalTo: cardView.bottomAnchor, constant: -28),

            givenButton.bottomAnchor.constraint(equalTo: doneButton.topAnchor, constant: -12),
            givenButton.leadingAnchor.constraint(equalTo: view.safeAreaLayoutGuide.leadingAnchor, constant: 40),
            givenButton.trailingAnchor.constraint(equalTo: view.safeAreaLayoutGuide.trailingAnchor, constant: -40),

            doneButton.bottomAnchor.constraint(equalTo: view.safeAreaLayoutGuide.bottomAnchor, constant: -20),
            doneButton.leadingAnchor.constraint(equalTo: view.safeAreaLayoutGuide.leadingAnchor, constant: 40),
            doneButton.trailingAnchor.constraint(equalTo: view.safeAreaLayoutGuide.trailingAnchor, constant: -40)
        ])
    }

    // MARK: - Countdown

    private func startCountdown() {
        updateCountdown()
        countdownTimer = Timer.scheduledTimer(withTimeInterval: 1.0, repeats: true) { [weak self] _ in
            self?.updateCountdown()
        }
    }

    private func updateCountdown() {
        let remaining = Int(expiryDate.timeIntervalSinceNow)

        guard remaining > 0 else {
            countdownTimer?.invalidate()
            countdownTimer = nil
            countdownLabel.text = "Time\u{2019}s up"
            codeLabel.textColor = .lightGray
            offerLabel.textColor = .lightGray
            givenButton.isHidden = true
            checkmarkImageView.image = UIImage(systemName: "arrow.uturn.backward.circle.fill")
            checkmarkImageView.tintColor = .systemOrange
            staffInstructionLabel.text = "This reward wasn\u{2019}t marked as given, so your \(voucher.pointsCost) points are back at \(voucher.venueName)."
            RewardsService.shared.clearActiveVoucher()
            // The server refunds on this read; every points display refreshes
            RewardsService.shared.fetchRewardTickets { _ in }
            return
        }

        let minutes = remaining / 60
        let seconds = remaining % 60
        countdownLabel.text = String(format: "%d:%02d", minutes, seconds)

        if remaining <= 30 {
            countdownLabel.textColor = .systemYellow
        }
    }

    // MARK: - Given

    @objc private func givenTapped() {
        AlertPresenter.showConfirmation(
            title: "Hand over \(voucher.offerTitle)?",
            message: "For staff: this marks the reward as given. It can\u{2019}t be used again.",
            confirmTitle: "Given",
            from: self
        ) { [weak self] in
            guard let self else { return }
            self.givenButton.isEnabled = false
            RewardsService.shared.markRewardGiven(self.voucher) { result in
                DispatchQueue.main.async {
                    switch result {
                    case .success(let given):
                        self.voucher.status = "given"
                        self.voucher.givenAt = given.givenAt ?? ISO8601DateFormatter().string(from: Date())
                        UINotificationFeedbackGenerator().notificationOccurred(.success)
                        self.showGiven()
                        RewardsService.postBalanceChanged()
                    case .failure(let error):
                        self.givenButton.isEnabled = true
                        self.showError(error)
                    }
                }
            }
        }
    }

    /// Green "Given ✓ 5:54 PM": the reward was handed over
    private func showGiven() {
        countdownTimer?.invalidate()
        countdownTimer = nil
        UIApplication.shared.isIdleTimerDisabled = false
        view.backgroundColor = .systemGreen
        countdownLabel.textColor = .white
        countdownLabel.text = "Given \u{2713}"
        givenButton.isHidden = true
        checkmarkImageView.image = UIImage(systemName: "checkmark.circle.fill")
        checkmarkImageView.tintColor = .systemGreen
        codeLabel.textColor = .lightGray
        let time = Self.givenTime(voucher.givenAt).map { " at \($0)" } ?? ""
        staffInstructionLabel.text = "Given\(time). Enjoy!"
        doneButton.setTitleColor(.systemGreen, for: .normal)
    }

    private static func givenTime(_ iso: String?) -> String? {
        guard let iso else { return nil }
        let parser = ISO8601DateFormatter()
        parser.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        let date = parser.date(from: iso) ?? ISO8601DateFormatter().date(from: iso)
        return date.map { DateFormatter.localizedString(from: $0, dateStyle: .none, timeStyle: .short) }
    }

    // MARK: - Actions

    @objc private func doneTapped() {
        dismiss(animated: true)
    }
}

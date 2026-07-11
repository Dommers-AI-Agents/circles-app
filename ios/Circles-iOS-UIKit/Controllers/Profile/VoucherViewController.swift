import UIKit

/// Full-screen redemption voucher shown to venue staff at the counter.
/// Displays the offer, a short confirmation code, and a 5-minute countdown;
/// dismisses itself when the voucher expires.
class VoucherViewController: BaseViewController {

    // MARK: - Properties

    private let voucher: RewardVoucher
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
        label.text = "Show this screen to staff\nbefore it expires"
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

    private let doneButton = UIButton.secondaryButton(title: "Done")

    // MARK: - Init

    init(voucher: RewardVoucher) {
        self.voucher = voucher

        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        if let date = formatter.date(from: voucher.expiresAt) {
            self.expiryDate = date
        } else {
            formatter.formatOptions = [.withInternetDateTime]
            self.expiryDate = formatter.date(from: voucher.expiresAt) ?? Date().addingTimeInterval(5 * 60)
        }

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
        view.addSubview(doneButton)

        doneButton.addTarget(self, action: #selector(doneTapped), for: .touchUpInside)

        NSLayoutConstraint.activate([
            countdownLabel.topAnchor.constraint(equalTo: view.safeAreaLayoutGuide.topAnchor, constant: 30),
            countdownLabel.centerXAnchor.constraint(equalTo: view.centerXAnchor),

            cardView.centerYAnchor.constraint(equalTo: view.centerYAnchor, constant: -20),
            cardView.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: 24),
            cardView.trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: -24),

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

            doneButton.bottomAnchor.constraint(equalTo: view.safeAreaLayoutGuide.bottomAnchor, constant: -20),
            doneButton.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: 40),
            doneButton.trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: -40)
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
            countdownLabel.text = "Expired"
            codeLabel.textColor = .lightGray
            offerLabel.textColor = .lightGray

            DispatchQueue.main.asyncAfter(deadline: .now() + 2.0) { [weak self] in
                self?.dismiss(animated: true)
            }
            return
        }

        let minutes = remaining / 60
        let seconds = remaining % 60
        countdownLabel.text = String(format: "%d:%02d", minutes, seconds)

        if remaining <= 30 {
            countdownLabel.textColor = .systemYellow
        }
    }

    // MARK: - Actions

    @objc private func doneTapped() {
        dismiss(animated: true)
    }
}

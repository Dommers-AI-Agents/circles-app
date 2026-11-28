import UIKit
import StoreKit

/// The reward ticket in the clip (2026-11-28: the clip alone is the punch
/// card, no app needed): who it's for, the reward, a short code and a
/// 15-minute countdown. Staff tap Given on this phone when they hand it over;
/// a ticket that runs out unused says the points are back (the server
/// refunds them). Same rules as the app's VoucherViewController.
final class ClipRewardTicketViewController: UIViewController {

    private var voucher: ClipVoucher
    private let session: ClipSession
    private var timer: Timer?
    /// Closed: the ticket as it ended (given, expired or still open)
    var onClose: ((ClipVoucher) -> Void)?

    private let card = UIView()
    private let badge = UIImageView()
    private let forLabel = UILabel()
    private let storeLabel = UILabel()
    private let offerLabel = UILabel()
    private let codeLabel = UILabel()
    private let countdownLabel = UILabel()
    private let instructionLabel = UILabel()
    private let givenButton = ClipTheme.primaryButton("Given")
    private let doneButton = ClipTheme.linkButton("Done")

    init(voucher: ClipVoucher, session: ClipSession) {
        self.voucher = voucher
        self.session = session
        super.init(nibName: nil, bundle: nil)
        modalPresentationStyle = .fullScreen
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    override var preferredStatusBarStyle: UIStatusBarStyle { .lightContent }

    override func viewDidLoad() {
        super.viewDidLoad()
        view.backgroundColor = ClipTheme.ink
        setupUI()
        if voucher.status == "given" {
            showGiven()
        } else {
            startCountdown()
        }
        #if DEBUG
        // Simulator runs (CLIP_AUTOPILOT_REDEEM=1): staff tap Given after a beat
        if ProcessInfo.processInfo.environment["CLIP_AUTOPILOT_REDEEM"] == "1", voucher.status != "given" {
            DispatchQueue.main.asyncAfter(deadline: .now() + 4) { [weak self] in self?.markGiven() }
        }
        #endif
    }

    override func viewDidAppear(_ animated: Bool) {
        super.viewDidAppear(animated)
        // A clean screen for the counter: no "Get the full app" banner over it
        if let scene = view.window?.windowScene { SKOverlay.dismiss(in: scene) }
    }

    override func viewWillDisappear(_ animated: Bool) {
        super.viewWillDisappear(animated)
        timer?.invalidate()
        timer = nil
    }

    private func setupUI() {
        card.backgroundColor = .white
        card.layer.cornerRadius = 22
        card.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(card)

        badge.image = UIImage(systemName: "checkmark.seal.fill")
        badge.tintColor = .systemGreen
        badge.contentMode = .scaleAspectFit
        badge.heightAnchor.constraint(equalToConstant: 52).isActive = true

        let name = session.displayName?.trimmingCharacters(in: .whitespaces) ?? ""
        forLabel.text = name.isEmpty ? "Reward ticket" : "For \(name)"
        forLabel.font = .systemFont(ofSize: 22, weight: .bold)
        storeLabel.text = voucher.venueName
        storeLabel.font = .systemFont(ofSize: 18, weight: .semibold)
        storeLabel.textColor = .darkGray
        offerLabel.text = voucher.offerTitle
        offerLabel.font = .systemFont(ofSize: 30, weight: .bold)
        codeLabel.text = voucher.voucherCode
        codeLabel.font = .monospacedSystemFont(ofSize: 44, weight: .heavy)
        codeLabel.textColor = ClipTheme.pinRed
        codeLabel.adjustsFontSizeToFitWidth = true
        countdownLabel.font = .monospacedDigitSystemFont(ofSize: 22, weight: .semibold)
        countdownLabel.textColor = .darkGray
        instructionLabel.text = "Show this screen to staff. They tap Given when they hand it over.\nYou can close it: scan the store's code again and it's still here."
        instructionLabel.font = .systemFont(ofSize: 15)
        instructionLabel.textColor = .gray
        for label in [forLabel, storeLabel, offerLabel, codeLabel, countdownLabel, instructionLabel] {
            label.textAlignment = .center
            label.numberOfLines = 0
        }
        codeLabel.numberOfLines = 1
        forLabel.textColor = .black
        offerLabel.textColor = .black

        let stack = UIStackView(arrangedSubviews: [badge, forLabel, storeLabel, offerLabel, codeLabel, countdownLabel, instructionLabel])
        stack.axis = .vertical
        stack.spacing = 10
        stack.setCustomSpacing(18, after: storeLabel)
        stack.setCustomSpacing(18, after: countdownLabel)
        stack.translatesAutoresizingMaskIntoConstraints = false
        card.addSubview(stack)

        givenButton.addTarget(self, action: #selector(givenTapped), for: .touchUpInside)
        doneButton.addTarget(self, action: #selector(doneTapped), for: .touchUpInside)
        let buttons = UIStackView(arrangedSubviews: [givenButton, doneButton])
        buttons.axis = .vertical
        buttons.spacing = 8
        buttons.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(buttons)

        NSLayoutConstraint.activate([
            card.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: 20),
            card.trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: -20),
            card.centerYAnchor.constraint(equalTo: view.centerYAnchor, constant: -60),
            card.topAnchor.constraint(greaterThanOrEqualTo: view.safeAreaLayoutGuide.topAnchor, constant: 12),
            stack.topAnchor.constraint(equalTo: card.topAnchor, constant: 24),
            stack.leadingAnchor.constraint(equalTo: card.leadingAnchor, constant: 20),
            stack.trailingAnchor.constraint(equalTo: card.trailingAnchor, constant: -20),
            stack.bottomAnchor.constraint(equalTo: card.bottomAnchor, constant: -24),
            buttons.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: 24),
            buttons.trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: -24),
            // Right under the card: the bottom of the screen is where the
            // App Store banner sits, and staff need Given in plain sight
            buttons.topAnchor.constraint(equalTo: card.bottomAnchor, constant: 16)
        ])
    }

    // MARK: - Countdown

    private func startCountdown() {
        updateCountdown()
        timer = Timer.scheduledTimer(withTimeInterval: 1, repeats: true) { [weak self] _ in self?.updateCountdown() }
    }

    private func updateCountdown() {
        let remaining = Int((voucher.expiryDate ?? Date()).timeIntervalSinceNow)
        guard remaining > 0 else {
            timer?.invalidate()
            timer = nil
            countdownLabel.text = "Time's up"
            codeLabel.textColor = .lightGray
            offerLabel.textColor = .lightGray
            givenButton.isHidden = true
            badge.image = UIImage(systemName: "arrow.uturn.backward.circle.fill")
            badge.tintColor = .systemOrange
            instructionLabel.text = voucher.couponId != nil
                ? "This ticket ran out before it was used."
                : "This reward wasn't marked as given, so your \(voucher.pointsCost) points are back at \(voucher.venueName)."
            // The server refunds on this read
            Task { _ = try? await ClipAPIClient.shared.openTickets(bearer: session.token) }
            return
        }
        countdownLabel.text = String(format: "%d:%02d left", remaining / 60, remaining % 60)
        countdownLabel.textColor = remaining <= 30 ? .systemOrange : .darkGray
    }

    // MARK: - Given

    @objc private func givenTapped() {
        let alert = UIAlertController(title: "Hand over \(voucher.offerTitle)?",
                                      message: "For staff: this marks the reward as given. It can't be used again.",
                                      preferredStyle: .alert)
        alert.addAction(UIAlertAction(title: "Cancel", style: .cancel))
        alert.addAction(UIAlertAction(title: "Given", style: .default) { [weak self] _ in self?.markGiven() })
        present(alert, animated: true)
    }

    private func markGiven() {
        guard let voucherId = voucher.voucherId else { return }
        givenButton.isEnabled = false
        Task { @MainActor in
            do {
                let given = try await ClipAPIClient.shared.markGiven(voucherId: voucherId, bearer: session.token)
                voucher.status = "given"
                voucher.givenAt = given.givenAt ?? ISO8601DateFormatter().string(from: Date())
                UINotificationFeedbackGenerator().notificationOccurred(.success)
                showGiven()
            } catch {
                givenButton.isEnabled = true
                let alert = UIAlertController(title: "Couldn't mark it given", message: error.localizedDescription, preferredStyle: .alert)
                alert.addAction(UIAlertAction(title: "OK", style: .default))
                present(alert, animated: true)
            }
        }
    }

    /// Green "Given ✓": the reward was handed over
    private func showGiven() {
        timer?.invalidate()
        timer = nil
        badge.image = UIImage(systemName: "checkmark.seal.fill")
        badge.tintColor = .systemGreen
        countdownLabel.text = "Given ✓"
        countdownLabel.textColor = .systemGreen
        givenButton.isHidden = true
        var time = ""
        if let date = ClipVoucher.date(voucher.givenAt) {
            time = " at " + DateFormatter.localizedString(from: date, dateStyle: .none, timeStyle: .short)
        }
        instructionLabel.text = "Given\(time). Enjoy!"
    }

    @objc private func doneTapped() {
        let ended = voucher
        dismiss(animated: true) { [onClose] in onClose?(ended) }
    }
}

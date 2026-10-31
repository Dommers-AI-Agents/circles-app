import UIKit
import StoreKit

// After sign-in, and on every later scan by someone the clip knows: redeem
// the code, then show what they earned here, how to keep earning and what the
// store's points buy (Wes, 2026-10-31), over the store's photo. Hands the
// session to the full app and offers it via SKOverlay.
final class ClipSuccessViewController: UIViewController {

    private let session: ClipSession
    private let isNewSignIn: Bool
    private let invocation: ClipInvocation
    private let code: String
    private let preview: VenuePreview

    private let backdrop = ClipBackdropView()
    private let brandMark = ClipTheme.brandMarkView(side: 40)
    private let stack = UIStackView()
    private let hookLabel = ClipTheme.label(ClipTheme.serif(46))
    private let nameLabel = ClipTheme.label(.systemFont(ofSize: 22, weight: .semibold))
    private let detailLabel = ClipTheme.label(.systemFont(ofSize: 17), color: UIColor.white.withAlphaComponent(0.9))
    private let panel = UIVisualEffectView(effect: UIBlurEffect(style: .systemUltraThinMaterialDark))
    private let panelStack = UIStackView()
    private let getAppButton = ClipTheme.primaryButton("Get the FavCircles app")
    private let signOutButton = ClipTheme.linkButton("")
    private let spinner = UIActivityIndicatorView(style: .large)
    private var overlayPresented = false

    init(session: ClipSession, isNewSignIn: Bool, invocation: ClipInvocation, code: String, preview: VenuePreview) {
        self.session = session
        self.isNewSignIn = isNewSignIn
        self.invocation = invocation
        self.code = code
        self.preview = preview
        super.init(nibName: nil, bundle: nil)
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    override var preferredStatusBarStyle: UIStatusBarStyle { .lightContent }

    override func viewDidLoad() {
        super.viewDidLoad()
        view.backgroundColor = ClipTheme.ink
        navigationController?.setNavigationBarHidden(true, animated: false)
        setupUI()
        backdrop.loadPhoto(from: preview.coverUrl.flatMap(URL.init(string:)))

        // Hand the session to the full app FIRST — even if the scan call fails,
        // the install lands logged in.
        ClipHandoff.storeAuthHandoff(session: session)
        ClipNotifications.shared.register(session: session, code: code)

        if preview.isGeneric {
            // Generic join: nothing to redeem — the welcome gifts are claimed in
            // the full app. Mark the code handled so the full app's first launch
            // doesn't re-run the sticker flow on it.
            ClipHandoff.markStickerHandled(code)
            showGenericWelcome()
        } else {
            redeem()
        }
    }

    private func setupUI() {
        view.addSubview(backdrop)
        view.addSubview(brandMark)

        stack.axis = .vertical
        stack.spacing = 10
        stack.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(stack)

        hookLabel.adjustsFontSizeToFitWidth = true
        hookLabel.minimumScaleFactor = 0.7
        [hookLabel, nameLabel, detailLabel].forEach(ClipTheme.lift)

        panel.layer.cornerRadius = 18
        panel.layer.masksToBounds = true
        panel.layer.borderWidth = 1
        panel.layer.borderColor = UIColor.white.withAlphaComponent(0.18).cgColor
        panelStack.axis = .vertical
        panelStack.spacing = 10
        panelStack.translatesAutoresizingMaskIntoConstraints = false
        panel.contentView.addSubview(panelStack)
        panel.isHidden = true

        getAppButton.addTarget(self, action: #selector(getAppTapped), for: .touchUpInside)
        let firstName = session.displayName?.split(separator: " ").first.map(String.init)
        signOutButton.configuration?.attributedTitle = AttributedString(
            firstName.map { "Not \($0)? Sign out" } ?? "Not you? Sign out",
            attributes: AttributeContainer([.font: UIFont.systemFont(ofSize: 15, weight: .medium)]))
        signOutButton.addTarget(self, action: #selector(signOutTapped), for: .touchUpInside)

        [hookLabel, nameLabel, detailLabel, panel, getAppButton, signOutButton].forEach { stack.addArrangedSubview($0) }
        stack.setCustomSpacing(14, after: hookLabel)
        stack.setCustomSpacing(6, after: nameLabel)
        stack.setCustomSpacing(18, after: detailLabel)
        stack.setCustomSpacing(18, after: panel)
        stack.setCustomSpacing(4, after: getAppButton)
        stack.isHidden = true

        spinner.color = .white
        spinner.translatesAutoresizingMaskIntoConstraints = false
        spinner.startAnimating()
        view.addSubview(spinner)

        NSLayoutConstraint.activate([
            backdrop.topAnchor.constraint(equalTo: view.topAnchor),
            backdrop.bottomAnchor.constraint(equalTo: view.bottomAnchor),
            backdrop.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            backdrop.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            brandMark.topAnchor.constraint(equalTo: view.safeAreaLayoutGuide.topAnchor, constant: 12),
            brandMark.leadingAnchor.constraint(equalTo: view.safeAreaLayoutGuide.leadingAnchor, constant: 24),
            panelStack.topAnchor.constraint(equalTo: panel.contentView.topAnchor, constant: 16),
            panelStack.bottomAnchor.constraint(equalTo: panel.contentView.bottomAnchor, constant: -16),
            panelStack.leadingAnchor.constraint(equalTo: panel.contentView.leadingAnchor, constant: 18),
            panelStack.trailingAnchor.constraint(equalTo: panel.contentView.trailingAnchor, constant: -18),
            stack.bottomAnchor.constraint(equalTo: view.safeAreaLayoutGuide.bottomAnchor, constant: -8),
            stack.leadingAnchor.constraint(equalTo: view.safeAreaLayoutGuide.leadingAnchor, constant: 26),
            stack.trailingAnchor.constraint(equalTo: view.safeAreaLayoutGuide.trailingAnchor, constant: -26),
            stack.topAnchor.constraint(greaterThanOrEqualTo: brandMark.bottomAnchor, constant: 16),
            spinner.centerXAnchor.constraint(equalTo: view.centerXAnchor),
            spinner.centerYAnchor.constraint(equalTo: view.centerYAnchor)
        ])
    }

    // MARK: - Redeem

    private func redeem() {
        Task { @MainActor in
            // Register codes: Apple can confirm the phone is at the store
            // (no prompt). Only a clear "not here" withholds the visit points.
            var atStore: Bool?
            if preview.kind == "register", preview.loyaltyLive == true {
                atStore = await invocation.confirmAtStore(latitude: preview.location?.latitude,
                                                          longitude: preview.location?.longitude)
            }
            do {
                let result = try await ClipAPIClient.shared.redeemSticker(code: code, token: session.token, atStore: atStore)
                // Scan handled in-clip — tell the full app not to redeem it again
                ClipHandoff.markStickerHandled(code, welcome: result.venue.map { venue in
                    ClipHandoff.Welcome(code: code, kind: result.kind, venue: venue,
                                        awardedPoints: result.awarded?.points,
                                        venueBalance: result.venueBalance,
                                        earnRate: result.earnRate ?? preview.earnRate,
                                        offers: preview.offers ?? [],
                                        nextRewardLine: result.nextRewardLine,
                                        alreadySaved: result.alreadySaved)
                })
                show(result)
            } catch ClipAPIError.unauthorized {
                // The remembered session ran out: sign in again
                ClipSession.clear()
                navigationController?.setViewControllers([ClipOfferViewController(invocation: invocation)], animated: true)
            } catch {
                // Let the full app's existing pending-sticker flow finish the award
                ClipHandoff.markStickerPending(code)
                showPending()
            }
        }
    }

    // MARK: - Results

    private func show(_ result: ScanResult) {
        let name = preview.venueName
        let earnsHere = preview.kind == "register" && preview.loyaltyLive == true
        let balance = result.venueBalance ?? 0
        let hello = isNewSignIn ? "You're in." : "Welcome back."
        nameLabel.text = name

        if let award = result.awarded {
            hookLabel.attributedText = ClipTheme.hookText(hello, "+\(award.points) points.", size: 46)
            detailLabel.text = "You have \(balance) points at \(name)."
        } else if result.notAtStore == true {
            hookLabel.attributedText = ClipTheme.hookText("Almost.", "Scan it at the counter.", size: 46)
            detailLabel.text = "Visit points are for scans at \(name). Scan the code at the register on your next visit."
        } else if result.alreadyEarnedToday == true {
            hookLabel.attributedText = ClipTheme.hookText("Welcome back.", "See you next visit.", size: 46)
            detailLabel.text = "You've collected today's points here. You have \(balance) points at \(name)."
        } else {
            // Window code, or a store whose rewards aren't live: nothing to pay out
            hookLabel.attributedText = ClipTheme.hookText(hello, "One step left.", size: 46)
            detailLabel.text = "Get the FavCircles app to save \(name) to your map. It opens right on \(name)'s page."
        }

        if earnsHere {
            fillRewardsPanel(balance: balance, earnRate: result.earnRate ?? preview.earnRate, nextLine: result.nextRewardLine)
        }
        reveal(celebrate: result.awarded != nil)
    }

    /// How to keep earning, and what the points buy here
    private func fillRewardsPanel(balance: Int, earnRate: Int?, nextLine: String?) {
        panelStack.arrangedSubviews.forEach { $0.removeFromSuperview() }
        let heading = ClipTheme.label(.systemFont(ofSize: 13, weight: .bold), color: ClipTheme.gold)
        heading.text = "KEEP EARNING"
        panelStack.addArrangedSubview(heading)
        if let earnRate {
            let how = ClipTheme.label(.systemFont(ofSize: 16, weight: .medium))
            how.text = "Every visit earns \(earnRate) points. Scan the code at the register."
            panelStack.addArrangedSubview(how)
        }
        let offers = (preview.offers ?? []).sorted { $0.pointsCost < $1.pointsCost }.prefix(4)
        if !offers.isEmpty {
            let rewards = ClipTheme.label(.systemFont(ofSize: 13, weight: .bold), color: ClipTheme.gold)
            rewards.text = "REWARDS HERE"
            panelStack.setCustomSpacing(16, after: panelStack.arrangedSubviews.last!)
            panelStack.addArrangedSubview(rewards)
            for offer in offers {
                panelStack.addArrangedSubview(rewardRow(offer, balance: balance))
            }
        }
        if let nextLine {
            let next = ClipTheme.label(.systemFont(ofSize: 14), color: UIColor.white.withAlphaComponent(0.8))
            next.text = nextLine
            panelStack.addArrangedSubview(next)
        }
        panel.isHidden = false
    }

    /// "Free croissant · 100 points" with a bar showing how close they are
    private func rewardRow(_ offer: ClipOffer, balance: Int) -> UIView {
        let title = ClipTheme.label(.systemFont(ofSize: 16, weight: .semibold), lines: 1)
        title.text = offer.title
        let cost = ClipTheme.label(.systemFont(ofSize: 15, weight: .medium), color: UIColor.white.withAlphaComponent(0.8), lines: 1)
        let ready = balance >= offer.pointsCost
        cost.text = ready ? "Ready ✓" : "\(offer.pointsCost) pts"
        cost.textColor = ready ? ClipTheme.gold : UIColor.white.withAlphaComponent(0.8)
        cost.setContentHuggingPriority(.required, for: .horizontal)
        let line = UIStackView(arrangedSubviews: [title, cost])
        line.spacing = 8

        let bar = UIProgressView(progressViewStyle: .bar)
        bar.progressTintColor = ClipTheme.gold
        bar.trackTintColor = UIColor.white.withAlphaComponent(0.18)
        bar.progress = Float(min(1, Double(balance) / Double(max(offer.pointsCost, 1))))
        bar.layer.cornerRadius = 2
        bar.clipsToBounds = true
        bar.heightAnchor.constraint(equalToConstant: 4).isActive = true

        let row = UIStackView(arrangedSubviews: [line, bar])
        row.axis = .vertical
        row.spacing = 6
        return row
    }

    private func showGenericWelcome() {
        hookLabel.attributedText = ClipTheme.hookText(isNewSignIn ? "You're in." : "Welcome back.", "+\(preview.favCoinBonus) FavCoins.", size: 46)
        nameLabel.isHidden = true
        detailLabel.text = "Get the FavCircles app to claim them, then add your first place for 25 more."
        reveal(celebrate: isNewSignIn)
    }

    private func showPending() {
        hookLabel.attributedText = ClipTheme.hookText("You're in.", "Almost done.", size: 46)
        nameLabel.text = preview.venueName
        detailLabel.text = preview.signupBonusPoints > 0
            ? "Your \(preview.signupBonusPoints) points at \(preview.venueName) are on the way. Open the FavCircles app to collect them."
            : "Open the FavCircles app to keep \(preview.venueName) on your map."
        reveal(celebrate: false)
    }

    private func reveal(celebrate: Bool) {
        spinner.stopAnimating()
        stack.isHidden = false
        ClipTheme.animateIn([brandMark, hookLabel, nameLabel, detailLabel, panel, getAppButton, signOutButton])
        if celebrate {
            UINotificationFeedbackGenerator().notificationOccurred(.success)
            rainConfetti()
        }
        presentInstallOverlay(afterDelay: celebrate ? 2.2 : 1.4)
    }

    // MARK: - Actions

    @objc private func getAppTapped() {
        overlayPresented = false
        presentInstallOverlay(afterDelay: 0)
    }

    @objc private func signOutTapped() {
        ClipSession.clear()
        navigationController?.setViewControllers([ClipOfferViewController(invocation: invocation)], animated: true)
    }

    // MARK: - Celebration

    private func rainConfetti() {
        let emitter = CAEmitterLayer()
        emitter.emitterPosition = CGPoint(x: view.bounds.midX, y: -20)
        emitter.emitterShape = .line
        emitter.emitterSize = CGSize(width: view.bounds.width, height: 1)

        let colors: [UIColor] = [ClipTheme.gold, .white, ClipTheme.pinRed, ClipTheme.pinGreen, ClipTheme.pinGold]
        emitter.emitterCells = colors.map { color in
            let cell = CAEmitterCell()
            cell.contents = Self.confettiImage(color: color).cgImage
            cell.birthRate = 7
            cell.lifetime = 6
            cell.velocity = 190
            cell.velocityRange = 80
            cell.emissionLongitude = .pi
            cell.emissionRange = .pi / 5
            cell.spin = 3.2
            cell.spinRange = 4
            cell.scale = 0.7
            cell.scaleRange = 0.35
            cell.yAcceleration = 90
            return cell
        }
        view.layer.addSublayer(emitter)

        // Burst, then let the last pieces fall and clean up
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.8) { emitter.birthRate = 0 }
        DispatchQueue.main.asyncAfter(deadline: .now() + 8) { emitter.removeFromSuperlayer() }
    }

    private static func confettiImage(color: UIColor) -> UIImage {
        let size = CGSize(width: 10, height: 14)
        return UIGraphicsImageRenderer(size: size).image { context in
            color.setFill()
            context.cgContext.fill(CGRect(origin: .zero, size: size))
        }
    }

    private func presentInstallOverlay(afterDelay delay: TimeInterval) {
        DispatchQueue.main.asyncAfter(deadline: .now() + delay) { [weak self] in
            guard let self = self, !self.overlayPresented,
                  let scene = self.view.window?.windowScene else { return }
            self.overlayPresented = true
            let config = SKOverlay.AppClipConfiguration(position: .bottom)
            SKOverlay(configuration: config).present(in: scene)
        }
    }
}

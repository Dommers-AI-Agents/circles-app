import UIKit

/// What the circle organizer shows during its ~30 s run (Wes, 2026-11-04:
/// use the empty space and the wait): what it's doing, in plain steps, and
/// "Did you know?" tips that turn every few seconds (tap for the next).
/// Tips come from the server's list (`ClientConfig.tips`); none → no card.
final class OrganizeProgressView: UIView {
    private static let tipSeconds: TimeInterval = 6

    private let tips: [ClientConfig.Tip]
    private var tipIndex = 0
    private var timer: Timer?

    private let tipEmoji: UILabel = {
        let label = UILabel()
        label.font = .systemFont(ofSize: 34)
        label.textAlignment = .center
        return label
    }()
    private let tipText: UILabel = {
        let label = UILabel()
        label.font = .preferredFont(forTextStyle: .body)
        label.textColor = Constants.Colors.label
        label.textAlignment = .center
        label.numberOfLines = 0
        return label
    }()
    private let pageDots: UIPageControl = {
        let dots = UIPageControl()
        dots.isUserInteractionEnabled = false
        dots.hidesForSinglePage = true
        dots.currentPageIndicatorTintColor = Constants.Colors.primary
        dots.pageIndicatorTintColor = .tertiaryLabel
        return dots
    }()

    init(circleCount: Int, tips: [ClientConfig.Tip]) {
        self.tips = tips.shuffled()
        super.init(frame: .zero)
        build(circleCount: circleCount)
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    deinit { timer?.invalidate() }

    /// Tips turn only while the view is on screen
    override func didMoveToWindow() {
        super.didMoveToWindow()
        timer?.invalidate()
        timer = nil
        guard window != nil, tips.count > 1 else { return }
        timer = Timer.scheduledTimer(withTimeInterval: Self.tipSeconds, repeats: true) { [weak self] _ in
            self?.showTip(at: (self?.tipIndex ?? 0) + 1)
        }
    }

    private func build(circleCount: Int) {
        let spinner = UIActivityIndicatorView(style: .large)
        spinner.startAnimating()

        let title = UILabel()
        title.text = "Organizing your circles…"
        title.font = .systemFont(ofSize: UIFont.preferredFont(forTextStyle: .title3).pointSize, weight: .semibold)
        title.textColor = Constants.Colors.label
        title.textAlignment = .center

        let time = UILabel()
        time.text = "This usually takes about 30 seconds."
        time.font = .preferredFont(forTextStyle: .subheadline)
        time.textColor = .secondaryLabel
        time.textAlignment = .center

        let circlesText = circleCount == 1 ? "your circle" : "each of your \(circleCount) circles"
        let steps = card(rows: [
            row("doc.text.magnifyingglass", "Reading the places saved in \(circlesText)"),
            row("square.grid.2x2", "Working out how each one is organized: by neighborhood, by kind of place, by person, or as a trip"),
            row("arrow.triangle.merge", "Spotting circles that overlap enough to combine"),
            row("hand.raised", "Nothing changes until you approve it, one suggestion at a time")
        ], header: "What's happening")

        var arranged: [UIView] = [spinner, title, time, steps]
        if !tips.isEmpty {
            pageDots.numberOfPages = tips.count
            // Room for three lines, so a short tip doesn't make the cards jump
            tipText.heightAnchor.constraint(greaterThanOrEqualToConstant: ceil(tipText.font.lineHeight * 3)).isActive = true
            let tipStack = UIStackView(arrangedSubviews: [tipEmoji, tipText, pageDots])
            tipStack.axis = .vertical
            tipStack.spacing = 8
            let tipCard = card(rows: [tipStack], header: "Did you know?")
            tipCard.addGestureRecognizer(UITapGestureRecognizer(target: self, action: #selector(nextTip)))
            tipCard.accessibilityHint = "Shows the next tip"
            arranged.append(tipCard)
            showTip(at: 0, animated: false)
        }

        let stack = UIStackView(arrangedSubviews: arranged)
        stack.axis = .vertical
        stack.spacing = 12
        stack.setCustomSpacing(4, after: title)
        stack.setCustomSpacing(24, after: time)
        stack.setCustomSpacing(16, after: steps)
        stack.translatesAutoresizingMaskIntoConstraints = false

        let scroll = UIScrollView()
        scroll.alwaysBounceVertical = false
        scroll.translatesAutoresizingMaskIntoConstraints = false
        scroll.addSubview(stack)
        addSubview(scroll)
        NSLayoutConstraint.activate([
            scroll.topAnchor.constraint(equalTo: safeAreaLayoutGuide.topAnchor),
            scroll.bottomAnchor.constraint(equalTo: bottomAnchor),
            scroll.leadingAnchor.constraint(equalTo: leadingAnchor),
            scroll.trailingAnchor.constraint(equalTo: trailingAnchor),
            stack.topAnchor.constraint(greaterThanOrEqualTo: scroll.contentLayoutGuide.topAnchor, constant: 24),
            stack.bottomAnchor.constraint(lessThanOrEqualTo: scroll.contentLayoutGuide.bottomAnchor, constant: -24),
            stack.leadingAnchor.constraint(equalTo: scroll.frameLayoutGuide.leadingAnchor, constant: 20),
            stack.trailingAnchor.constraint(equalTo: scroll.frameLayoutGuide.trailingAnchor, constant: -20),
            // Centered when it fits, scrolls when it doesn't (large text)
            scroll.contentLayoutGuide.heightAnchor.constraint(greaterThanOrEqualTo: scroll.frameLayoutGuide.heightAnchor),
            stack.centerYAnchor.constraint(equalTo: scroll.contentLayoutGuide.centerYAnchor).withPriority(.defaultHigh)
        ])
    }

    private func row(_ symbol: String, _ text: String) -> UIView {
        let icon = UIImageView(image: UIImage(systemName: symbol))
        icon.tintColor = Constants.Colors.primary
        icon.contentMode = .scaleAspectFit
        icon.translatesAutoresizingMaskIntoConstraints = false
        icon.widthAnchor.constraint(equalToConstant: 24).isActive = true
        icon.heightAnchor.constraint(equalToConstant: 22).isActive = true
        let label = UILabel()
        label.text = text
        label.font = .preferredFont(forTextStyle: .subheadline)
        label.textColor = Constants.Colors.label
        label.numberOfLines = 0
        let line = UIStackView(arrangedSubviews: [icon, label])
        line.spacing = 12
        line.alignment = .top
        return line
    }

    private func card(rows: [UIView], header: String) -> UIView {
        let headerLabel = UILabel()
        headerLabel.text = header.uppercased()
        headerLabel.font = .systemFont(ofSize: UIFont.preferredFont(forTextStyle: .caption1).pointSize, weight: .semibold)
        headerLabel.textColor = .secondaryLabel
        let stack = UIStackView(arrangedSubviews: [headerLabel] + rows)
        stack.axis = .vertical
        stack.spacing = 14
        stack.translatesAutoresizingMaskIntoConstraints = false
        let card = UIView()
        card.backgroundColor = .secondarySystemGroupedBackground
        card.layer.cornerRadius = 14
        card.addSubview(stack)
        NSLayoutConstraint.activate([
            stack.topAnchor.constraint(equalTo: card.topAnchor, constant: 16),
            stack.bottomAnchor.constraint(equalTo: card.bottomAnchor, constant: -14),
            stack.leadingAnchor.constraint(equalTo: card.leadingAnchor, constant: 16),
            stack.trailingAnchor.constraint(equalTo: card.trailingAnchor, constant: -16)
        ])
        return card
    }

    @objc private func nextTip() {
        showTip(at: tipIndex + 1)
        // A tap restarts the clock so the new tip gets its full time
        didMoveToWindow()
    }

    private func showTip(at index: Int, animated: Bool = true) {
        guard !tips.isEmpty else { return }
        tipIndex = index % tips.count
        let tip = tips[tipIndex]
        let apply = {
            self.tipEmoji.text = tip.emoji
            self.tipText.text = tip.text
            self.pageDots.currentPage = self.tipIndex
        }
        guard animated else { apply(); return }
        UIView.transition(with: tipText.superview ?? self, duration: 0.35, options: .transitionCrossDissolve, animations: apply)
    }
}

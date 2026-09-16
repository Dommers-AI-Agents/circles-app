import UIKit

/// Three-slide "what are FavCoins?" explainer, opened from the home daily
/// card's piggy-bank prompt. "Got it" hands off to the Piggy Bank; Skip just
/// closes. Either way the caller records the `favcoins_intro` ack so the
/// card never asks again.
final class FavCoinsIntroViewController: BaseViewController {

    override var loadsDataOnViewDidLoad: Bool { false }

    /// `true` when the user finished the slides (open the piggy bank).
    var onFinished: ((Bool) -> Void)?
    private var reported = false

    private struct Slide {
        let emoji: String
        let title: String
        let body: String
    }

    private let slides: [Slide] = [
        Slide(emoji: "🐷",
              title: "You earn FavCoins by using FavCircles",
              body: "Adding places, creating circles, sharing moments, connecting with friends — each one drops coins into your piggy bank. There's a weekly bonus, too."),
        Slide(emoji: "🌵",
              title: "They're real crypto",
              body: "FavCoins are a real cryptocurrency on the 🌵 Cactus blockchain. Coins clear after a short holding window, then they're confirmed and yours."),
        Slide(emoji: "👛",
              title: "Claim them to your own wallet",
              body: "Create or link a 🌵 wallet only you control and send your confirmed coins on-chain. After that, FavCircles can't move or take them.")
    ]

    private let pager: UIScrollView = {
        let view = UIScrollView()
        view.isPagingEnabled = true
        view.showsHorizontalScrollIndicator = false
        view.translatesAutoresizingMaskIntoConstraints = false
        return view
    }()

    private let pageControl: UIPageControl = {
        let control = UIPageControl()
        control.currentPageIndicatorTintColor = Constants.Colors.primary
        control.pageIndicatorTintColor = Constants.Colors.lightGray
        control.translatesAutoresizingMaskIntoConstraints = false
        return control
    }()

    private lazy var nextButton = UIButton.primaryButton(title: "Next")
    private lazy var skipButton = UIButton.secondaryButton(title: "Skip")

    override func viewDidLoad() {
        super.viewDidLoad()
        view.backgroundColor = Constants.Colors.background
        if let sheet = sheetPresentationController {
            sheet.detents = [.medium(), .large()]
            sheet.prefersGrabberVisible = true
        }
        buildUI()
        AnalyticsService.shared.logEvent("favcoins_intro_shown")
    }

    override func viewDidDisappear(_ animated: Bool) {
        super.viewDidDisappear(animated)
        // Swiped down = skipped.
        finish(openPiggyBank: false)
    }

    private func buildUI() {
        pager.delegate = self
        pageControl.numberOfPages = slides.count
        nextButton.addTarget(self, action: #selector(nextTapped), for: .touchUpInside)
        skipButton.addTarget(self, action: #selector(skipTapped), for: .touchUpInside)
        [pager, pageControl, nextButton, skipButton].forEach(view.addSubview)

        NSLayoutConstraint.activate([
            pager.topAnchor.constraint(equalTo: view.safeAreaLayoutGuide.topAnchor, constant: Constants.Spacing.large),
            pager.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            pager.trailingAnchor.constraint(equalTo: view.trailingAnchor),

            pageControl.topAnchor.constraint(equalTo: pager.bottomAnchor, constant: Constants.Spacing.small),
            pageControl.centerXAnchor.constraint(equalTo: view.centerXAnchor),

            nextButton.topAnchor.constraint(equalTo: pageControl.bottomAnchor, constant: Constants.Spacing.medium),
            nextButton.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: Constants.Spacing.large),
            nextButton.trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: -Constants.Spacing.large),

            skipButton.topAnchor.constraint(equalTo: nextButton.bottomAnchor, constant: Constants.Spacing.xsmall),
            skipButton.leadingAnchor.constraint(equalTo: nextButton.leadingAnchor),
            skipButton.trailingAnchor.constraint(equalTo: nextButton.trailingAnchor),
            skipButton.bottomAnchor.constraint(lessThanOrEqualTo: view.safeAreaLayoutGuide.bottomAnchor, constant: -Constants.Spacing.medium)
        ])

        // Pages are laid out with the frame layout guide so each is exactly
        // one screen wide without knowing the width up front.
        var previous: UIView?
        for slide in slides {
            let page = makePage(slide)
            pager.addSubview(page)
            NSLayoutConstraint.activate([
                page.topAnchor.constraint(equalTo: pager.contentLayoutGuide.topAnchor),
                page.bottomAnchor.constraint(equalTo: pager.contentLayoutGuide.bottomAnchor),
                page.widthAnchor.constraint(equalTo: pager.frameLayoutGuide.widthAnchor),
                page.heightAnchor.constraint(equalTo: pager.frameLayoutGuide.heightAnchor),
                page.leadingAnchor.constraint(equalTo: previous?.trailingAnchor ?? pager.contentLayoutGuide.leadingAnchor)
            ])
            previous = page
        }
        previous?.trailingAnchor.constraint(equalTo: pager.contentLayoutGuide.trailingAnchor).isActive = true
    }

    private func makePage(_ slide: Slide) -> UIView {
        let page = UIView()
        page.translatesAutoresizingMaskIntoConstraints = false

        let emoji = UILabel()
        emoji.text = slide.emoji
        emoji.font = .systemFont(ofSize: 64)
        emoji.textAlignment = .center

        let title = UILabel()
        title.text = slide.title
        title.font = .systemFont(ofSize: 22, weight: .bold)
        title.textColor = Constants.Colors.label
        title.textAlignment = .center
        title.numberOfLines = 0

        let body = UILabel()
        body.text = slide.body
        body.font = .systemFont(ofSize: 16)
        body.textColor = Constants.Colors.secondaryLabel
        body.textAlignment = .center
        body.numberOfLines = 0

        let stack = UIStackView(arrangedSubviews: [emoji, title, body])
        stack.axis = .vertical
        stack.spacing = Constants.Spacing.small
        stack.translatesAutoresizingMaskIntoConstraints = false
        page.addSubview(stack)
        NSLayoutConstraint.activate([
            stack.leadingAnchor.constraint(equalTo: page.leadingAnchor, constant: Constants.Spacing.large),
            stack.trailingAnchor.constraint(equalTo: page.trailingAnchor, constant: -Constants.Spacing.large),
            stack.topAnchor.constraint(equalTo: page.topAnchor),
            stack.bottomAnchor.constraint(lessThanOrEqualTo: page.bottomAnchor)
        ])
        return page
    }

    private var currentPage: Int {
        guard pager.bounds.width > 0 else { return 0 }
        return Int((pager.contentOffset.x / pager.bounds.width).rounded())
    }

    private func updateChrome() {
        pageControl.currentPage = currentPage
        let last = currentPage == slides.count - 1
        nextButton.setTitle(last ? "Got it — open my piggy bank" : "Next", for: .normal)
    }

    @objc private func nextTapped() {
        if currentPage == slides.count - 1 {
            finish(openPiggyBank: true)
            return
        }
        let x = CGFloat(currentPage + 1) * pager.bounds.width
        pager.setContentOffset(CGPoint(x: x, y: 0), animated: true)
    }

    @objc private func skipTapped() {
        finish(openPiggyBank: false)
        dismiss(animated: true)
    }

    private func finish(openPiggyBank: Bool) {
        guard !reported else { return }
        reported = true
        AnalyticsService.shared.logEvent(openPiggyBank ? "favcoins_intro_completed" : "favcoins_intro_skipped")
        onFinished?(openPiggyBank)
    }
}

extension FavCoinsIntroViewController: UIScrollViewDelegate {
    func scrollViewDidScroll(_ scrollView: UIScrollView) { updateChrome() }
}

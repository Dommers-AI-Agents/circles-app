import UIKit

/// The owner's Insights (Wes, 2026-11-09; FavCircles Business): who's new and
/// who came back, the repeat rate, regulars and customers who haven't been
/// back, busiest hours and days, which rewards get redeemed, the FavCircles
/// score beside the Google rating, and reviews waiting for a reply. The
/// numbers come from services/venueInsights.js, cached an hour per store.
final class VenueInsightsViewController: BaseViewController {

    private let venueId: String
    private let venueName: String
    /// The store's place, for opening its reviews
    private let placeId: String?
    private var range: VenueInsightsCopy.Range = .days30
    private var data: VenueInsightsData?

    override var enablesPullToRefresh: Bool { true }

    private let scrollView: UIScrollView = {
        let scroll = UIScrollView()
        scroll.translatesAutoresizingMaskIntoConstraints = false
        scroll.alwaysBounceVertical = true
        return scroll
    }()

    private let contentStack: UIStackView = {
        let stack = UIStackView()
        stack.axis = .vertical
        stack.spacing = Constants.Spacing.medium
        stack.translatesAutoresizingMaskIntoConstraints = false
        return stack
    }()

    private lazy var rangeControl: UISegmentedControl = {
        let control = UISegmentedControl(items: VenueInsightsCopy.Range.allCases.map(\.title))
        control.selectedSegmentIndex = 0
        control.addTarget(self, action: #selector(rangeChanged), for: .valueChanged)
        return control
    }()

    init(venueId: String, venueName: String, placeId: String?) {
        self.venueId = venueId
        self.venueName = venueName
        self.placeId = placeId
        super.init(nibName: nil, bundle: nil)
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    override func viewDidLoad() {
        super.viewDidLoad()
        title = "Insights"
        view.backgroundColor = .systemBackground
        view.addSubview(scrollView)
        scrollView.addSubview(contentStack)
        contentStack.addArrangedSubview(rangeControl)
        NSLayoutConstraint.activate([
            scrollView.topAnchor.constraint(equalTo: view.safeAreaLayoutGuide.topAnchor),
            scrollView.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            scrollView.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            scrollView.bottomAnchor.constraint(equalTo: view.bottomAnchor),
            contentStack.topAnchor.constraint(equalTo: scrollView.topAnchor, constant: Constants.Spacing.medium),
            contentStack.leadingAnchor.constraint(equalTo: scrollView.leadingAnchor, constant: Constants.Spacing.medium),
            contentStack.trailingAnchor.constraint(equalTo: scrollView.trailingAnchor, constant: -Constants.Spacing.medium),
            contentStack.bottomAnchor.constraint(equalTo: scrollView.bottomAnchor, constant: -Constants.Spacing.large),
            contentStack.widthAnchor.constraint(equalTo: scrollView.widthAnchor, constant: -2 * Constants.Spacing.medium)
        ])
    }

    override func setupRefreshControl() {
        scrollView.refreshControl = refreshControl
    }

    override func loadData(completion: (() -> Void)? = nil) {
        let requested = range
        RewardsService.shared.getVenueInsights(venueId: venueId, range: requested.rawValue) { [weak self] result in
            DispatchQueue.main.async {
                completion?()
                guard let self, self.range == requested else { return }
                switch result {
                case .success(let data):
                    self.data = data
                    self.render(data)
                case .failure(let error):
                    self.showError(error)
                }
            }
        }
    }

    @objc private func rangeChanged() {
        range = VenueInsightsCopy.Range.allCases[rangeControl.selectedSegmentIndex]
        loadData()
    }

    // MARK: - Rendering

    private func render(_ data: VenueInsightsData) {
        contentStack.arrangedSubviews.filter { $0 !== rangeControl }.forEach { $0.removeFromSuperview() }

        if data.stale == true {
            contentStack.addArrangedSubview(caption(VenueInsightsCopy.staleNote))
        }

        contentStack.addArrangedSubview(scoreCard(data.score))

        contentStack.addArrangedSubview(header("Customers"))
        contentStack.addArrangedSubview(caption(VenueInsightsCopy.visitsLine(visits: data.customers.visits, visitors: data.customers.visitors, range: range)))
        contentStack.addArrangedSubview(StatTileView.grid(VenueInsightsCopy.customerTiles(data.customers, range: range)))
        contentStack.addArrangedSubview(caption(VenueInsightsCopy.repeatLine(pct: data.customers.repeatRatePct, total: data.customers.total)))

        if data.customers.visits > 0 {
            contentStack.addArrangedSubview(HistogramCardView.make(title: "Busiest hours", values: data.busiest.hours, labels: HistogramCardView.hourLabels))
            contentStack.addArrangedSubview(HistogramCardView.make(title: "Busiest days", values: data.busiest.days, labels: HistogramCardView.dayLabels))
        }

        contentStack.addArrangedSubview(header("Rewards redeemed"))
        if data.offers.isEmpty {
            contentStack.addArrangedSubview(caption(VenueInsightsCopy.offersEmpty(range: range)))
        } else {
            contentStack.addArrangedSubview(card(data.offers.map { body(VenueInsightsCopy.offerLine($0)) }))
        }

        contentStack.addArrangedSubview(header("Reviews on FavCircles"))
        contentStack.addArrangedSubview(caption(VenueInsightsCopy.commentsLine(inPeriod: data.comments.inPeriod, total: data.comments.total, range: range)))
        if data.comments.total > 0 {
            let awaitingLabel = body(VenueInsightsCopy.awaitingLine(count: data.comments.awaitingReply))
            awaitingLabel.textColor = data.comments.awaitingReply > 0 ? Constants.Colors.primary : Constants.Colors.label
            var rows: [UIView] = [awaitingLabel]
            rows += data.comments.awaiting.compactMap { awaiting in
                guard let text = awaiting.text, !text.isEmpty else { return nil }
                let quote = body("“\(text)”")
                quote.textColor = .secondaryLabel
                return quote
            }
            contentStack.addArrangedSubview(card(rows))
            if placeId != nil {
                let reviews = UIButton.secondaryButton(title: data.comments.awaitingReply > 0 ? "Reply to reviews" : "See all reviews")
                reviews.addTarget(self, action: #selector(openReviews), for: .touchUpInside)
                contentStack.addArrangedSubview(reviews)
            }
        }
    }

    private func scoreCard(_ score: VenueInsightsData.Score) -> UIView {
        let title = header("Your FavCircles score")
        let big = UILabel()
        big.text = VenueInsightsCopy.scoreLine(average: score.average)
        big.font = UIFont.systemFont(ofSize: 34, weight: .bold)
        big.textColor = Constants.Colors.label
        var rows: [UIView] = [title, big, caption(VenueInsightsCopy.scoreCaption(ratings: score.ratings, recommend: score.recommend, recommendPct: score.recommendPct))]
        if let trend = VenueInsightsCopy.trendLine(score.trend) {
            let label = caption(trend)
            label.textColor = (score.trend ?? 0) < -0.05 ? Constants.Colors.danger : Constants.Colors.success
            rows.append(label)
        }
        if let google = VenueInsightsCopy.googleLine(rating: score.google?.rating, total: score.google?.total ?? 0) {
            rows.append(caption(google))
        }
        return card(rows)
    }

    // MARK: - Pieces

    private func header(_ text: String) -> UILabel {
        let label = UILabel()
        label.text = text
        label.font = UIFont.systemFont(ofSize: 16, weight: .semibold)
        label.textColor = Constants.Colors.label
        label.numberOfLines = 0
        return label
    }

    private func body(_ text: String) -> UILabel {
        let label = UILabel()
        label.text = text
        label.font = UIFont.systemFont(ofSize: 15)
        label.textColor = Constants.Colors.label
        label.numberOfLines = 0
        return label
    }

    private func caption(_ text: String) -> UILabel {
        let label = UILabel()
        label.text = text
        label.font = UIFont.systemFont(ofSize: 13)
        label.textColor = .secondaryLabel
        label.numberOfLines = 0
        return label
    }

    private func card(_ rows: [UIView]) -> UIView {
        let card = UIView()
        card.backgroundColor = Constants.Colors.secondaryBackground
        card.layer.cornerRadius = 12
        let stack = UIStackView(arrangedSubviews: rows)
        stack.axis = .vertical
        stack.spacing = 6
        stack.translatesAutoresizingMaskIntoConstraints = false
        card.addSubview(stack)
        NSLayoutConstraint.activate([
            stack.topAnchor.constraint(equalTo: card.topAnchor, constant: 12),
            stack.leadingAnchor.constraint(equalTo: card.leadingAnchor, constant: 12),
            stack.trailingAnchor.constraint(equalTo: card.trailingAnchor, constant: -12),
            stack.bottomAnchor.constraint(equalTo: card.bottomAnchor, constant: -12)
        ])
        return card
    }

    // MARK: - Actions

    /// The store's reviews, where the team answers them (replies carry the store's badge)
    @objc private func openReviews() {
        guard let placeId else { return }
        PlaceService.shared.fetchPlaceById(id: placeId) { [weak self] result in
            DispatchQueue.main.async {
                guard let self else { return }
                switch result {
                case .success(let place):
                    let comments = PlaceCommentsViewController(place: place)
                    self.present(UINavigationController(rootViewController: comments), animated: true)
                case .failure(let error):
                    self.showError(error)
                }
            }
        }
    }
}

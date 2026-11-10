import UIKit

/// A customer's spot in a store's line (2026-11-09): join with a party size,
/// then see the place in line and the quoted wait, refreshed every 15 s and
/// when the host's push lands. Leave any time. Presented as a sheet from the
/// place page's store card.
final class WaitlistStatusViewController: BaseViewController {

    private let venue: PlaceVenue
    private let waitlist: StoreWaitlist
    private var entry: WaitlistEntry?
    private var poller: Timer?
    private var observer: NSObjectProtocol?
    /// The place page refreshes its row from this
    var onChanged: ((WaitlistEntry?) -> Void)?

    override var loadsDataOnViewDidLoad: Bool { true }

    private let titleLabel = UILabel()
    private let bodyLabel = UILabel()
    private let partyLabel = UILabel()
    private lazy var partyStepper: UIStepper = {
        let stepper = UIStepper()
        stepper.minimumValue = 1
        stepper.maximumValue = 12
        stepper.value = 2
        stepper.addTarget(self, action: #selector(partyChanged), for: .valueChanged)
        return stepper
    }()
    private lazy var joinButton = UIButton.primaryButton(title: WaitlistCopy.joinButton)
    private lazy var leaveButton = UIButton.secondaryButton(title: WaitlistCopy.leaveButton)
    private let statusLabel = UILabel()
    private let footerLabel = UILabel()

    init(venue: PlaceVenue, waitlist: StoreWaitlist, entry: WaitlistEntry?) {
        self.venue = venue
        self.waitlist = waitlist
        self.entry = entry
        super.init(nibName: nil, bundle: nil)
    }
    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    deinit {
        poller?.invalidate()
        if let observer { NotificationCenter.default.removeObserver(observer) }
    }

    override func viewDidLoad() {
        super.viewDidLoad()
        view.backgroundColor = .systemBackground

        titleLabel.font = .systemFont(ofSize: 22, weight: .bold)
        titleLabel.textColor = Constants.Colors.label
        titleLabel.numberOfLines = 0
        bodyLabel.font = .systemFont(ofSize: 15)
        bodyLabel.textColor = .secondaryLabel
        bodyLabel.numberOfLines = 0
        partyLabel.font = .systemFont(ofSize: 17, weight: .semibold)
        partyLabel.textColor = Constants.Colors.label
        statusLabel.font = .systemFont(ofSize: 20, weight: .semibold)
        statusLabel.textColor = Constants.Colors.label
        statusLabel.numberOfLines = 0
        footerLabel.font = .systemFont(ofSize: 13)
        footerLabel.textColor = .secondaryLabel
        footerLabel.numberOfLines = 0

        let partyRow = UIStackView(arrangedSubviews: [partyLabel, partyStepper])
        partyRow.axis = .horizontal
        partyRow.distribution = .equalSpacing

        let stack = UIStackView(arrangedSubviews: [titleLabel, bodyLabel, partyRow, joinButton, statusLabel, footerLabel, leaveButton])
        stack.axis = .vertical
        stack.spacing = 14
        stack.setCustomSpacing(6, after: titleLabel)
        stack.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(stack)
        NSLayoutConstraint.activate([
            stack.topAnchor.constraint(equalTo: view.safeAreaLayoutGuide.topAnchor, constant: 28),
            stack.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: 24),
            stack.trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: -24)
        ])
        joinButton.addTarget(self, action: #selector(joinTapped), for: .touchUpInside)
        leaveButton.addTarget(self, action: #selector(leaveTapped), for: .touchUpInside)
        observer = NotificationCenter.default.addObserver(forName: .waitlistChanged, object: nil, queue: .main) { [weak self] _ in self?.loadData() }
        render()
    }

    override func viewWillDisappear(_ animated: Bool) {
        super.viewWillDisappear(animated)
        poller?.invalidate()
        poller = nil
    }

    override func loadData(completion: (() -> Void)? = nil) {
        WaitlistService.shared.mine(venueId: venue.venueId) { [weak self] result in
            DispatchQueue.main.async {
                completion?()
                guard let self else { return }
                if case .success(let entry) = result {
                    self.entry = entry
                    self.onChanged?(entry)
                    self.render()
                }
                self.schedulePolling()
            }
        }
    }

    private func schedulePolling() {
        poller?.invalidate()
        guard entry?.isOpen == true else { return }
        poller = Timer.scheduledTimer(withTimeInterval: 15, repeats: false) { [weak self] _ in
            if self?.view.window != nil { self?.loadData() }
        }
    }

    private func render() {
        let inLine = entry?.isOpen == true
        titleLabel.text = inLine ? venue.venueName : WaitlistCopy.joinTitle(storeName: venue.venueName)
        bodyLabel.text = WaitlistCopy.joinExplanation(quoteMinutes: waitlist.quoteMinutes)
        bodyLabel.isHidden = inLine
        partyLabel.text = WaitlistCopy.partyLine(Int(partyStepper.value))
        partyLabel.superview?.isHidden = inLine
        joinButton.isHidden = inLine
        statusLabel.isHidden = !inLine
        footerLabel.isHidden = !inLine
        leaveButton.isHidden = !inLine
        if let entry, inLine {
            statusLabel.text = WaitlistCopy.statusLine(entry)
            footerLabel.text = entry.isCalled ? WaitlistCopy.calledFooter : WaitlistCopy.partyLine(entry.partySize) + " · we'll notify this phone when your table is ready."
        }
    }

    @objc private func partyChanged() {
        partyLabel.text = WaitlistCopy.partyLine(Int(partyStepper.value))
    }

    @objc private func joinTapped() {
        joinButton.isEnabled = false
        WaitlistService.shared.join(venueId: venue.venueId, partySize: Int(partyStepper.value)) { [weak self] result in
            DispatchQueue.main.async {
                guard let self else { return }
                self.joinButton.isEnabled = true
                switch result {
                case .success(let entry):
                    self.entry = entry
                    self.onChanged?(entry)
                    self.render()
                    self.schedulePolling()
                case .failure(let error):
                    self.showError(error.serverMessage ?? "Couldn\u{2019}t join the line.")
                }
            }
        }
    }

    @objc private func leaveTapped() {
        guard let entry else { return }
        showConfirmation(title: "Leave the line?", message: "You'd join again at the back if you change your mind.") { [weak self] in
            WaitlistService.shared.leave(entryId: entry.entryId) { result in
                DispatchQueue.main.async {
                    guard let self else { return }
                    switch result {
                    case .success:
                        self.entry = nil
                        self.onChanged?(nil)
                        self.dismiss(animated: true)
                    case .failure(let error):
                        self.showError(error.serverMessage ?? "Couldn\u{2019}t leave the line.")
                    }
                }
            }
        }
    }
}

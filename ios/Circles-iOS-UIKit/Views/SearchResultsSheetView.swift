import UIKit

/// The home search results, Apple-Maps style: a sheet over the bottom of the
/// map that rides above the keyboard, with a handle line ("26 places · 3
/// nearby") that stays when the sheet is collapsed. The host owns the table's
/// delegate/dataSource; this view owns geometry, drag, and the rule that
/// nothing moves under a finger.
final class SearchResultsSheetView: UIView {
    let tableView: UITableView = {
        let table = UITableView(frame: .zero, style: .plain)
        table.backgroundColor = .clear
        table.rowHeight = SearchSheetLayout.rowHeight
        table.estimatedRowHeight = SearchSheetLayout.rowHeight
        table.alwaysBounceVertical = true
        table.delaysContentTouches = false
        table.canCancelContentTouches = true
        table.sectionHeaderTopPadding = 0
        table.register(UITableViewCell.self, forCellReuseIdentifier: "SearchResultCell")
        table.translatesAutoresizingMaskIntoConstraints = false
        return table
    }()

    private(set) var state: SearchSheetState = .expanded
    var isVisible: Bool { !isHidden && alpha > 0 }
    var onStateChange: ((SearchSheetState) -> Void)?
    var onHandleTap: (() -> Void)?

    private let container = UIView()
    private let handle = UIView()
    private let grabber = UIView()
    private let titleLabel = UILabel()
    private let chevron = UIImageView()
    private var heightConstraint: NSLayoutConstraint!
    private var bottomCap: NSLayoutConstraint!

    private var availableHeight: CGFloat = 0
    private var contentHeight: CGFloat = SearchSheetLayout.handleHeight
    private var isRowHighlighted = false
    private var pendingUpdate: (() -> Void)?
    private var dragStartHeight: CGFloat = 0

    override init(frame: CGRect) {
        super.init(frame: frame)
        build()
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) is not supported") }

    // MARK: - Public

    /// Pins the sheet to the container's sides and to `bottomAnchor` (the
    /// keyboard layout guide's top, so it rides above the keyboard). With no
    /// keyboard — or a hardware one — that guide sits at the very bottom of
    /// the view, under the tab bar; `setBottomInset` keeps the sheet above it.
    func install(in containerView: UIView, bottomAnchor: NSLayoutYAxisAnchor) {
        translatesAutoresizingMaskIntoConstraints = false
        heightConstraint = heightAnchor.constraint(equalToConstant: SearchSheetLayout.handleHeight)
        let ridesKeyboard = self.bottomAnchor.constraint(equalTo: bottomAnchor)
        ridesKeyboard.priority = .defaultHigh
        bottomCap = self.bottomAnchor.constraint(lessThanOrEqualTo: containerView.bottomAnchor)
        NSLayoutConstraint.activate([
            leadingAnchor.constraint(equalTo: containerView.leadingAnchor),
            trailingAnchor.constraint(equalTo: containerView.trailingAnchor),
            ridesKeyboard,
            bottomCap,
            heightConstraint
        ])
        isHidden = true
        alpha = 0
    }

    /// How far above the container's bottom the sheet must stop (the tab
    /// bar, which the home view's safe area does not cover).
    func setBottomInset(_ inset: CGFloat) {
        guard bottomCap != nil, bottomCap.constant != -inset else { return }
        bottomCap.constant = -inset
    }

    func present(state: SearchSheetState, availableHeight: CGFloat) {
        self.availableHeight = availableHeight
        self.state = state
        updateChevron()
        let wasHidden = isHidden
        isHidden = false
        heightConstraint.constant = targetHeight
        UIView.animate(withDuration: wasHidden ? 0.25 : 0.2) {
            self.alpha = 1
            self.superview?.layoutIfNeeded()
        }
    }

    func hide() {
        pendingUpdate = nil
        guard !isHidden else { return }
        UIView.animate(withDuration: 0.2, animations: { self.alpha = 0 }) { _ in
            if self.alpha == 0 { self.isHidden = true }
        }
    }

    func setState(_ newState: SearchSheetState, animated: Bool) {
        state = newState
        updateChevron()
        applyHeight(animated: animated)
        onStateChange?(newState)
    }

    /// New rows and a new height. Applied now — unless a finger is on the
    /// list, in which case it waits: a reload or a frame change landing
    /// mid-touch cancels the tap (the "tapped a result, nothing happened" bug).
    func setContent(plan: HomeSearchPlan, title: String) {
        titleLabel.text = title
        let newContent = SearchSheetLayout.contentHeight(for: plan)
        let apply = { [weak self] in
            guard let self else { return }
            self.contentHeight = newContent
            self.applyHeight(animated: true)
            self.tableView.reloadData()
        }
        if isInteracting {
            pendingUpdate = apply
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.4) { [weak self] in self?.flushPendingUpdateIfIdle() }
        } else {
            apply()
        }
    }

    /// The keyboard moved: the bottom edge follows its layout guide on its
    /// own; the height re-fits the new room in the same animation.
    func updateAvailableHeight(_ height: CGFloat, duration: TimeInterval, options: UIView.AnimationOptions) {
        availableHeight = height
        guard !isHidden else { return }
        heightConstraint.constant = targetHeight
        UIView.animate(withDuration: max(duration, 0.1), delay: 0, options: options) {
            self.superview?.layoutIfNeeded()
        }
    }

    func setRowHighlighted(_ highlighted: Bool) {
        isRowHighlighted = highlighted
        if !highlighted { flushPendingUpdateIfIdle() }
    }

    func flushPendingUpdateIfIdle() {
        guard !isInteracting, let update = pendingUpdate else { return }
        pendingUpdate = nil
        update()
    }

    // MARK: - Geometry

    private var isInteracting: Bool {
        tableView.isTracking || tableView.isDragging || tableView.isDecelerating || isRowHighlighted
    }

    private var expandedHeight: CGFloat {
        SearchSheetLayout.expandedHeight(available: availableHeight, content: contentHeight)
    }

    private var targetHeight: CGFloat {
        SearchSheetLayout.height(for: state, available: availableHeight, content: contentHeight)
    }

    private func applyHeight(animated: Bool) {
        heightConstraint.constant = targetHeight
        guard animated else { superview?.layoutIfNeeded(); return }
        UIView.animate(withDuration: 0.25, delay: 0, options: [.curveEaseOut]) {
            self.superview?.layoutIfNeeded()
        }
    }

    private func updateChevron() {
        let name = state == .expanded ? "chevron.down" : "chevron.up"
        chevron.image = UIImage(systemName: name, withConfiguration: UIImage.SymbolConfiguration(pointSize: 13, weight: .semibold))
    }

    // MARK: - Drag

    @objc private func handleTapped() { onHandleTap?() }

    @objc private func handlePanned(_ pan: UIPanGestureRecognizer) {
        let translation = pan.translation(in: self).y
        switch pan.state {
        case .began:
            dragStartHeight = heightConstraint.constant
        case .changed:
            let wanted = dragStartHeight - translation
            heightConstraint.constant = min(max(wanted, SearchSheetLayout.handleHeight), expandedHeight)
            superview?.layoutIfNeeded()
        case .ended, .cancelled, .failed:
            let next = SearchSheetDetentResolver.resolve(
                from: state,
                translationY: translation,
                velocityY: pan.velocity(in: self).y,
                travel: expandedHeight - SearchSheetLayout.handleHeight
            )
            setState(next, animated: true)
        default:
            break
        }
    }

    // MARK: - Build

    private func build() {
        backgroundColor = .clear
        layer.shadowColor = UIColor.black.cgColor
        layer.shadowOpacity = 0.15
        layer.shadowOffset = CGSize(width: 0, height: -3)
        layer.shadowRadius = 8

        container.backgroundColor = Constants.Colors.secondaryBackground
        container.layer.cornerRadius = 16
        container.layer.maskedCorners = [.layerMinXMinYCorner, .layerMaxXMinYCorner]
        container.clipsToBounds = true
        container.translatesAutoresizingMaskIntoConstraints = false
        addSubview(container)

        handle.translatesAutoresizingMaskIntoConstraints = false
        handle.addGestureRecognizer(UITapGestureRecognizer(target: self, action: #selector(handleTapped)))
        handle.addGestureRecognizer(UIPanGestureRecognizer(target: self, action: #selector(handlePanned(_:))))
        container.addSubview(handle)

        grabber.backgroundColor = .tertiaryLabel
        grabber.layer.cornerRadius = 2.5
        grabber.translatesAutoresizingMaskIntoConstraints = false
        handle.addSubview(grabber)

        titleLabel.font = .systemFont(ofSize: 13, weight: .semibold)
        titleLabel.textColor = .secondaryLabel
        titleLabel.textAlignment = .center
        titleLabel.translatesAutoresizingMaskIntoConstraints = false
        handle.addSubview(titleLabel)

        chevron.tintColor = .secondaryLabel
        chevron.contentMode = .center
        chevron.translatesAutoresizingMaskIntoConstraints = false
        handle.addSubview(chevron)
        updateChevron()

        container.addSubview(tableView)

        NSLayoutConstraint.activate([
            container.topAnchor.constraint(equalTo: topAnchor),
            container.leadingAnchor.constraint(equalTo: leadingAnchor),
            container.trailingAnchor.constraint(equalTo: trailingAnchor),
            container.bottomAnchor.constraint(equalTo: bottomAnchor),

            handle.topAnchor.constraint(equalTo: container.topAnchor),
            handle.leadingAnchor.constraint(equalTo: container.leadingAnchor),
            handle.trailingAnchor.constraint(equalTo: container.trailingAnchor),
            handle.heightAnchor.constraint(equalToConstant: SearchSheetLayout.handleHeight),

            grabber.topAnchor.constraint(equalTo: handle.topAnchor, constant: 8),
            grabber.centerXAnchor.constraint(equalTo: handle.centerXAnchor),
            grabber.widthAnchor.constraint(equalToConstant: 36),
            grabber.heightAnchor.constraint(equalToConstant: 5),

            titleLabel.topAnchor.constraint(equalTo: grabber.bottomAnchor, constant: 8),
            titleLabel.leadingAnchor.constraint(equalTo: handle.leadingAnchor, constant: 44),
            titleLabel.trailingAnchor.constraint(equalTo: handle.trailingAnchor, constant: -44),

            chevron.centerYAnchor.constraint(equalTo: titleLabel.centerYAnchor),
            chevron.trailingAnchor.constraint(equalTo: handle.trailingAnchor, constant: -16),
            chevron.widthAnchor.constraint(equalToConstant: 20),
            chevron.heightAnchor.constraint(equalToConstant: 20),

            tableView.topAnchor.constraint(equalTo: handle.bottomAnchor),
            tableView.leadingAnchor.constraint(equalTo: container.leadingAnchor),
            tableView.trailingAnchor.constraint(equalTo: container.trailingAnchor),
            tableView.bottomAnchor.constraint(equalTo: container.bottomAnchor)
        ])
    }
}

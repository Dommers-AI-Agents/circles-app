import UIKit

protocol InnerCircleRingViewDelegate: AnyObject {
    /// The add bubble on the ring
    func ringViewDidTapAdd(_ ringView: InnerCircleRingView)
    /// One person's face
    func ringView(_ ringView: InnerCircleRingView, didTap person: User, from sourceView: UIView)
    /// The middle of the ring, or "+N": show everyone on the list
    func ringViewDidTapSeeEveryone(_ ringView: InnerCircleRingView)
}

/// One inner circle drawn as what it is: a circle, the list's name in the
/// middle, and the people on it as faces around the ring. A long list shows
/// as many faces as fit and "+N" for the rest; the last bubble adds someone.
///
/// Which bubbles appear and where is decided by `InnerCircleRingLayout`
/// (pure, tested); this view only draws them.
final class InnerCircleRingView: UIView {

    static let bubbleDiameter: CGFloat = 46
    private static let bubbleGap: CGFloat = 10

    let list: InnerCircleNamedList
    weak var delegate: InnerCircleRingViewDelegate?

    private let diameter: CGFloat
    private let ringLayer = CAShapeLayer()
    private var faces: [(view: AvatarView, person: User)] = []
    private var borderedBubbles: [UIView] = []

    /// The radius of the line the bubbles sit on
    private var ringRadius: CGFloat { diameter / 2 - Self.bubbleDiameter / 2 - 2 }

    init(list: InnerCircleNamedList, maxSize: Int, diameter: CGFloat) {
        self.list = list
        self.diameter = diameter
        super.init(frame: .zero)
        translatesAutoresizingMaskIntoConstraints = false
        NSLayoutConstraint.activate([
            widthAnchor.constraint(equalToConstant: diameter),
            heightAnchor.constraint(equalToConstant: diameter)
        ])

        ringLayer.lineWidth = 2
        layer.addSublayer(ringLayer)

        buildCenter()
        buildBubbles(maxSize: maxSize)
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    // MARK: - Drawing

    override func layoutSubviews() {
        super.layoutSubviews()
        let center = CGPoint(x: bounds.midX, y: bounds.midY)
        ringLayer.frame = bounds
        ringLayer.path = UIBezierPath(arcCenter: center, radius: ringRadius,
                                      startAngle: 0, endAngle: 2 * .pi, clockwise: true).cgPath
        applyColors()
    }

    override func traitCollectionDidChange(_ previous: UITraitCollection?) {
        super.traitCollectionDidChange(previous)
        if previous?.hasDifferentColorAppearance(comparedTo: traitCollection) ?? true { applyColors() }
    }

    /// Layer colours don't follow light/dark by themselves
    private func applyColors() {
        let primary = Constants.Colors.primary.resolvedColor(with: traitCollection)
        ringLayer.strokeColor = primary.withAlphaComponent(list.userIds.isEmpty ? 0.25 : 0.45).cgColor
        ringLayer.fillColor = primary.withAlphaComponent(0.07).cgColor
        // An empty circle is drawn dashed: there is nobody in it yet
        ringLayer.lineDashPattern = list.userIds.isEmpty ? [6, 6] : nil
        let border = Constants.Colors.background.resolvedColor(with: traitCollection).cgColor
        for bubble in borderedBubbles { bubble.layer.borderColor = border }
    }

    // MARK: - The middle: the list's name and how many people

    private func buildCenter() {
        let nameLabel = UILabel()
        nameLabel.text = list.name
        nameLabel.font = .systemFont(ofSize: 21, weight: .bold)
        nameLabel.textColor = Constants.Colors.label
        nameLabel.textAlignment = .center
        nameLabel.numberOfLines = 2
        nameLabel.adjustsFontSizeToFitWidth = true
        nameLabel.minimumScaleFactor = 0.7

        let count = list.userIds.count
        let countLabel = UILabel()
        countLabel.text = InnerCircleEditing.summary(memberCount: count)
        countLabel.font = .systemFont(ofSize: 13, weight: .medium)
        countLabel.textColor = count == 0 ? Constants.Colors.danger : Constants.Colors.secondaryLabel
        countLabel.textAlignment = .center
        countLabel.numberOfLines = 0

        let stack = UIStackView(arrangedSubviews: [nameLabel, countLabel])
        stack.axis = .vertical
        stack.spacing = 4
        stack.isUserInteractionEnabled = false
        stack.translatesAutoresizingMaskIntoConstraints = false

        // The whole inside of the ring opens the full list
        let inside = UIControl()
        inside.translatesAutoresizingMaskIntoConstraints = false
        inside.addTarget(self, action: #selector(seeEveryoneTapped), for: .touchUpInside)
        inside.isAccessibilityElement = true
        inside.accessibilityTraits = .button
        inside.accessibilityLabel = "\(list.name), \(InnerCircleEditing.summary(memberCount: count))"
        inside.accessibilityHint = "Shows everyone on this list"
        let insideDiameter = max(0, (ringRadius - Self.bubbleDiameter / 2 - 6) * 2)
        inside.layer.cornerRadius = insideDiameter / 2

        addSubview(inside)
        inside.addSubview(stack)
        NSLayoutConstraint.activate([
            inside.centerXAnchor.constraint(equalTo: centerXAnchor),
            inside.centerYAnchor.constraint(equalTo: centerYAnchor),
            inside.widthAnchor.constraint(equalToConstant: insideDiameter),
            inside.heightAnchor.constraint(equalToConstant: insideDiameter),
            stack.centerXAnchor.constraint(equalTo: inside.centerXAnchor),
            stack.centerYAnchor.constraint(equalTo: inside.centerYAnchor),
            // Inside the circle, not just its bounding square
            stack.widthAnchor.constraint(lessThanOrEqualTo: inside.widthAnchor, multiplier: 0.8)
        ])
    }

    // MARK: - The ring: faces, "+N", add

    private func buildBubbles(maxSize: Int) {
        let capacity = InnerCircleRingLayout.capacity(ringRadius: ringRadius,
                                                      bubbleDiameter: Self.bubbleDiameter,
                                                      minimumGap: Self.bubbleGap)
        let slots = InnerCircleRingLayout.slots(memberCount: list.users.count,
                                                capacity: capacity,
                                                canAdd: list.userIds.count < maxSize)
        let center = CGPoint(x: diameter / 2, y: diameter / 2)

        for (position, slot) in slots.enumerated() {
            let bubble: UIView
            switch slot {
            case .member(let index):
                bubble = makeFace(for: list.users[index])
            case .overflow(let count):
                // Counts everyone not drawn, including anyone the server
                // listed by id without a profile
                bubble = makeOverflowBubble(count: count + max(0, list.userIds.count - list.users.count))
            case .add:
                bubble = makeAddBubble()
            }
            addSubview(bubble)
            let point = InnerCircleRingLayout.point(forSlot: position, of: slots.count,
                                                    ringRadius: ringRadius, around: center)
            NSLayoutConstraint.activate([
                bubble.centerXAnchor.constraint(equalTo: leadingAnchor, constant: point.x),
                bubble.centerYAnchor.constraint(equalTo: topAnchor, constant: point.y)
            ])
        }
    }

    private func makeFace(for person: User) -> UIView {
        let avatar = AvatarView(diameter: Self.bubbleDiameter)
        avatar.configure(with: person)
        avatar.layer.borderWidth = 2
        avatar.isUserInteractionEnabled = true
        avatar.addGestureRecognizer(UITapGestureRecognizer(target: self, action: #selector(faceTapped(_:))))
        avatar.isAccessibilityElement = true
        avatar.accessibilityTraits = .button
        avatar.accessibilityLabel = person.displayName
        avatar.accessibilityHint = "Shows their profile, or removes them from \(list.name)"
        faces.append((avatar, person))
        borderedBubbles.append(avatar)
        return avatar
    }

    private func makeOverflowBubble(count: Int) -> UIView {
        let label = UILabel()
        label.text = "+\(count)"
        label.font = .systemFont(ofSize: 14, weight: .bold)
        label.textColor = .white
        label.textAlignment = .center
        label.adjustsFontSizeToFitWidth = true
        label.minimumScaleFactor = 0.6
        label.backgroundColor = Constants.Colors.primary
        label.layer.cornerRadius = Self.bubbleDiameter / 2
        label.layer.borderWidth = 2
        label.clipsToBounds = true
        label.translatesAutoresizingMaskIntoConstraints = false
        label.isUserInteractionEnabled = true
        label.addGestureRecognizer(UITapGestureRecognizer(target: self, action: #selector(seeEveryoneTapped)))
        label.isAccessibilityElement = true
        label.accessibilityTraits = .button
        label.accessibilityLabel = "\(count) more on \(list.name)"
        label.accessibilityHint = "Shows everyone on this list"
        NSLayoutConstraint.activate([
            label.widthAnchor.constraint(equalToConstant: Self.bubbleDiameter),
            label.heightAnchor.constraint(equalToConstant: Self.bubbleDiameter)
        ])
        borderedBubbles.append(label)
        return label
    }

    private func makeAddBubble() -> UIView {
        let button = UIButton.iconButton(systemName: "plus", pointSize: 18)
        button.tintColor = .white
        button.backgroundColor = Constants.Colors.primary
        button.layer.cornerRadius = Self.bubbleDiameter / 2
        button.layer.borderWidth = 2
        button.accessibilityLabel = "Add people to \(list.name)"
        button.addTarget(self, action: #selector(addTapped), for: .touchUpInside)
        NSLayoutConstraint.activate([
            button.widthAnchor.constraint(equalToConstant: Self.bubbleDiameter),
            button.heightAnchor.constraint(equalToConstant: Self.bubbleDiameter)
        ])
        borderedBubbles.append(button)
        return button
    }

    // MARK: - Taps

    @objc private func addTapped() {
        delegate?.ringViewDidTapAdd(self)
    }

    @objc private func seeEveryoneTapped() {
        delegate?.ringViewDidTapSeeEveryone(self)
    }

    @objc private func faceTapped(_ gesture: UITapGestureRecognizer) {
        guard let tapped = gesture.view,
              let face = faces.first(where: { $0.view === tapped }) else { return }
        delegate?.ringView(self, didTap: face.person, from: tapped)
    }
}

/// The dashed, empty circle that starts a new inner circle: small at the end
/// of the rings, large as the whole page when there are none yet.
final class NewInnerCircleControl: UIControl {

    private let dashLayer = CAShapeLayer()
    private let diameter: CGFloat

    init(diameter: CGFloat, title: String) {
        self.diameter = diameter
        super.init(frame: .zero)
        translatesAutoresizingMaskIntoConstraints = false

        dashLayer.lineWidth = 2
        dashLayer.lineDashPattern = [7, 7]
        layer.addSublayer(dashLayer)

        let plus = UIImageView(image: UIImage(systemName: "plus",
                                              withConfiguration: UIImage.SymbolConfiguration(pointSize: diameter * 0.2, weight: .semibold)))
        plus.tintColor = Constants.Colors.primary
        plus.contentMode = .center

        let label = UILabel()
        label.text = title
        label.font = .systemFont(ofSize: diameter >= 160 ? 16 : 13, weight: .semibold)
        label.textColor = Constants.Colors.primary
        label.textAlignment = .center
        label.numberOfLines = 2

        let stack = UIStackView(arrangedSubviews: [plus, label])
        stack.axis = .vertical
        stack.spacing = 6
        stack.alignment = .center
        stack.isUserInteractionEnabled = false
        stack.translatesAutoresizingMaskIntoConstraints = false
        addSubview(stack)

        NSLayoutConstraint.activate([
            widthAnchor.constraint(equalToConstant: diameter),
            heightAnchor.constraint(equalToConstant: diameter),
            stack.centerXAnchor.constraint(equalTo: centerXAnchor),
            stack.centerYAnchor.constraint(equalTo: centerYAnchor),
            stack.widthAnchor.constraint(lessThanOrEqualTo: widthAnchor, multiplier: 0.7)
        ])

        isAccessibilityElement = true
        accessibilityTraits = .button
        accessibilityLabel = title
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    override func layoutSubviews() {
        super.layoutSubviews()
        dashLayer.frame = bounds
        dashLayer.path = UIBezierPath(ovalIn: bounds.insetBy(dx: 2, dy: 2)).cgPath
        applyColors()
    }

    override func traitCollectionDidChange(_ previous: UITraitCollection?) {
        super.traitCollectionDidChange(previous)
        if previous?.hasDifferentColorAppearance(comparedTo: traitCollection) ?? true { applyColors() }
    }

    private func applyColors() {
        let primary = Constants.Colors.primary.resolvedColor(with: traitCollection)
        dashLayer.strokeColor = primary.withAlphaComponent(0.6).cgColor
        dashLayer.fillColor = primary.withAlphaComponent(isHighlighted ? 0.16 : 0.06).cgColor
    }

    override var isHighlighted: Bool {
        didSet { applyColors() }
    }
}

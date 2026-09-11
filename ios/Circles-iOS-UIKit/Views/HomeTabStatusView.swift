import UIKit

/// The loading card + empty-state message a home content tab shows over
/// its list: a small rounded spinner card while fetching, or a centered
/// message when there's nothing to show. One per tab, so a fetch finishing
/// on a hidden tab can't write its message onto the visible one.
final class HomeTabStatusView: UIView {
    private let loadingContainer: UIView = {
        let container = UIView()
        container.backgroundColor = UIColor.systemBackground.withAlphaComponent(0.95)
        container.layer.cornerRadius = 12
        container.layer.shadowColor = UIColor.black.cgColor
        container.layer.shadowOpacity = 0.1
        container.layer.shadowOffset = CGSize(width: 0, height: 2)
        container.layer.shadowRadius = 4
        container.translatesAutoresizingMaskIntoConstraints = false
        container.isHidden = true
        return container
    }()

    private let loadingIndicator: UIActivityIndicatorView = {
        let indicator = UIActivityIndicatorView(style: .large)
        indicator.color = Constants.Colors.primary
        indicator.hidesWhenStopped = false
        indicator.translatesAutoresizingMaskIntoConstraints = false
        return indicator
    }()

    private let messageLabel: UILabel = {
        let label = UILabel()
        label.font = UIFont.systemFont(ofSize: 16)
        label.textColor = Constants.Colors.secondaryLabel
        label.textAlignment = .center
        label.numberOfLines = 0
        label.translatesAutoresizingMaskIntoConstraints = false
        label.isHidden = true
        return label
    }()

    override init(frame: CGRect) {
        super.init(frame: frame)
        translatesAutoresizingMaskIntoConstraints = false
        isUserInteractionEnabled = false
        addSubview(messageLabel)
        addSubview(loadingContainer)
        loadingContainer.addSubview(loadingIndicator)
        NSLayoutConstraint.activate([
            messageLabel.centerXAnchor.constraint(equalTo: centerXAnchor),
            messageLabel.centerYAnchor.constraint(equalTo: centerYAnchor),
            messageLabel.leadingAnchor.constraint(equalTo: leadingAnchor, constant: Constants.Spacing.large),
            messageLabel.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -Constants.Spacing.large),

            loadingContainer.centerXAnchor.constraint(equalTo: centerXAnchor),
            loadingContainer.centerYAnchor.constraint(equalTo: centerYAnchor),
            loadingContainer.widthAnchor.constraint(equalToConstant: 80),
            loadingContainer.heightAnchor.constraint(equalToConstant: 80),
            loadingIndicator.centerXAnchor.constraint(equalTo: loadingContainer.centerXAnchor),
            loadingIndicator.centerYAnchor.constraint(equalTo: loadingContainer.centerYAnchor)
        ])
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    var isLoading: Bool {
        get { !loadingContainer.isHidden }
        set {
            loadingContainer.isHidden = !newValue
            if newValue {
                loadingIndicator.startAnimating()
                messageLabel.isHidden = true
            } else {
                loadingIndicator.stopAnimating()
            }
        }
    }

    /// The empty-state / error message; `nil` hides it.
    var message: String? {
        get { messageLabel.isHidden ? nil : messageLabel.text }
        set {
            messageLabel.text = newValue
            messageLabel.isHidden = newValue == nil
        }
    }
}

import UIKit

/// The card for an Activity row with nothing else to show (Wes, 2026-11-19:
/// "I want every activity to have a full pretty card"): the actor's photo
/// blown up and blurred as the wash, the kind's colour over it, a big symbol,
/// and the thing's name in large type. Never a flat blank rectangle.
final class ActivityPosterView: UIView {
    private let backdrop: UIImageView = {
        let view = UIImageView()
        view.contentMode = .scaleAspectFill
        view.clipsToBounds = true
        view.alpha = 0.9
        return view
    }()
    private let blur = UIVisualEffectView(effect: UIBlurEffect(style: .systemUltraThinMaterialDark))
    private let wash = CAGradientLayer()
    private let symbolView: UIImageView = {
        let view = UIImageView()
        view.contentMode = .scaleAspectFit
        view.tintColor = UIColor.white.withAlphaComponent(0.92)
        view.preferredSymbolConfiguration = UIImage.SymbolConfiguration(pointSize: 46, weight: .semibold)
        view.translatesAutoresizingMaskIntoConstraints = false
        return view
    }()
    private let titleLabel: UILabel = {
        let label = UILabel()
        label.font = UIFont.systemFont(ofSize: 24, weight: .bold)
        label.textColor = .white
        label.numberOfLines = 3
        label.adjustsFontSizeToFitWidth = true
        label.minimumScaleFactor = 0.7
        label.translatesAutoresizingMaskIntoConstraints = false
        label.layer.shadowColor = UIColor.black.cgColor
        label.layer.shadowOpacity = 0.35
        label.layer.shadowRadius = 4
        label.layer.shadowOffset = CGSize(width: 0, height: 1)
        return label
    }()
    private let detailLabel: UILabel = {
        let label = UILabel()
        label.font = UIFont.systemFont(ofSize: 15, weight: .semibold)
        label.textColor = UIColor.white.withAlphaComponent(0.9)
        label.numberOfLines = 2
        label.translatesAutoresizingMaskIntoConstraints = false
        return label
    }()

    override init(frame: CGRect) {
        super.init(frame: frame)
        clipsToBounds = true
        isUserInteractionEnabled = false
        backdrop.frame = bounds
        backdrop.autoresizingMask = [.flexibleWidth, .flexibleHeight]
        blur.frame = bounds
        blur.autoresizingMask = [.flexibleWidth, .flexibleHeight]
        addSubview(backdrop)
        addSubview(blur)
        wash.startPoint = CGPoint(x: 0, y: 0)
        wash.endPoint = CGPoint(x: 1, y: 1)
        layer.addSublayer(wash)
        addSubview(symbolView)
        addSubview(titleLabel)
        addSubview(detailLabel)
        NSLayoutConstraint.activate([
            symbolView.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -18),
            symbolView.topAnchor.constraint(equalTo: topAnchor, constant: 16),
            symbolView.widthAnchor.constraint(equalToConstant: 56),
            symbolView.heightAnchor.constraint(equalToConstant: 56),
            detailLabel.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 16),
            detailLabel.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -16),
            detailLabel.bottomAnchor.constraint(equalTo: bottomAnchor, constant: -14),
            titleLabel.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 16),
            titleLabel.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -16),
            titleLabel.bottomAnchor.constraint(equalTo: detailLabel.topAnchor, constant: -2),
            titleLabel.topAnchor.constraint(greaterThanOrEqualTo: symbolView.bottomAnchor, constant: 8)
        ])
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    override func layoutSubviews() {
        super.layoutSubviews()
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        wash.frame = bounds
        CATransaction.commit()
    }

    func configure(_ poster: ActivityRowStyle.Poster) {
        symbolView.image = UIImage(systemName: poster.symbol)
        titleLabel.text = poster.title
        detailLabel.text = poster.detail
        detailLabel.isHidden = poster.detail == nil
        let (a, b) = Self.colors(poster.tint)
        wash.colors = [a.withAlphaComponent(0.92).cgColor, b.withAlphaComponent(0.78).cgColor]
        backgroundColor = a
    }

    /// The actor's photo under the wash; nil leaves the colour alone
    func setBackdrop(_ image: UIImage?) {
        backdrop.image = image
        blur.isHidden = image == nil
    }

    func reset() {
        backdrop.image = nil
        symbolView.image = nil
        titleLabel.text = nil
        detailLabel.text = nil
    }

    /// Two colours per kind, the brand's blue for anything about a place
    static func colors(_ tint: ActivityRowStyle.Tint) -> (UIColor, UIColor) {
        switch tint {
        case .brand: return (UIColor(red: 0.10, green: 0.42, blue: 0.86, alpha: 1), UIColor(red: 0.25, green: 0.70, blue: 0.95, alpha: 1))
        case .like: return (UIColor(red: 0.85, green: 0.18, blue: 0.38, alpha: 1), UIColor(red: 0.98, green: 0.45, blue: 0.40, alpha: 1))
        case .comment: return (UIColor(red: 0.05, green: 0.55, blue: 0.56, alpha: 1), UIColor(red: 0.20, green: 0.78, blue: 0.70, alpha: 1))
        case .circle: return (UIColor(red: 0.42, green: 0.25, blue: 0.80, alpha: 1), UIColor(red: 0.66, green: 0.45, blue: 0.95, alpha: 1))
        case .workout: return (UIColor(red: 0.19, green: 0.51, blue: 0.81, alpha: 1), UIColor(red: 0.30, green: 0.70, blue: 0.90, alpha: 1))
        case .run: return (UIColor(red: 0.87, green: 0.42, blue: 0.13, alpha: 1), UIColor(red: 0.98, green: 0.62, blue: 0.25, alpha: 1))
        case .mail: return (UIColor(red: 0.78, green: 0.45, blue: 0.20, alpha: 1), UIColor(red: 0.95, green: 0.70, blue: 0.40, alpha: 1))
        case .people: return (UIColor(red: 0.30, green: 0.36, blue: 0.52, alpha: 1), UIColor(red: 0.50, green: 0.58, blue: 0.75, alpha: 1))
        case .store: return (UIColor(red: 0.16, green: 0.50, blue: 0.36, alpha: 1), UIColor(red: 0.30, green: 0.72, blue: 0.52, alpha: 1))
        }
    }
}

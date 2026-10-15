import UIKit

/// The "i" on a widget's page: what the widget is and what it can do.
final class WidgetAboutViewController: BaseViewController {
    override var loadsDataOnViewDidLoad: Bool { false }
    override var showsLoadingIndicator: Bool { false }

    private let about: WidgetAbout
    private let symbolName: String
    private let accent: UIColor

    init(about: WidgetAbout, symbolName: String, accent: UIColor) {
        self.about = about
        self.symbolName = symbolName
        self.accent = accent
        super.init(nibName: nil, bundle: nil)
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    override func viewDidLoad() {
        super.viewDidLoad()
        view.backgroundColor = Constants.Colors.background
        navigationItem.rightBarButtonItem = UIBarButtonItem(barButtonSystemItem: .close, target: self, action: #selector(closeTapped))

        let scroll = UIScrollView()
        scroll.translatesAutoresizingMaskIntoConstraints = false
        scroll.alwaysBounceVertical = true
        view.addSubview(scroll)

        let icon = UIImageView(image: UIImage(systemName: symbolName))
        icon.tintColor = .white
        icon.contentMode = .scaleAspectFit
        let badge = UIView()
        badge.backgroundColor = accent
        badge.layer.cornerRadius = 14
        badge.layer.cornerCurve = .continuous
        icon.translatesAutoresizingMaskIntoConstraints = false
        badge.translatesAutoresizingMaskIntoConstraints = false
        badge.addSubview(icon)
        NSLayoutConstraint.activate([
            badge.widthAnchor.constraint(equalToConstant: 56), badge.heightAnchor.constraint(equalToConstant: 56),
            icon.centerXAnchor.constraint(equalTo: badge.centerXAnchor), icon.centerYAnchor.constraint(equalTo: badge.centerYAnchor),
            icon.widthAnchor.constraint(equalToConstant: 28), icon.heightAnchor.constraint(equalToConstant: 28)
        ])

        let name = label(about.name, font: .systemFont(ofSize: 26, weight: .bold), color: .label)
        let tagline = label(about.tagline, font: .systemFont(ofSize: 17), color: .secondaryLabel)

        let stack = UIStackView(arrangedSubviews: [badge, name, tagline])
        stack.axis = .vertical
        stack.alignment = .leading
        stack.spacing = 8
        stack.setCustomSpacing(14, after: badge)
        if !about.features.isEmpty {
            let header = label("WHAT IT DOES", font: .systemFont(ofSize: 13, weight: .semibold), color: .secondaryLabel)
            stack.addArrangedSubview(header)
            stack.setCustomSpacing(24, after: tagline)
            stack.setCustomSpacing(12, after: header)
            for feature in about.features {
                stack.addArrangedSubview(featureRow(feature))
            }
        }
        stack.translatesAutoresizingMaskIntoConstraints = false
        scroll.addSubview(stack)
        NSLayoutConstraint.activate([
            scroll.topAnchor.constraint(equalTo: view.safeAreaLayoutGuide.topAnchor),
            scroll.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            scroll.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            scroll.bottomAnchor.constraint(equalTo: view.bottomAnchor),
            stack.topAnchor.constraint(equalTo: scroll.contentLayoutGuide.topAnchor, constant: 8),
            stack.leadingAnchor.constraint(equalTo: scroll.frameLayoutGuide.leadingAnchor, constant: 24),
            stack.trailingAnchor.constraint(equalTo: scroll.frameLayoutGuide.trailingAnchor, constant: -24),
            stack.bottomAnchor.constraint(equalTo: scroll.contentLayoutGuide.bottomAnchor, constant: -32)
        ])
    }

    private func label(_ text: String, font: UIFont, color: UIColor) -> UILabel {
        let label = UILabel()
        label.text = text
        label.font = font
        label.textColor = color
        label.numberOfLines = 0
        return label
    }

    private func featureRow(_ text: String) -> UIView {
        let check = UIImageView(image: UIImage(systemName: "checkmark.circle.fill"))
        check.tintColor = accent
        check.setContentHuggingPriority(.required, for: .horizontal)
        check.translatesAutoresizingMaskIntoConstraints = false
        check.widthAnchor.constraint(equalToConstant: 20).isActive = true
        check.heightAnchor.constraint(equalToConstant: 20).isActive = true
        let row = UIStackView(arrangedSubviews: [check, label(text, font: .systemFont(ofSize: 16), color: .label)])
        row.alignment = .top
        row.spacing = 10
        return row
    }

    @objc private func closeTapped() {
        dismiss(animated: true)
    }
}

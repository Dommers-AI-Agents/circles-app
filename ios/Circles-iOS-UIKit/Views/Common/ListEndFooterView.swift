import UIKit

/// The bottom of a list is never the end (2026-11-02): "You're all caught
/// up" and one button somewhere worth going. Set as a table's footer view
/// (it sizes itself) or added to a stack.
final class ListEndFooterView: UIView {
    private let onTap: () -> Void
    private let surface: String
    private let stepId: String

    init(text: String, step: NextStep, surface: String, onTap: @escaping () -> Void) {
        self.onTap = onTap
        self.surface = surface
        self.stepId = step.id
        super.init(frame: CGRect(x: 0, y: 0, width: 320, height: 128))
        let label = UILabel()
        label.text = text
        label.font = .preferredFont(forTextStyle: .subheadline)
        label.adjustsFontForContentSizeCategory = true
        label.textColor = .secondaryLabel
        label.textAlignment = .center
        label.numberOfLines = 0
        let button = UIButton.smallActionButton(title: step.title, style: .primary)
        button.addTarget(self, action: #selector(tapped), for: .touchUpInside)
        let stack = UIStackView(arrangedSubviews: [label, button])
        stack.axis = .vertical
        stack.alignment = .center
        stack.spacing = 12
        stack.translatesAutoresizingMaskIntoConstraints = false
        addSubview(stack)
        NSLayoutConstraint.activate([
            stack.topAnchor.constraint(equalTo: topAnchor, constant: 24),
            stack.bottomAnchor.constraint(equalTo: bottomAnchor, constant: -32),
            stack.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 24),
            stack.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -24)
        ])
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    @objc private func tapped() {
        AnalyticsService.shared.logEvent("next_step_tapped", parameters: ["surface": surface, "step": stepId])
        onTap()
    }
}

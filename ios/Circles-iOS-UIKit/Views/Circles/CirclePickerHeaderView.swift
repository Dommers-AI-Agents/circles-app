import UIKit

/// The words above a circle picker's list: a headline and the why (Wes,
/// 2026-11-09: the sheet asked for a circle without saying what one is for).
/// Sized for a table header at the given width.
enum CirclePickerHeaderView {
    static func make(headline: String, explanation: String, width: CGFloat) -> UIView {
        let headlineLabel = UILabel()
        headlineLabel.text = headline
        headlineLabel.font = .systemFont(ofSize: 20, weight: .bold)
        headlineLabel.textColor = Constants.Colors.label
        headlineLabel.numberOfLines = 0

        let bodyLabel = UILabel()
        bodyLabel.text = explanation
        bodyLabel.font = .systemFont(ofSize: 15)
        bodyLabel.textColor = Constants.Colors.secondaryLabel
        bodyLabel.numberOfLines = 0

        let stack = UIStackView(arrangedSubviews: [headlineLabel, bodyLabel])
        stack.axis = .vertical
        stack.spacing = 6
        stack.translatesAutoresizingMaskIntoConstraints = false

        let header = UIView()
        header.addSubview(stack)
        NSLayoutConstraint.activate([
            stack.topAnchor.constraint(equalTo: header.topAnchor, constant: Constants.Spacing.small),
            stack.leadingAnchor.constraint(equalTo: header.leadingAnchor, constant: 20),
            stack.trailingAnchor.constraint(equalTo: header.trailingAnchor, constant: -20),
            stack.bottomAnchor.constraint(equalTo: header.bottomAnchor, constant: -Constants.Spacing.small)
        ])
        let size = header.systemLayoutSizeFitting(
            CGSize(width: width, height: UIView.layoutFittingCompressedSize.height),
            withHorizontalFittingPriority: .required,
            verticalFittingPriority: .fittingSizeLevel
        )
        header.frame = CGRect(x: 0, y: 0, width: width, height: size.height)
        return header
    }
}

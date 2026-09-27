import UIKit

/// Hosts a segmented control in a horizontal scroll view so every segment
/// keeps its full title: segments size to their text, the control fills the
/// row when they fit and scrolls sideways when they don't. The control is
/// the caller's; this only lays it out.
final class ScrollingSegmentHost: UIScrollView {
    let segmentedControl: UISegmentedControl

    init(segmentedControl: UISegmentedControl, sideInset: CGFloat = 0) {
        self.segmentedControl = segmentedControl
        super.init(frame: .zero)
        translatesAutoresizingMaskIntoConstraints = false
        showsHorizontalScrollIndicator = false
        alwaysBounceHorizontal = false
        clipsToBounds = true

        segmentedControl.apportionsSegmentWidthsByContent = true
        segmentedControl.translatesAutoresizingMaskIntoConstraints = false
        segmentedControl.addTarget(self, action: #selector(selectionChanged), for: .valueChanged)
        addSubview(segmentedControl)

        NSLayoutConstraint.activate([
            segmentedControl.leadingAnchor.constraint(equalTo: contentLayoutGuide.leadingAnchor, constant: sideInset),
            segmentedControl.trailingAnchor.constraint(equalTo: contentLayoutGuide.trailingAnchor, constant: -sideInset),
            segmentedControl.topAnchor.constraint(equalTo: contentLayoutGuide.topAnchor),
            segmentedControl.bottomAnchor.constraint(equalTo: contentLayoutGuide.bottomAnchor),
            segmentedControl.heightAnchor.constraint(equalTo: frameLayoutGuide.heightAnchor),
            // Fill the row when the titles fit; grow past it (and scroll) when not.
            segmentedControl.widthAnchor.constraint(greaterThanOrEqualTo: frameLayoutGuide.widthAnchor, constant: -2 * sideInset)
        ])
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    @objc private func selectionChanged() { scrollSelectedSegmentIntoView(animated: true) }

    /// Brings the selected segment on screen. Call after setting
    /// selectedSegmentIndex in code (valueChanged doesn't fire then).
    func scrollSelectedSegmentIntoView(animated: Bool) {
        let index = segmentedControl.selectedSegmentIndex
        let count = segmentedControl.numberOfSegments
        guard index >= 0, count > 0, contentSize.width > bounds.width else { return }
        layoutIfNeeded()
        // Segment frames aren't public; sum the content-apportioned widths.
        let widths = (0..<count).map { segmentWidth(at: $0) }
        let total = widths.reduce(0, +)
        guard total > 0 else { return }
        let scale = segmentedControl.bounds.width / total
        let x = widths[..<index].reduce(0, +) * scale
        let rect = CGRect(x: segmentedControl.frame.minX + x, y: 0, width: widths[index] * scale, height: bounds.height)
        scrollRectToVisible(rect.insetBy(dx: -16, dy: 0), animated: animated)
    }

    private func segmentWidth(at index: Int) -> CGFloat {
        let explicit = segmentedControl.widthForSegment(at: index)
        if explicit > 0 { return explicit }
        let title = segmentedControl.titleForSegment(at: index) ?? ""
        let font = (segmentedControl.titleTextAttributes(for: .normal)?[.font] as? UIFont) ?? .systemFont(ofSize: 13, weight: .medium)
        return (title as NSString).size(withAttributes: [.font: font]).width + 24
    }
}

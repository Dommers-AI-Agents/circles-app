import UIKit

/// "Print a sign or tent": pick the shape (sign, table tent, small tent,
/// counter card, sticker sheet) and the code's printed size, then hand the PDF to the share
/// sheet, where Print, AirDrop, Mail and Save to Files all live.
final class VenuePrintOptionsViewController: BaseViewController {

    override var loadsDataOnViewDidLoad: Bool { false }
    override var showsLoadingIndicator: Bool { false }

    private let venueId: String
    private let venueName: String
    private var options: VenuePrintOptions

    init(venueId: String, venueName: String, kind: VenuePrintKind) {
        self.venueId = venueId
        self.venueName = venueName
        self.options = VenuePrintOptions(kind: kind)
        super.init(nibName: nil, bundle: nil)
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    // MARK: - UI

    private let titleLabel: UILabel = {
        let label = UILabel()
        label.font = UIFont.systemFont(ofSize: 22, weight: .bold)
        label.translatesAutoresizingMaskIntoConstraints = false
        return label
    }()

    private let formatHeading = VenuePrintOptionsViewController.heading("What to print")
    private let sizeHeading = VenuePrintOptionsViewController.heading("Size of the code")

    private lazy var formatControl: UISegmentedControl = {
        let control = UISegmentedControl(items: VenuePrintFormat.allCases.map(\.title))
        // Five shapes: each segment as wide as its word, so none truncates
        control.apportionsSegmentWidthsByContent = true
        control.selectedSegmentIndex = VenuePrintFormat.allCases.firstIndex(of: options.format) ?? 0
        control.addTarget(self, action: #selector(formatChanged), for: .valueChanged)
        control.translatesAutoresizingMaskIntoConstraints = false
        return control
    }()

    private lazy var sizeControl: UISegmentedControl = {
        let control = UISegmentedControl(items: VenuePrintQRSize.allCases.map(\.title))
        control.selectedSegmentIndex = VenuePrintQRSize.allCases.firstIndex(of: options.qrSize) ?? 1
        control.addTarget(self, action: #selector(sizeChanged), for: .valueChanged)
        control.translatesAutoresizingMaskIntoConstraints = false
        return control
    }()

    private let summaryLabel: UILabel = {
        let label = UILabel()
        label.font = UIFont.systemFont(ofSize: 14)
        label.textColor = Constants.Colors.secondaryLabel
        label.numberOfLines = 0
        label.translatesAutoresizingMaskIntoConstraints = false
        return label
    }()

    private lazy var printButton = UIButton.primaryButton(title: "Share or Print PDF")
    private lazy var cancelButton = UIButton.secondaryButton(title: "Cancel")

    private static func heading(_ text: String) -> UILabel {
        let label = UILabel()
        label.text = text.uppercased()
        label.font = UIFont.systemFont(ofSize: 12, weight: .semibold)
        label.textColor = Constants.Colors.secondaryLabel
        label.translatesAutoresizingMaskIntoConstraints = false
        return label
    }

    override func viewDidLoad() {
        super.viewDidLoad()
        view.backgroundColor = Constants.Colors.background
        titleLabel.text = "Print the \(options.kind == .window ? "window" : "register") code"

        let stack = UIStackView(arrangedSubviews: [
            titleLabel, formatHeading, formatControl, sizeHeading, sizeControl, summaryLabel, printButton, cancelButton
        ])
        stack.axis = .vertical
        stack.spacing = 12
        stack.setCustomSpacing(20, after: titleLabel)
        stack.setCustomSpacing(6, after: formatHeading)
        stack.setCustomSpacing(20, after: formatControl)
        stack.setCustomSpacing(6, after: sizeHeading)
        stack.setCustomSpacing(16, after: sizeControl)
        stack.setCustomSpacing(24, after: summaryLabel)
        stack.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(stack)

        printButton.addTarget(self, action: #selector(printTapped), for: .touchUpInside)
        cancelButton.addTarget(self, action: #selector(cancelTapped), for: .touchUpInside)

        NSLayoutConstraint.activate([
            stack.topAnchor.constraint(equalTo: view.safeAreaLayoutGuide.topAnchor, constant: 24),
            stack.leadingAnchor.constraint(equalTo: view.safeAreaLayoutGuide.leadingAnchor, constant: 24),
            stack.trailingAnchor.constraint(equalTo: view.safeAreaLayoutGuide.trailingAnchor, constant: -24)
        ])
        refreshSummary()
    }

    // MARK: - Choices

    @objc private func formatChanged() {
        options.format = VenuePrintFormat.allCases[formatControl.selectedSegmentIndex]
        refreshSummary()
    }

    @objc private func sizeChanged() {
        options.qrSize = VenuePrintQRSize.allCases[sizeControl.selectedSegmentIndex]
        refreshSummary()
    }

    private func refreshSummary() {
        summaryLabel.text = options.summary
        // A sticker sheet has one code size; the size row would only mislead
        let sized = options.format.hasQRSizeChoice
        sizeHeading.isHidden = !sized
        sizeControl.isHidden = !sized
    }

    @objc private func cancelTapped() {
        dismiss(animated: true)
    }

    // MARK: - The PDF

    @objc private func printTapped() {
        printButton.isEnabled = false
        let loading = AlertPresenter.showLoading(message: "Building your PDF…", from: self)
        let fileName = options.fileName(storeName: venueName)
        RewardsService.shared.downloadPrint(venueId: venueId, options: options) { [weak self] result in
            DispatchQueue.main.async {
                guard let self else { return }
                loading.dismiss(animated: true) {
                    self.printButton.isEnabled = true
                    switch result {
                    case .failure(let error):
                        self.showError(error)
                    case .success(let data):
                        self.share(pdf: data, fileName: fileName)
                    }
                }
            }
        }
    }

    /// The share sheet gets a real file with a readable name, so Print,
    /// Save to Files and Mail all show "Tommys Tavern - window table tent.pdf"
    private func share(pdf: Data, fileName: String) {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent(fileName)
        do {
            try pdf.write(to: url, options: .atomic)
        } catch {
            showError(error)
            return
        }
        let activity = UIActivityViewController(activityItems: [url], applicationActivities: nil)
        activity.popoverPresentationController?.sourceView = printButton
        present(activity, animated: true)
    }
}

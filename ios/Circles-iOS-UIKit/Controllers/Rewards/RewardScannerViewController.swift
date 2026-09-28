import UIKit
import AVFoundation
import VisionKit

/// Scans a store's rewards QR code from inside the app.
///
/// Until this screen, the only way in was the iPhone Camera app opening the
/// sticker's universal link. The code read here goes down exactly that path —
/// `StickerRewardCoordinator.handleScannedCode` — so points, the once-a-day
/// cap and the offer sheet behave the same whichever camera saw the code.
///
/// Presented inside a navigation controller. Phones that can't run the live
/// scanner, or a camera the person has said no to, get "Type a code" instead.
final class RewardScannerViewController: BaseViewController {

    override var loadsDataOnViewDidLoad: Bool { false }
    override var showsLoadingIndicator: Bool { false }

    private var scanner: DataScannerViewController?
    /// Set once a sticker code is found, so a second frame can't send it twice.
    private var handledCode = false
    /// The last non-sticker payload we complained about, so the hint doesn't flicker.
    private var lastRejectedPayload: String?

    private let hintLabel: UILabel = {
        let label = UILabel()
        label.text = "Point your camera at the store's rewards QR code"
        label.font = .systemFont(ofSize: Constants.FontSize.large, weight: .semibold)
        label.textColor = .white
        label.textAlignment = .center
        label.numberOfLines = 0
        label.translatesAutoresizingMaskIntoConstraints = false
        return label
    }()

    private let hintBackground: UIView = {
        let view = UIView()
        view.backgroundColor = UIColor.black.withAlphaComponent(0.55)
        view.layer.cornerRadius = 12
        view.translatesAutoresizingMaskIntoConstraints = false
        return view
    }()

    private let unavailableStack: UIStackView = {
        let stack = UIStackView()
        stack.axis = .vertical
        stack.spacing = Constants.Spacing.medium
        stack.alignment = .fill
        stack.isHidden = true
        stack.translatesAutoresizingMaskIntoConstraints = false
        return stack
    }()

    private let unavailableLabel: UILabel = {
        let label = UILabel()
        label.font = .systemFont(ofSize: Constants.FontSize.large)
        label.textColor = Constants.Colors.label
        label.textAlignment = .center
        label.numberOfLines = 0
        return label
    }()

    private lazy var typeCodeButton: UIButton = {
        let button = UIButton.primaryButton(title: "Type a code")
        button.addTarget(self, action: #selector(typeCodeTapped), for: .touchUpInside)
        return button
    }()

    private lazy var openSettingsButton: UIButton = {
        let button = UIButton.secondaryButton(title: "Open Settings")
        button.addTarget(self, action: #selector(openSettingsTapped), for: .touchUpInside)
        return button
    }()

    override func viewDidLoad() {
        super.viewDidLoad()
        title = "Scan for Rewards"
        view.backgroundColor = .black
        navigationItem.leftBarButtonItem = UIBarButtonItem(barButtonSystemItem: .close, target: self, action: #selector(closeTapped))
        navigationItem.rightBarButtonItem = UIBarButtonItem(title: "Type a code", style: .plain, target: self, action: #selector(typeCodeTapped))

        unavailableStack.addArrangedSubview(unavailableLabel)
        unavailableStack.addArrangedSubview(typeCodeButton)
        unavailableStack.addArrangedSubview(openSettingsButton)
        view.addSubview(unavailableStack)
        NSLayoutConstraint.activate([
            unavailableStack.centerYAnchor.constraint(equalTo: view.safeAreaLayoutGuide.centerYAnchor),
            unavailableStack.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: Constants.Spacing.large),
            unavailableStack.trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: -Constants.Spacing.large)
        ])

        startIfPossible()
    }

    override func viewWillDisappear(_ animated: Bool) {
        super.viewWillDisappear(animated)
        scanner?.stopScanning()
    }

    // MARK: - Camera

    private func startIfPossible() {
        guard DataScannerViewController.isSupported else {
            showUnavailable("This iPhone can't scan codes inside the app. Open the Camera app and point it at the QR code, or type the code instead.", offerSettings: false)
            return
        }
        switch AVCaptureDevice.authorizationStatus(for: .video) {
        case .authorized:
            startScanner()
        case .notDetermined:
            AVCaptureDevice.requestAccess(for: .video) { [weak self] granted in
                DispatchQueue.main.async {
                    granted ? self?.startScanner() : self?.showCameraDenied()
                }
            }
        default:
            showCameraDenied()
        }
    }

    private func showCameraDenied() {
        showUnavailable("FavCircles needs the camera to scan the store's QR code. Turn it on in Settings, or type the code instead.", offerSettings: true)
    }

    private func startScanner() {
        guard DataScannerViewController.isAvailable else {
            showUnavailable("The scanner isn't available right now. Type the code instead.", offerSettings: false)
            return
        }
        let scanner = DataScannerViewController(
            recognizedDataTypes: [.barcode(symbologies: [.qr])],
            qualityLevel: .balanced,
            recognizesMultipleItems: false,
            isHighFrameRateTrackingEnabled: false,
            isHighlightingEnabled: true
        )
        scanner.delegate = self
        addChild(scanner)
        scanner.view.translatesAutoresizingMaskIntoConstraints = false
        view.insertSubview(scanner.view, at: 0)
        NSLayoutConstraint.activate([
            scanner.view.topAnchor.constraint(equalTo: view.topAnchor),
            scanner.view.bottomAnchor.constraint(equalTo: view.bottomAnchor),
            scanner.view.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            scanner.view.trailingAnchor.constraint(equalTo: view.trailingAnchor)
        ])
        scanner.didMove(toParent: self)
        self.scanner = scanner

        view.addSubview(hintBackground)
        hintBackground.addSubview(hintLabel)
        NSLayoutConstraint.activate([
            hintBackground.bottomAnchor.constraint(equalTo: view.safeAreaLayoutGuide.bottomAnchor, constant: -Constants.Spacing.large),
            hintBackground.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: Constants.Spacing.medium),
            hintBackground.trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: -Constants.Spacing.medium),
            hintLabel.topAnchor.constraint(equalTo: hintBackground.topAnchor, constant: Constants.Spacing.small),
            hintLabel.bottomAnchor.constraint(equalTo: hintBackground.bottomAnchor, constant: -Constants.Spacing.small),
            hintLabel.leadingAnchor.constraint(equalTo: hintBackground.leadingAnchor, constant: Constants.Spacing.small),
            hintLabel.trailingAnchor.constraint(equalTo: hintBackground.trailingAnchor, constant: -Constants.Spacing.small)
        ])

        do {
            try scanner.startScanning()
        } catch {
            showUnavailable("The scanner couldn't start. Type the code instead.", offerSettings: false)
        }
    }

    private func showUnavailable(_ message: String, offerSettings: Bool) {
        view.backgroundColor = Constants.Colors.background
        scanner?.view.isHidden = true
        hintBackground.isHidden = true
        unavailableLabel.text = message
        openSettingsButton.isHidden = !offerSettings
        unavailableStack.isHidden = false
        navigationItem.rightBarButtonItem = nil
    }

    // MARK: - Results

    private func handle(payload: String?) {
        guard !handledCode, let payload else { return }
        guard let code = StickerCodeExtractor.code(from: payload) else {
            if payload != lastRejectedPayload {
                lastRejectedPayload = payload
                hintLabel.text = "That's not a FavCircles rewards code. Look for the FavCircles QR at the register."
                UINotificationFeedbackGenerator().notificationOccurred(.warning)
            }
            return
        }
        handledCode = true
        scanner?.stopScanning()
        UINotificationFeedbackGenerator().notificationOccurred(.success)
        // The coordinator presents its result from the top view controller,
        // so leave first and hand over once this screen is gone.
        let host = navigationController ?? self
        host.dismiss(animated: true) {
            StickerRewardCoordinator.shared.handleScannedCode(code)
        }
    }

    // MARK: - Actions

    @objc private func closeTapped() {
        (navigationController ?? self).dismiss(animated: true)
    }

    @objc private func typeCodeTapped() {
        scanner?.stopScanning()
        let host = navigationController ?? self
        guard let presenter = host.presentingViewController else { return }
        host.dismiss(animated: true) {
            StickerRewardCoordinator.shared.promptForCode(from: presenter)
        }
    }

    @objc private func openSettingsTapped() {
        guard let url = URL(string: UIApplication.openSettingsURLString) else { return }
        UIApplication.shared.open(url)
    }
}

extension RewardScannerViewController: DataScannerViewControllerDelegate {
    func dataScanner(_ dataScanner: DataScannerViewController, didAdd addedItems: [RecognizedItem], allItems: [RecognizedItem]) {
        for item in addedItems {
            if case .barcode(let barcode) = item {
                handle(payload: barcode.payloadStringValue)
            }
        }
    }

    func dataScanner(_ dataScanner: DataScannerViewController, didTapOn item: RecognizedItem) {
        if case .barcode(let barcode) = item {
            handle(payload: barcode.payloadStringValue)
        }
    }
}

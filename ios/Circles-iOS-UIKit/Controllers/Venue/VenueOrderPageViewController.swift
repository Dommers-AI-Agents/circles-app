import UIKit

/// The store's website, order.favcircles.com/<slug> (Wes, 2026-10-28 ordering;
/// 2026-11-09 the whole page): photos, about, hours, buttons, what's on, the
/// menu with ordering when it's on, the waitlist when it's on, how to earn
/// here — everything the owner already keeps in Manage Store, on the web for
/// people without the app. Here the owner copies, shares or opens the
/// address, links it from their own site, or changes the slug.
final class VenueOrderPageViewController: BaseViewController {

    override var showsLoadingIndicator: Bool { false }
    override var loadsDataOnViewDidLoad: Bool { false }

    /// The page after the owner changed its address
    var onChanged: ((StorefrontOrderingPage) -> Void)?

    private let venueId: String
    private let venueName: String
    private var page: StorefrontOrderingPage?
    private let orderingOn: Bool

    private let urlLabel = UILabel()
    private let snippetLabel = UILabel()
    private lazy var copyButton = UIButton.primaryButton(title: "Copy link")
    private lazy var shareButton = UIButton.secondaryButton(title: "Share")
    private lazy var openButton = UIButton.secondaryButton(title: "Open the page")
    private lazy var changeButton = UIButton.secondaryButton(title: "Change web address")

    init(venueId: String, venueName: String, page: StorefrontOrderingPage?, orderingOn: Bool) {
        self.venueId = venueId
        self.venueName = venueName
        self.page = page
        self.orderingOn = orderingOn
        super.init(nibName: nil, bundle: nil)
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    override func viewDidLoad() {
        super.viewDidLoad()
        title = "Your website"
        view.backgroundColor = Constants.Colors.background
        let stack = VenueFormLayout.install(in: view)

        stack.addArrangedSubview(VenueFormLayout.hintLabel(
            orderingOn
                ? "Your store's page on the web: photos, hours, what's on, your menu with ordering (paid at pickup, into the same Orders list), your waitlist when it's on, and how to earn rewards here. There's nothing to edit — it shows what you keep in Manage Store."
                : "Your store's page on the web: photos, hours, buttons, what's on, your menu, your waitlist when it's on, and how to earn rewards here. It shows what you keep in Manage Store. Turn on Online ordering and customers order from it too."))

        guard page != nil else {
            stack.addArrangedSubview(VenueFormLayout.hintLabel("Your web address is being set up. Close and reopen Manage Store in a moment."))
            return
        }

        urlLabel.font = .monospacedSystemFont(ofSize: 15, weight: .semibold)
        urlLabel.textColor = Constants.Colors.primary
        urlLabel.numberOfLines = 0
        urlLabel.lineBreakMode = .byCharWrapping
        stack.addArrangedSubview(VenueFormLayout.field("Web address", urlLabel))

        copyButton.addTarget(self, action: #selector(copyTapped), for: .touchUpInside)
        stack.addArrangedSubview(copyButton)
        shareButton.setImage(UIImage(systemName: "square.and.arrow.up"), for: .normal)
        shareButton.addTarget(self, action: #selector(shareTapped), for: .touchUpInside)
        stack.addArrangedSubview(shareButton)
        openButton.setImage(UIImage(systemName: "safari"), for: .normal)
        openButton.addTarget(self, action: #selector(openTapped), for: .touchUpInside)
        stack.addArrangedSubview(openButton)

        snippetLabel.font = .monospacedSystemFont(ofSize: 13, weight: .regular)
        snippetLabel.textColor = Constants.Colors.secondaryLabel
        snippetLabel.numberOfLines = 0
        snippetLabel.lineBreakMode = .byCharWrapping
        stack.addArrangedSubview(VenueFormLayout.field("Add it to your website", snippetLabel,
            hint: VenueFormLayout.hintLabel("Paste the link behind an \u{201C}Order online\u{201D} button or menu item on your site, or into your Instagram and Google Business profiles. The page can't be embedded inside another site; link to it.")))

        stack.addArrangedSubview(VenueFormLayout.hintLabel(
            "Try it: open the page on your phone and place an order with your own number. It arrives in Orders like any other, and you can decline it."))
        changeButton.addTarget(self, action: #selector(changeTapped), for: .touchUpInside)
        stack.addArrangedSubview(changeButton)
        stack.addArrangedSubview(VenueFormLayout.hintLabel("Changing the address keeps the old one working as a redirect, so printed or published links still land."))
        render()
    }

    private func render() {
        guard let page else { return }
        urlLabel.text = page.url
        snippetLabel.text = "<a href=\"\(page.url)\">Order online</a>"
    }

    @objc private func copyTapped() {
        guard let page else { return }
        UIPasteboard.general.string = page.url
        AlertPresenter.showSuccess("Link copied", from: self)
    }

    @objc private func shareTapped() {
        guard let page, let url = URL(string: page.url) else { return }
        let sheet = UIActivityViewController(activityItems: ["Order from \(venueName)", url], applicationActivities: nil)
        sheet.popoverPresentationController?.sourceView = shareButton
        present(sheet, animated: true)
    }

    @objc private func openTapped() {
        guard let page, let url = URL(string: page.url) else { return }
        UIApplication.shared.open(url)
    }

    @objc private func changeTapped() {
        AlertPresenter.showTextInput(
            title: "Web address",
            message: "Letters, numbers and dashes, after \(ShareLinks.orderBase.replacingOccurrences(of: "https://", with: ""))/",
            placeholder: "wooden-robot-brewery",
            initialText: page?.slug,
            confirmTitle: "Save",
            from: self
        ) { [weak self] text in
            guard let self, let slug = text?.trimmingCharacters(in: .whitespacesAndNewlines), !slug.isEmpty, slug != self.page?.slug else { return }
            let loading = AlertPresenter.showLoading(message: "Saving\u{2026}", from: self)
            OrderService.shared.setOrderSlug(venueId: self.venueId, slug: slug) { [weak self] result in
                DispatchQueue.main.async {
                    loading.dismiss(animated: true) {
                        guard let self else { return }
                        switch result {
                        case .success(let fresh):
                            self.page = fresh
                            self.render()
                            self.onChanged?(fresh)
                            AlertPresenter.showSuccess("Your page is now \(fresh.url)", from: self)
                        case .failure(let error):
                            self.showError(error.serverMessage ?? "Couldn\u{2019}t change the address. Try another.")
                        }
                    }
                }
            }
        }
    }
}

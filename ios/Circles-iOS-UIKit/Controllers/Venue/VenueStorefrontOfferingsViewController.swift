import UIKit
import PhotosUI

/// The menu — or services, products, rooms; the title comes from the server
/// by category. Two ways in, because owners already have one of them: a link
/// (their site, a PDF, a delivery page) or photos of the printed menu. Then
/// the part that makes the page look alive: a few featured items with a
/// photo and a price.
final class VenueStorefrontOfferingsViewController: BaseViewController {
    private let venueId: String
    private let label: String
    private var offerings: StorefrontOfferings
    var onSaved: ((VenueStorefront) -> Void)?

    override var loadsDataOnViewDidLoad: Bool { false }
    override var showsLoadingIndicator: Bool { false }

    private enum Section: Int, CaseIterable { case link, files, featured }
    private let tableView = UITableView(frame: .zero, style: .insetGrouped)
    /// Which list the next picked photo belongs to.
    private enum PickTarget { case menuPhoto, featuredPhoto(index: Int) }
    private var pickTarget: PickTarget = .menuPhoto

    init(venueId: String, label: String, offerings: StorefrontOfferings?) {
        self.venueId = venueId
        self.label = label
        self.offerings = offerings ?? StorefrontOfferings()
        super.init(nibName: nil, bundle: nil)
        title = label
    }
    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    override func viewDidLoad() {
        super.viewDidLoad()
        view.backgroundColor = Constants.Colors.background
        navigationItem.rightBarButtonItem = UIBarButtonItem(title: "Save", style: .done, target: self, action: #selector(saveTapped))
        tableView.translatesAutoresizingMaskIntoConstraints = false
        tableView.dataSource = self
        tableView.delegate = self
        tableView.register(UITableViewCell.self, forCellReuseIdentifier: "Cell")
        view.addSubview(tableView)
        NSLayoutConstraint.activate([
            tableView.topAnchor.constraint(equalTo: view.safeAreaLayoutGuide.topAnchor),
            tableView.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            tableView.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            tableView.bottomAnchor.constraint(equalTo: view.bottomAnchor)
        ])
    }

    // MARK: - Save

    @objc private func saveTapped() {
        navigationItem.rightBarButtonItem?.isEnabled = false
        RewardsService.shared.updateStorefrontOfferings(venueId: venueId, offerings: offerings) { [weak self] result in
            DispatchQueue.main.async {
                guard let self else { return }
                self.navigationItem.rightBarButtonItem?.isEnabled = true
                switch result {
                case .success(let storefront):
                    self.offerings = storefront.offerings ?? StorefrontOfferings()
                    self.onSaved?(storefront)
                    self.showSuccess("\(self.label) saved")
                case .failure(let error):
                    self.showError(error)
                }
            }
        }
    }

    // MARK: - Edits

    private func editLink() {
        showTextInput(title: "\(label) link", message: "Your website, a PDF, or a delivery page.",
                      placeholder: "https://…", initialText: offerings.link, keyboardType: .URL) { [weak self] text in
            guard let self else { return }
            var s = (text ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
            if !s.isEmpty, !s.lowercased().hasPrefix("http") { s = "https://" + s }
            self.offerings.link = s.isEmpty ? nil : s
            self.tableView.reloadSections([Section.link.rawValue], with: .automatic)
        }
    }

    private func addFeaturedItem() {
        showTextInput(title: "Featured item", placeholder: "Name, e.g. Cacio e Pepe") { [weak self] name in
            guard let self, let name = name?.trimmingCharacters(in: .whitespacesAndNewlines), !name.isEmpty else { return }
            guard self.offerings.featured.count < 8 else { self.showError("Up to 8 featured items."); return }
            self.showTextInput(title: "Price", message: "Optional", placeholder: "$18", keyboardType: .numbersAndPunctuation) { price in
                let p = price?.trimmingCharacters(in: .whitespacesAndNewlines)
                self.offerings.featured.append(StorefrontFeaturedItem(name: name, price: (p ?? "").isEmpty ? nil : p))
                self.tableView.reloadSections([Section.featured.rawValue], with: .automatic)
                // Straight into the photo, because an item without one is the
                // one nobody taps.
                self.pickPhoto(for: .featuredPhoto(index: self.offerings.featured.count - 1))
            }
        }
    }

    private func manageFeatured(at index: Int) {
        let item = offerings.featured[index]
        AlertPresenter.showActionSheet(title: item.name, message: nil, actions: [
            (title: item.photoUrl == nil ? "Add photo" : "Change photo", style: .default, handler: { [weak self] in
                self?.pickPhoto(for: .featuredPhoto(index: index))
            }),
            (title: "Edit name", style: .default, handler: { [weak self] in
                self?.showTextInput(title: "Name", initialText: item.name) { text in
                    guard let t = text?.trimmingCharacters(in: .whitespacesAndNewlines), !t.isEmpty else { return }
                    self?.offerings.featured[index].name = t
                    self?.tableView.reloadData()
                }
            }),
            (title: "Edit price", style: .default, handler: { [weak self] in
                self?.showTextInput(title: "Price", initialText: item.price, keyboardType: .numbersAndPunctuation) { text in
                    let t = text?.trimmingCharacters(in: .whitespacesAndNewlines)
                    self?.offerings.featured[index].price = (t ?? "").isEmpty ? nil : t
                    self?.tableView.reloadData()
                }
            }),
            (title: "Edit description", style: .default, handler: { [weak self] in
                self?.showTextInput(title: "Description", message: "One line. What's in it, why it's good.", initialText: item.description) { text in
                    let t = text?.trimmingCharacters(in: .whitespacesAndNewlines)
                    self?.offerings.featured[index].description = (t ?? "").isEmpty ? nil : t
                    self?.tableView.reloadData()
                }
            }),
            (title: "Tags", style: .default, handler: { [weak self] in
                self?.showTextInput(title: "Tags", message: "Up to three, comma-separated — Popular, Gluten-free, Spicy",
                                    initialText: item.tags.joined(separator: ", ")) { text in
                    let tags = (text ?? "").split(separator: ",").map { $0.trimmingCharacters(in: .whitespaces) }.filter { !$0.isEmpty }
                    self?.offerings.featured[index].tags = Array(tags.prefix(3))
                    self?.tableView.reloadData()
                }
            }),
            (title: "Remove", style: .destructive, handler: { [weak self] in
                self?.offerings.featured.remove(at: index)
                self?.tableView.reloadData()
            })
        ], from: self)
    }

    private func manageFile(at index: Int) {
        let file = offerings.files[index]
        AlertPresenter.showActionSheet(title: file.label ?? "Menu photo", message: nil, actions: [
            (title: "Label", style: .default, handler: { [weak self] in
                self?.showTextInput(title: "Label", message: "Dinner, Brunch, Wine list…", initialText: file.label) { text in
                    let t = text?.trimmingCharacters(in: .whitespacesAndNewlines)
                    self?.offerings.files[index].label = (t ?? "").isEmpty ? nil : t
                    self?.tableView.reloadData()
                }
            }),
            (title: "Remove", style: .destructive, handler: { [weak self] in
                self?.offerings.files.remove(at: index)
                self?.tableView.reloadData()
            })
        ], from: self)
    }

    // MARK: - Photos

    private func pickPhoto(for target: PickTarget) {
        pickTarget = target
        var config = PHPickerConfiguration()
        config.filter = .images
        config.selectionLimit = 1
        let picker = PHPickerViewController(configuration: config)
        picker.delegate = self
        present(picker, animated: true)
    }

    private func upload(_ image: UIImage) {
        guard let data = image.jpegData(compressionQuality: 0.85) else { return }
        let loading = showLoading(message: "Uploading…")
        PlaceService.shared.uploadImage(data) { [weak self] result in
            DispatchQueue.main.async {
                loading.dismiss(animated: true) {
                    guard let self else { return }
                    switch result {
                    case .success(let url):
                        switch self.pickTarget {
                        case .menuPhoto:
                            guard self.offerings.files.count < 6 else { self.showError("Up to 6 menu photos."); return }
                            self.offerings.files.append(StorefrontFile(url: url, kind: "image", label: nil))
                        case .featuredPhoto(let index):
                            guard self.offerings.featured.indices.contains(index) else { return }
                            self.offerings.featured[index].photoUrl = url
                        }
                        self.tableView.reloadData()
                    case .failure(let error):
                        self.showError(error)
                    }
                }
            }
        }
    }
}

// MARK: - Table

extension VenueStorefrontOfferingsViewController: UITableViewDataSource, UITableViewDelegate {
    func numberOfSections(in tableView: UITableView) -> Int { Section.allCases.count }

    func tableView(_ tableView: UITableView, numberOfRowsInSection section: Int) -> Int {
        switch Section(rawValue: section)! {
        case .link: return 1
        case .files: return offerings.files.count + 1
        case .featured: return offerings.featured.count + 1
        }
    }

    func tableView(_ tableView: UITableView, titleForHeaderInSection section: Int) -> String? {
        switch Section(rawValue: section)! {
        case .link: return "Link"
        case .files: return "Photos of your \(label.lowercased())"
        case .featured: return "Featured items"
        }
    }

    func tableView(_ tableView: UITableView, titleForFooterInSection section: Int) -> String? {
        switch Section(rawValue: section)! {
        case .link: return "Opens in the app. A PDF or your website both work."
        case .files: return "Photograph the printed \(label.lowercased()) — up to six pages."
        case .featured: return "Up to eight. A photo and a price is what gets tapped."
        }
    }

    func tableView(_ tableView: UITableView, cellForRowAt indexPath: IndexPath) -> UITableViewCell {
        let cell = tableView.dequeueReusableCell(withIdentifier: "Cell", for: indexPath)
        var config = cell.defaultContentConfiguration()
        cell.accessoryType = .none
        cell.accessoryView = nil
        config.imageProperties.tintColor = Constants.Colors.primary
        config.secondaryTextProperties.color = .secondaryLabel
        config.secondaryTextProperties.font = .systemFont(ofSize: 12)
        switch Section(rawValue: indexPath.section)! {
        case .link:
            config.image = UIImage(systemName: "link")
            config.text = offerings.link ?? "Add a link"
            config.secondaryText = offerings.link == nil ? "Website, PDF or ordering page" : "Tap to change"
            cell.accessoryType = .disclosureIndicator
        case .files:
            if indexPath.row < offerings.files.count {
                let file = offerings.files[indexPath.row]
                config.image = UIImage(systemName: file.kind == "pdf" ? "doc.fill" : "photo")
                config.text = file.label ?? "Page \(indexPath.row + 1)"
                config.secondaryText = "Tap to label or remove"
                loadThumb(file.url, into: cell)
            } else {
                config.image = UIImage(systemName: "plus.circle.fill")
                config.text = "Add a photo"
            }
        case .featured:
            if indexPath.row < offerings.featured.count {
                let item = offerings.featured[indexPath.row]
                config.image = UIImage(systemName: item.photoUrl == nil ? "photo.badge.plus" : "photo")
                config.text = [item.name, item.price].compactMap { $0 }.joined(separator: " · ")
                var secondary: [String] = []
                if let d = item.description, !d.isEmpty { secondary.append(d) }
                if !item.tags.isEmpty { secondary.append(item.tags.joined(separator: " · ")) }
                if item.photoUrl == nil { secondary.append("No photo yet") }
                config.secondaryText = secondary.joined(separator: "\n")
                if let url = item.photoUrl { loadThumb(url, into: cell) }
            } else {
                config.image = UIImage(systemName: "plus.circle.fill")
                config.text = "Add a featured item"
            }
        }
        cell.contentConfiguration = config
        return cell
    }

    private func loadThumb(_ url: String, into cell: UITableViewCell) {
        ImageService.shared.loadImage(from: url) { image in
            DispatchQueue.main.async {
                guard let image else { return }
                let iv = UIImageView(image: image)
                iv.contentMode = .scaleAspectFill
                iv.clipsToBounds = true
                iv.layer.cornerRadius = 6
                iv.frame = CGRect(x: 0, y: 0, width: 44, height: 44)
                cell.accessoryView = iv
            }
        }
    }

    func tableView(_ tableView: UITableView, didSelectRowAt indexPath: IndexPath) {
        tableView.deselectRow(at: indexPath, animated: true)
        switch Section(rawValue: indexPath.section)! {
        case .link: editLink()
        case .files:
            if indexPath.row < offerings.files.count { manageFile(at: indexPath.row) } else { pickPhoto(for: .menuPhoto) }
        case .featured:
            if indexPath.row < offerings.featured.count { manageFeatured(at: indexPath.row) } else { addFeaturedItem() }
        }
    }
}

extension VenueStorefrontOfferingsViewController: PHPickerViewControllerDelegate {
    func picker(_ picker: PHPickerViewController, didFinishPicking results: [PHPickerResult]) {
        picker.dismiss(animated: true)
        guard let provider = results.first?.itemProvider, provider.canLoadObject(ofClass: UIImage.self) else { return }
        provider.loadObject(ofClass: UIImage.self) { [weak self] object, _ in
            guard let image = object as? UIImage else { return }
            DispatchQueue.main.async { self?.upload(image) }
        }
    }
}

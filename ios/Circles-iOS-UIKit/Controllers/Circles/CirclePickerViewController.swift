import UIKit

class CirclePickerViewController: UIViewController {
    
    // MARK: - Properties
    private let circles: [Circle]
    private var filteredCircles: [Circle]
    var onCircleSelected: ((Circle) -> Void)?
    var onCreateNewCircle: (() -> Void)?
    /// Sheet title; callers adding a specific place can say so.
    var pickerTitle = "Select Circle"
    /// When set, a card above the list shows the place being added
    /// (name + address), so the sheet says what it's for.
    var placeName: String?
    var placeAddress: String?

    // MARK: - UI Elements
    private lazy var searchController: UISearchController = {
        let searchController = UISearchController(searchResultsController: nil)
        searchController.searchResultsUpdater = self
        searchController.obscuresBackgroundDuringPresentation = false
        searchController.searchBar.placeholder = "Search circles..."
        return searchController
    }()

    private let tableView: UITableView = {
        let tableView = UITableView()
        tableView.backgroundColor = Constants.Colors.background
        tableView.separatorStyle = .none
        tableView.translatesAutoresizingMaskIntoConstraints = false
        return tableView
    }()
    
    private let createNewButton: UIButton = {
        let button = UIButton(type: .system)
        button.setTitle("+ Create New Circle", for: .normal)
        button.setTitleColor(Constants.Colors.primary, for: .normal)
        button.titleLabel?.font = UIFont.systemFont(ofSize: 16, weight: .semibold)
        button.backgroundColor = Constants.Colors.primary.withAlphaComponent(0.1)
        button.layer.cornerRadius = 12
        button.translatesAutoresizingMaskIntoConstraints = false
        return button
    }()
    
    // MARK: - Initialization
    init(circles: [Circle]) {
        self.circles = circles
        self.filteredCircles = circles
        super.init(nibName: nil, bundle: nil)
    }
    
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }
    
    // MARK: - Lifecycle
    override func viewDidLoad() {
        super.viewDidLoad()
        setupUI()
        setupTableView()
    }
    
    // MARK: - UI Setup
    private func setupUI() {
        view.backgroundColor = Constants.Colors.background
        title = pickerTitle
        
        // Add cancel button
        navigationItem.leftBarButtonItem = UIBarButtonItem(
            barButtonSystemItem: .cancel,
            target: self,
            action: #selector(cancelButtonTapped)
        )

        // Always-visible search bar under the title
        navigationItem.searchController = searchController
        navigationItem.hidesSearchBarWhenScrolling = false
        definesPresentationContext = true
        
        // Add subviews
        view.addSubview(tableView)
        view.addSubview(createNewButton)
        
        // Setup constraints
        NSLayoutConstraint.activate([
            tableView.topAnchor.constraint(equalTo: view.safeAreaLayoutGuide.topAnchor),
            tableView.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            tableView.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            tableView.bottomAnchor.constraint(equalTo: createNewButton.topAnchor, constant: -Constants.Spacing.medium),
            
            createNewButton.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: Constants.Spacing.medium),
            createNewButton.trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: -Constants.Spacing.medium),
            createNewButton.bottomAnchor.constraint(equalTo: view.safeAreaLayoutGuide.bottomAnchor, constant: -Constants.Spacing.medium),
            createNewButton.heightAnchor.constraint(equalToConstant: 50)
        ])
        
        // Add target for create button
        createNewButton.addTarget(self, action: #selector(createNewButtonTapped), for: .touchUpInside)
    }
    
    private func setupTableView() {
        tableView.delegate = self
        tableView.dataSource = self
        tableView.register(CirclePickerCell.self, forCellReuseIdentifier: "CirclePickerCell")
        tableView.contentInset = UIEdgeInsets(top: Constants.Spacing.small, left: 0, bottom: Constants.Spacing.small, right: 0)
        tableView.tableHeaderView = makePlaceHeader()
    }

    /// "📍 Ilios Crafted Greek / 123 Main St · Choose a circle for it."
    private func makePlaceHeader() -> UIView? {
        guard let name = placeName, !name.isEmpty else { return nil }
        let icon = UIImageView(image: UIImage(systemName: "mappin.circle.fill"))
        icon.tintColor = Constants.Colors.primary
        icon.contentMode = .scaleAspectFit
        icon.translatesAutoresizingMaskIntoConstraints = false

        let nameLabel = UILabel()
        nameLabel.text = name
        nameLabel.font = .systemFont(ofSize: 20, weight: .bold)
        nameLabel.textColor = Constants.Colors.label
        nameLabel.numberOfLines = 2

        let addressLabel = UILabel()
        addressLabel.text = placeAddress
        addressLabel.font = .systemFont(ofSize: 14)
        addressLabel.textColor = Constants.Colors.secondaryLabel
        addressLabel.numberOfLines = 2
        addressLabel.isHidden = (placeAddress ?? "").isEmpty

        let promptLabel = UILabel()
        promptLabel.text = "Choose a circle to save it to"
        promptLabel.font = .systemFont(ofSize: 13, weight: .semibold)
        promptLabel.textColor = Constants.Colors.secondaryLabel

        let textStack = UIStackView(arrangedSubviews: [nameLabel, addressLabel])
        textStack.axis = .vertical
        textStack.spacing = 2

        let row = UIStackView(arrangedSubviews: [icon, textStack])
        row.axis = .horizontal
        row.spacing = 12
        row.alignment = .center

        let stack = UIStackView(arrangedSubviews: [row, promptLabel])
        stack.axis = .vertical
        stack.spacing = Constants.Spacing.medium
        stack.translatesAutoresizingMaskIntoConstraints = false

        let header = UIView()
        header.addSubview(stack)
        NSLayoutConstraint.activate([
            icon.widthAnchor.constraint(equalToConstant: 40),
            icon.heightAnchor.constraint(equalToConstant: 40),
            stack.topAnchor.constraint(equalTo: header.topAnchor, constant: Constants.Spacing.small),
            stack.leadingAnchor.constraint(equalTo: header.leadingAnchor, constant: Constants.Spacing.medium + 4),
            stack.trailingAnchor.constraint(equalTo: header.trailingAnchor, constant: -Constants.Spacing.medium),
            stack.bottomAnchor.constraint(equalTo: header.bottomAnchor, constant: -Constants.Spacing.small)
        ])
        let width = view.bounds.width
        let size = header.systemLayoutSizeFitting(
            CGSize(width: width, height: UIView.layoutFittingCompressedSize.height),
            withHorizontalFittingPriority: .required,
            verticalFittingPriority: .fittingSizeLevel
        )
        header.frame = CGRect(x: 0, y: 0, width: width, height: size.height)
        return header
    }
    
    // MARK: - Actions
    @objc private func cancelButtonTapped() {
        searchController.isActive = false
        dismiss(animated: true)
    }

    @objc private func createNewButtonTapped() {
        searchController.isActive = false
        dismiss(animated: true) { [weak self] in
            self?.onCreateNewCircle?()
        }
    }
}

// MARK: - UITableViewDataSource
extension CirclePickerViewController: UITableViewDataSource {
    func tableView(_ tableView: UITableView, numberOfRowsInSection section: Int) -> Int {
        return filteredCircles.count
    }

    func tableView(_ tableView: UITableView, cellForRowAt indexPath: IndexPath) -> UITableViewCell {
        let cell = tableView.dequeueReusableCell(withIdentifier: "CirclePickerCell", for: indexPath) as! CirclePickerCell
        let circle = filteredCircles[indexPath.row]
        cell.configure(with: circle)
        return cell
    }
}

// MARK: - UISearchResultsUpdating
extension CirclePickerViewController: UISearchResultsUpdating {
    func updateSearchResults(for searchController: UISearchController) {
        let searchText = searchController.searchBar.text ?? ""
        if searchText.isEmpty {
            filteredCircles = circles
        } else {
            filteredCircles = circles.filter { $0.name.localizedCaseInsensitiveContains(searchText) }
        }
        tableView.reloadData()
    }
}

// MARK: - UITableViewDelegate
extension CirclePickerViewController: UITableViewDelegate {
    func tableView(_ tableView: UITableView, didSelectRowAt indexPath: IndexPath) {
        tableView.deselectRow(at: indexPath, animated: true)
        guard indexPath.row < filteredCircles.count else { return }
        let circle = filteredCircles[indexPath.row]
        // Dismissing while the search controller is active first tears down the
        // search presentation, which would swallow the sheet dismissal
        searchController.isActive = false
        dismiss(animated: true) { [weak self] in
            self?.onCircleSelected?(circle)
        }
    }
    
    func tableView(_ tableView: UITableView, heightForRowAt indexPath: IndexPath) -> CGFloat {
        return 80
    }
}

// MARK: - CirclePickerCell
class CirclePickerCell: UITableViewCell {
    
    // MARK: - UI Elements
    private let containerView: UIView = {
        let view = UIView()
        view.backgroundColor = Constants.Colors.secondaryBackground
        view.layer.cornerRadius = 12
        view.translatesAutoresizingMaskIntoConstraints = false
        return view
    }()
    
    private let iconImageView: UIImageView = {
        let imageView = UIImageView()
        imageView.contentMode = .scaleAspectFill
        imageView.clipsToBounds = true
        imageView.layer.cornerRadius = 25
        imageView.backgroundColor = Constants.Colors.tertiaryBackground
        imageView.translatesAutoresizingMaskIntoConstraints = false
        return imageView
    }()
    
    private let nameLabel: UILabel = {
        let label = UILabel()
        label.font = UIFont.systemFont(ofSize: 16, weight: .semibold)
        label.textColor = Constants.Colors.label
        label.translatesAutoresizingMaskIntoConstraints = false
        return label
    }()
    
    private let detailLabel: UILabel = {
        let label = UILabel()
        label.font = UIFont.systemFont(ofSize: 14)
        label.textColor = Constants.Colors.secondaryLabel
        label.translatesAutoresizingMaskIntoConstraints = false
        return label
    }()
    
    private let chevronImageView: UIImageView = {
        let imageView = UIImageView()
        imageView.image = UIImage(systemName: "chevron.right")
        imageView.tintColor = Constants.Colors.tertiaryLabel
        imageView.contentMode = .scaleAspectFit
        imageView.translatesAutoresizingMaskIntoConstraints = false
        return imageView
    }()
    
    // MARK: - Initialization
    override init(style: UITableViewCell.CellStyle, reuseIdentifier: String?) {
        super.init(style: style, reuseIdentifier: reuseIdentifier)
        setupUI()
    }
    
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }
    
    // MARK: - UI Setup
    private func setupUI() {
        backgroundColor = .clear
        selectionStyle = .none
        
        contentView.addSubview(containerView)
        containerView.addSubview(iconImageView)
        containerView.addSubview(nameLabel)
        containerView.addSubview(detailLabel)
        containerView.addSubview(chevronImageView)
        
        NSLayoutConstraint.activate([
            containerView.topAnchor.constraint(equalTo: contentView.topAnchor, constant: Constants.Spacing.xsmall),
            containerView.leadingAnchor.constraint(equalTo: contentView.leadingAnchor, constant: Constants.Spacing.medium),
            containerView.trailingAnchor.constraint(equalTo: contentView.trailingAnchor, constant: -Constants.Spacing.medium),
            containerView.bottomAnchor.constraint(equalTo: contentView.bottomAnchor, constant: -Constants.Spacing.xsmall),
            
            iconImageView.leadingAnchor.constraint(equalTo: containerView.leadingAnchor, constant: Constants.Spacing.medium),
            iconImageView.centerYAnchor.constraint(equalTo: containerView.centerYAnchor),
            iconImageView.widthAnchor.constraint(equalToConstant: 50),
            iconImageView.heightAnchor.constraint(equalToConstant: 50),
            
            nameLabel.topAnchor.constraint(equalTo: containerView.topAnchor, constant: Constants.Spacing.medium),
            nameLabel.leadingAnchor.constraint(equalTo: iconImageView.trailingAnchor, constant: Constants.Spacing.medium),
            nameLabel.trailingAnchor.constraint(equalTo: chevronImageView.leadingAnchor, constant: -Constants.Spacing.medium),
            
            detailLabel.topAnchor.constraint(equalTo: nameLabel.bottomAnchor, constant: 4),
            detailLabel.leadingAnchor.constraint(equalTo: nameLabel.leadingAnchor),
            detailLabel.trailingAnchor.constraint(equalTo: nameLabel.trailingAnchor),
            detailLabel.bottomAnchor.constraint(lessThanOrEqualTo: containerView.bottomAnchor, constant: -Constants.Spacing.medium),
            
            chevronImageView.centerYAnchor.constraint(equalTo: containerView.centerYAnchor),
            chevronImageView.trailingAnchor.constraint(equalTo: containerView.trailingAnchor, constant: -Constants.Spacing.medium),
            chevronImageView.widthAnchor.constraint(equalToConstant: 12),
            chevronImageView.heightAnchor.constraint(equalToConstant: 20)
        ])
    }
    
    // MARK: - Configuration
    func configure(with circle: Circle) {
        nameLabel.text = circle.name
        
        // Set detail text with place count
        // The circle list sends placesCount, not the ids, so prefer it
        let placeCount = circle.placesCount ?? circle.places?.count ?? 0
        detailLabel.text = "\(placeCount) place\(placeCount == 1 ? "" : "s")"
        
        // Load circle image
        if let coverImage = circle.coverImage {
            ImageService.shared.loadImage(from: coverImage) { [weak self] image in
                DispatchQueue.main.async {
                    self?.iconImageView.image = image
                }
            }
        } else {
            // Set default icon based on category
            iconImageView.image = UIImage(systemName: "circle.fill")
            iconImageView.tintColor = Constants.Colors.primary
        }
    }
    
    // MARK: - Selection Animation
    override func setHighlighted(_ highlighted: Bool, animated: Bool) {
        super.setHighlighted(highlighted, animated: animated)
        
        UIView.animate(withDuration: 0.1) {
            self.containerView.backgroundColor = highlighted ? 
                Constants.Colors.tertiaryBackground : Constants.Colors.secondaryBackground
            self.containerView.transform = highlighted ? 
                CGAffineTransform(scaleX: 0.98, y: 0.98) : .identity
        }
    }
}
import UIKit

class DataExportViewController: BaseViewController {
    
    // MARK: - Properties
    private var selectedExportType: CSVExportService.ExportType = .all
    private var exportedFileURL: URL?
    
    // MARK: - UI Elements
    private let scrollView: UIScrollView = {
        let scrollView = UIScrollView()
        scrollView.translatesAutoresizingMaskIntoConstraints = false
        scrollView.showsVerticalScrollIndicator = false
        return scrollView
    }()
    
    private let contentView: UIView = {
        let view = UIView()
        view.translatesAutoresizingMaskIntoConstraints = false
        return view
    }()
    
    private let iconImageView: UIImageView = {
        let imageView = UIImageView()
        let config = UIImage.SymbolConfiguration(pointSize: 60, weight: .medium)
        imageView.image = UIImage(systemName: "square.and.arrow.down.fill", withConfiguration: config)
        imageView.tintColor = Constants.Colors.primary
        imageView.contentMode = .scaleAspectFit
        imageView.translatesAutoresizingMaskIntoConstraints = false
        return imageView
    }()
    
    private let titleLabel: UILabel = {
        let label = UILabel()
        label.text = "Export Your Data"
        label.font = UIFont.systemFont(ofSize: 24, weight: .bold)
        label.textColor = Constants.Colors.label
        label.textAlignment = .center
        label.translatesAutoresizingMaskIntoConstraints = false
        return label
    }()
    
    private let descriptionLabel: UILabel = {
        let label = UILabel()
        label.text = "Download all your circles and places as a CSV file that you can open in Excel, Google Sheets, or any spreadsheet application."
        label.font = UIFont.systemFont(ofSize: 15)
        label.textColor = Constants.Colors.secondaryLabel
        label.textAlignment = .center
        label.numberOfLines = 0
        label.translatesAutoresizingMaskIntoConstraints = false
        return label
    }()
    
    // Export type selection
    private let exportTypeLabel: UILabel = {
        let label = UILabel()
        label.text = "What to Export"
        label.font = UIFont.systemFont(ofSize: 16, weight: .semibold)
        label.textColor = Constants.Colors.label
        label.translatesAutoresizingMaskIntoConstraints = false
        return label
    }()
    
    private let exportTypeStackView: UIStackView = {
        let stack = UIStackView()
        stack.axis = .vertical
        stack.spacing = 12
        stack.translatesAutoresizingMaskIntoConstraints = false
        return stack
    }()
    
    // Info section
    private let infoContainer: UIView = {
        let view = UIView()
        view.backgroundColor = Constants.Colors.secondaryBackground
        view.layer.cornerRadius = 12
        view.translatesAutoresizingMaskIntoConstraints = false
        return view
    }()
    
    private let infoLabel: UILabel = {
        let label = UILabel()
        label.text = "ℹ️ Your export will include:\n• All your circles and their details\n• All places you've added\n• Your personal notes (private notes)\n• Ratings and tags"
        label.font = UIFont.systemFont(ofSize: 14)
        label.textColor = Constants.Colors.secondaryLabel
        label.numberOfLines = 0
        label.translatesAutoresizingMaskIntoConstraints = false
        return label
    }()
    
    // Export button
    private lazy var exportButton = UIButton.primaryButton(title: "Export Data")
    
    // Progress view
    private let progressContainer: UIView = {
        let view = UIView()
        view.isHidden = true
        view.translatesAutoresizingMaskIntoConstraints = false
        return view
    }()
    
    private let progressIndicator: UIActivityIndicatorView = {
        let indicator = UIActivityIndicatorView(style: .large)
        indicator.hidesWhenStopped = true
        indicator.translatesAutoresizingMaskIntoConstraints = false
        return indicator
    }()
    
    private let progressLabel: UILabel = {
        let label = UILabel()
        label.text = "Preparing your export..."
        label.font = UIFont.systemFont(ofSize: 14)
        label.textColor = Constants.Colors.secondaryLabel
        label.textAlignment = .center
        label.translatesAutoresizingMaskIntoConstraints = false
        return label
    }()
    
    // MARK: - Lifecycle
    override func viewDidLoad() {
        super.viewDidLoad()
        setupUI()
        setupConstraints()
        setupExportTypeOptions()
    }
    
    // MARK: - Setup
    private func setupUI() {
        title = "Export Data"
        navigationItem.leftBarButtonItem = UIBarButtonItem(
            barButtonSystemItem: .cancel,
            target: self,
            action: #selector(cancelTapped)
        )
        
        view.backgroundColor = Constants.Colors.background
        
        // Add views
        view.addSubview(scrollView)
        scrollView.addSubview(contentView)
        
        contentView.addSubview(iconImageView)
        contentView.addSubview(titleLabel)
        contentView.addSubview(descriptionLabel)
        contentView.addSubview(exportTypeLabel)
        contentView.addSubview(exportTypeStackView)
        contentView.addSubview(infoContainer)
        infoContainer.addSubview(infoLabel)
        contentView.addSubview(exportButton)
        contentView.addSubview(progressContainer)
        progressContainer.addSubview(progressIndicator)
        progressContainer.addSubview(progressLabel)
        
        // Add action
        exportButton.addTarget(self, action: #selector(exportTapped), for: .touchUpInside)
    }
    
    private func setupConstraints() {
        NSLayoutConstraint.activate([
            // Scroll view
            scrollView.topAnchor.constraint(equalTo: view.safeAreaLayoutGuide.topAnchor),
            scrollView.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            scrollView.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            scrollView.bottomAnchor.constraint(equalTo: view.bottomAnchor),
            
            // Content view
            contentView.topAnchor.constraint(equalTo: scrollView.topAnchor),
            contentView.leadingAnchor.constraint(equalTo: scrollView.leadingAnchor),
            contentView.trailingAnchor.constraint(equalTo: scrollView.trailingAnchor),
            contentView.bottomAnchor.constraint(equalTo: scrollView.bottomAnchor),
            contentView.widthAnchor.constraint(equalTo: scrollView.widthAnchor),
            
            // Icon
            iconImageView.topAnchor.constraint(equalTo: contentView.topAnchor, constant: 40),
            iconImageView.centerXAnchor.constraint(equalTo: contentView.centerXAnchor),
            iconImageView.widthAnchor.constraint(equalToConstant: 80),
            iconImageView.heightAnchor.constraint(equalToConstant: 80),
            
            // Title
            titleLabel.topAnchor.constraint(equalTo: iconImageView.bottomAnchor, constant: 20),
            titleLabel.leadingAnchor.constraint(equalTo: contentView.leadingAnchor, constant: 32),
            titleLabel.trailingAnchor.constraint(equalTo: contentView.trailingAnchor, constant: -32),
            
            // Description
            descriptionLabel.topAnchor.constraint(equalTo: titleLabel.bottomAnchor, constant: 12),
            descriptionLabel.leadingAnchor.constraint(equalTo: contentView.leadingAnchor, constant: 32),
            descriptionLabel.trailingAnchor.constraint(equalTo: contentView.trailingAnchor, constant: -32),
            
            // Export type label
            exportTypeLabel.topAnchor.constraint(equalTo: descriptionLabel.bottomAnchor, constant: 32),
            exportTypeLabel.leadingAnchor.constraint(equalTo: contentView.leadingAnchor, constant: 24),
            exportTypeLabel.trailingAnchor.constraint(equalTo: contentView.trailingAnchor, constant: -24),
            
            // Export type options
            exportTypeStackView.topAnchor.constraint(equalTo: exportTypeLabel.bottomAnchor, constant: 12),
            exportTypeStackView.leadingAnchor.constraint(equalTo: contentView.leadingAnchor, constant: 24),
            exportTypeStackView.trailingAnchor.constraint(equalTo: contentView.trailingAnchor, constant: -24),
            
            // Info container
            infoContainer.topAnchor.constraint(equalTo: exportTypeStackView.bottomAnchor, constant: 24),
            infoContainer.leadingAnchor.constraint(equalTo: contentView.leadingAnchor, constant: 24),
            infoContainer.trailingAnchor.constraint(equalTo: contentView.trailingAnchor, constant: -24),
            
            // Info label
            infoLabel.topAnchor.constraint(equalTo: infoContainer.topAnchor, constant: 16),
            infoLabel.leadingAnchor.constraint(equalTo: infoContainer.leadingAnchor, constant: 16),
            infoLabel.trailingAnchor.constraint(equalTo: infoContainer.trailingAnchor, constant: -16),
            infoLabel.bottomAnchor.constraint(equalTo: infoContainer.bottomAnchor, constant: -16),
            
            // Export button
            exportButton.topAnchor.constraint(equalTo: infoContainer.bottomAnchor, constant: 32),
            exportButton.leadingAnchor.constraint(equalTo: contentView.leadingAnchor, constant: 24),
            exportButton.trailingAnchor.constraint(equalTo: contentView.trailingAnchor, constant: -24),
            
            // Progress container
            progressContainer.topAnchor.constraint(equalTo: exportButton.bottomAnchor, constant: 24),
            progressContainer.leadingAnchor.constraint(equalTo: contentView.leadingAnchor, constant: 24),
            progressContainer.trailingAnchor.constraint(equalTo: contentView.trailingAnchor, constant: -24),
            progressContainer.bottomAnchor.constraint(equalTo: contentView.bottomAnchor, constant: -32),
            
            // Progress indicator
            progressIndicator.topAnchor.constraint(equalTo: progressContainer.topAnchor),
            progressIndicator.centerXAnchor.constraint(equalTo: progressContainer.centerXAnchor),
            
            // Progress label
            progressLabel.topAnchor.constraint(equalTo: progressIndicator.bottomAnchor, constant: 12),
            progressLabel.leadingAnchor.constraint(equalTo: progressContainer.leadingAnchor),
            progressLabel.trailingAnchor.constraint(equalTo: progressContainer.trailingAnchor),
            progressLabel.bottomAnchor.constraint(equalTo: progressContainer.bottomAnchor)
        ])
    }
    
    private func setupExportTypeOptions() {
        let options: [(title: String, subtitle: String, type: CSVExportService.ExportType)] = [
            ("Everything", "Export all circles and places", .all),
            ("Circles Only", "Export only your circle information", .circlesOnly),
            ("Places Only", "Export only your places", .placesOnly)
        ]
        
        for (index, option) in options.enumerated() {
            let optionView = createExportOption(
                title: option.title,
                subtitle: option.subtitle,
                tag: index,
                isSelected: index == 0
            )
            exportTypeStackView.addArrangedSubview(optionView)
        }
    }
    
    private func createExportOption(title: String, subtitle: String, tag: Int, isSelected: Bool) -> UIView {
        let container = UIView()
        container.backgroundColor = isSelected ? Constants.Colors.primary.withAlphaComponent(0.1) : Constants.Colors.secondaryBackground
        container.layer.cornerRadius = 12
        container.layer.borderWidth = isSelected ? 2 : 1
        container.layer.borderColor = isSelected ? Constants.Colors.primary.cgColor : Constants.Colors.separator.cgColor
        container.tag = tag
        container.translatesAutoresizingMaskIntoConstraints = false
        
        let titleLabel = UILabel()
        titleLabel.text = title
        titleLabel.font = UIFont.systemFont(ofSize: 15, weight: .semibold)
        titleLabel.textColor = Constants.Colors.label
        titleLabel.translatesAutoresizingMaskIntoConstraints = false
        
        let subtitleLabel = UILabel()
        subtitleLabel.text = subtitle
        subtitleLabel.font = UIFont.systemFont(ofSize: 13)
        subtitleLabel.textColor = Constants.Colors.secondaryLabel
        subtitleLabel.translatesAutoresizingMaskIntoConstraints = false
        
        let checkmark = UIImageView()
        checkmark.image = UIImage(systemName: isSelected ? "checkmark.circle.fill" : "circle")
        checkmark.tintColor = isSelected ? Constants.Colors.primary : Constants.Colors.secondaryLabel
        checkmark.translatesAutoresizingMaskIntoConstraints = false
        
        container.addSubview(titleLabel)
        container.addSubview(subtitleLabel)
        container.addSubview(checkmark)
        
        NSLayoutConstraint.activate([
            container.heightAnchor.constraint(equalToConstant: 72),
            
            checkmark.leadingAnchor.constraint(equalTo: container.leadingAnchor, constant: 16),
            checkmark.centerYAnchor.constraint(equalTo: container.centerYAnchor),
            checkmark.widthAnchor.constraint(equalToConstant: 24),
            checkmark.heightAnchor.constraint(equalToConstant: 24),
            
            titleLabel.leadingAnchor.constraint(equalTo: checkmark.trailingAnchor, constant: 12),
            titleLabel.topAnchor.constraint(equalTo: container.topAnchor, constant: 16),
            titleLabel.trailingAnchor.constraint(equalTo: container.trailingAnchor, constant: -16),
            
            subtitleLabel.leadingAnchor.constraint(equalTo: titleLabel.leadingAnchor),
            subtitleLabel.topAnchor.constraint(equalTo: titleLabel.bottomAnchor, constant: 4),
            subtitleLabel.trailingAnchor.constraint(equalTo: titleLabel.trailingAnchor)
        ])
        
        // Add tap gesture
        let tapGesture = UITapGestureRecognizer(target: self, action: #selector(exportOptionTapped(_:)))
        container.addGestureRecognizer(tapGesture)
        container.isUserInteractionEnabled = true
        
        return container
    }
    
    // MARK: - Actions
    @objc private func cancelTapped() {
        dismiss(animated: true)
    }
    
    @objc private func exportOptionTapped(_ gesture: UITapGestureRecognizer) {
        guard let tappedView = gesture.view else { return }
        let tag = tappedView.tag
        
        // Update selection
        for (index, view) in exportTypeStackView.arrangedSubviews.enumerated() {
            let isSelected = index == tag
            view.backgroundColor = isSelected ? Constants.Colors.primary.withAlphaComponent(0.1) : Constants.Colors.secondaryBackground
            view.layer.borderWidth = isSelected ? 2 : 1
            view.layer.borderColor = isSelected ? Constants.Colors.primary.cgColor : Constants.Colors.separator.cgColor
            
            // Update checkmark
            if let checkmark = view.subviews.first(where: { $0 is UIImageView }) as? UIImageView {
                checkmark.image = UIImage(systemName: isSelected ? "checkmark.circle.fill" : "circle")
                checkmark.tintColor = isSelected ? Constants.Colors.primary : Constants.Colors.secondaryLabel
            }
        }
        
        // Update selected type
        switch tag {
        case 0: selectedExportType = .all
        case 1: selectedExportType = .circlesOnly
        case 2: selectedExportType = .placesOnly
        default: break
        }
    }
    
    @objc private func exportTapped() {
        showExportProgress()
        
        CSVExportService.shared.exportData(type: selectedExportType) { [weak self] result in
            DispatchQueue.main.async {
                self?.hideExportProgress()
                
                switch result {
                case .success(let fileURL):
                    self?.exportedFileURL = fileURL
                    self?.presentShareSheet(with: fileURL)
                case .failure(let error):
                    self?.showError("Failed to export data: \(error.localizedDescription)")
                }
            }
        }
    }
    
    private func showExportProgress() {
        exportButton.isEnabled = false
        progressContainer.isHidden = false
        progressIndicator.startAnimating()
        
        // Update progress label based on type
        switch selectedExportType {
        case .all:
            progressLabel.text = "Exporting all data..."
        case .circlesOnly:
            progressLabel.text = "Exporting circles..."
        case .placesOnly:
            progressLabel.text = "Exporting places..."
        }
    }
    
    private func hideExportProgress() {
        exportButton.isEnabled = true
        progressContainer.isHidden = true
        progressIndicator.stopAnimating()
    }
    
    private func presentShareSheet(with fileURL: URL) {
        let activityVC = UIActivityViewController(
            activityItems: [fileURL],
            applicationActivities: nil
        )
        
        // For iPad
        if let popover = activityVC.popoverPresentationController {
            popover.sourceView = exportButton
            popover.sourceRect = exportButton.bounds
        }
        
        // Set completion handler
        activityVC.completionWithItemsHandler = { [weak self] _, completed, _, _ in
            if completed {
                self?.showSuccess("Data exported successfully!")
                // Dismiss after a short delay
                DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) {
                    self?.dismiss(animated: true)
                }
            }
        }
        
        present(activityVC, animated: true)
    }
    
    // Override loadData from BaseViewController
    override func loadData(completion: (() -> Void)? = nil) {
        // No data to load initially
        completion?()
    }
}
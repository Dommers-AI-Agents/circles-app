import UIKit

class AccountMergeViewController: BaseViewController {
    
    // MARK: - Properties
    private var duplicateAccounts: [User] = []
    private var currentUser: User?
    
    // MARK: - UI Elements
    private lazy var titleLabel: UILabel = {
        let label = UILabel()
        label.text = "Merge Accounts"
        label.font = UIFont.systemFont(ofSize: 24, weight: .bold)
        label.textColor = Constants.Colors.label
        label.textAlignment = .center
        label.translatesAutoresizingMaskIntoConstraints = false
        return label
    }()
    
    private lazy var descriptionLabel: UILabel = {
        let label = UILabel()
        label.text = "We found potential duplicate accounts. Merge them to keep all your data in one place."
        label.font = UIFont.systemFont(ofSize: 16)
        label.textColor = Constants.Colors.secondaryLabel
        label.textAlignment = .center
        label.numberOfLines = 0
        label.translatesAutoresizingMaskIntoConstraints = false
        return label
    }()
    
    private lazy var tableView: UITableView = {
        let table = UITableView()
        table.delegate = self
        table.dataSource = self
        table.backgroundColor = Constants.Colors.background
        table.separatorStyle = .none
        table.translatesAutoresizingMaskIntoConstraints = false
        table.register(AccountMergeCell.self, forCellReuseIdentifier: "AccountMergeCell")
        return table
    }()
    
    private lazy var skipButton = UIButton.secondaryButton(title: "Skip for Now")
    
    // MARK: - BaseViewController Overrides
    override var showsLoadingIndicator: Bool { true }
    override var emptyStateMessage: String? { "No duplicate accounts found" }
    
    // MARK: - Lifecycle
    override func viewDidLoad() {
        super.viewDidLoad()
        setupNavigationBar()
        setupConstraints()
        setupActions()
    }
    
    // MARK: - Setup Methods
    private func setupNavigationBar() {
        title = "Account Merge"
        navigationItem.leftBarButtonItem = UIBarButtonItem(
            barButtonSystemItem: .cancel,
            target: self,
            action: #selector(cancelTapped)
        )
    }
    
    private func setupConstraints() {
        view.addSubview(titleLabel)
        view.addSubview(descriptionLabel)
        view.addSubview(tableView)
        view.addSubview(skipButton)
        
        NSLayoutConstraint.activate([
            titleLabel.topAnchor.constraint(equalTo: view.safeAreaLayoutGuide.topAnchor, constant: 20),
            titleLabel.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: 20),
            titleLabel.trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: -20),
            
            descriptionLabel.topAnchor.constraint(equalTo: titleLabel.bottomAnchor, constant: 16),
            descriptionLabel.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: 20),
            descriptionLabel.trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: -20),
            
            tableView.topAnchor.constraint(equalTo: descriptionLabel.bottomAnchor, constant: 24),
            tableView.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            tableView.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            tableView.bottomAnchor.constraint(equalTo: skipButton.topAnchor, constant: -20),
            
            skipButton.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: 20),
            skipButton.trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: -20),
            skipButton.bottomAnchor.constraint(equalTo: view.safeAreaLayoutGuide.bottomAnchor, constant: -20)
        ])
    }
    
    private func setupActions() {
        skipButton.addTarget(self, action: #selector(skipTapped), for: .touchUpInside)
    }
    
    // MARK: - Data Loading
    override func loadData(completion: (() -> Void)? = nil) {
        guard let currentUser = AuthService.shared.currentUser else {
            completion?()
            return
        }
        
        self.currentUser = currentUser
        
        // Call backend to find duplicate accounts
        UserService.findDuplicateAccounts(for: currentUser) { [weak self] result in
            DispatchQueue.main.async {
                switch result {
                case .success(let accounts):
                    self?.duplicateAccounts = accounts
                    self?.tableView.reloadData()
                case .failure(let error):
                    print("Failed to find duplicate accounts: \(error)")
                    self?.showError(error)
                }
                completion?()
            }
        }
    }
    
    // MARK: - Actions
    @objc private func cancelTapped() {
        dismiss(animated: true)
    }
    
    @objc private func skipTapped() {
        dismiss(animated: true)
    }
    
    private func mergeAccount(_ duplicateAccount: User) {
        guard let currentUser = self.currentUser else { return }
        
        let alert = UIAlertController(
            title: "Merge Accounts",
            message: "This will merge \(duplicateAccount.email ?? "this account") into your current account. This action cannot be undone. Continue?",
            preferredStyle: .alert
        )
        
        alert.addAction(UIAlertAction(title: "Cancel", style: .cancel))
        alert.addAction(UIAlertAction(title: "Merge", style: .destructive) { [weak self] _ in
            self?.performMerge(primary: currentUser, secondary: duplicateAccount)
        })
        
        present(alert, animated: true)
    }
    
    private func performMerge(primary: User, secondary: User) {
        showLoadingState()
        
        UserService.mergeAccounts(primaryId: primary.id, secondaryId: secondary.id) { [weak self] result in
            DispatchQueue.main.async {
                self?.hideLoadingState()
                
                switch result {
                case .success(let mergedUser):
                    // Update current user
                    AuthService.shared.updateCurrentUser(mergedUser)
                    
                    // Show success message
                    self?.showSuccess("Accounts merged successfully!")
                    
                    // Reload data to remove merged account from list
                    self?.loadData()
                    
                case .failure(let error):
                    self?.showError(error)
                }
            }
        }
    }
}

// MARK: - UITableViewDataSource
extension AccountMergeViewController: UITableViewDataSource {
    func tableView(_ tableView: UITableView, numberOfRowsInSection section: Int) -> Int {
        return duplicateAccounts.count
    }
    
    func tableView(_ tableView: UITableView, cellForRowAt indexPath: IndexPath) -> UITableViewCell {
        let cell = tableView.dequeueReusableCell(withIdentifier: "AccountMergeCell", for: indexPath) as! AccountMergeCell
        let account = duplicateAccounts[indexPath.row]
        cell.configure(with: account, currentUser: currentUser)
        cell.delegate = self
        return cell
    }
}

// MARK: - UITableViewDelegate
extension AccountMergeViewController: UITableViewDelegate {
    func tableView(_ tableView: UITableView, heightForRowAt indexPath: IndexPath) -> CGFloat {
        return 100
    }
}

// MARK: - AccountMergeCellDelegate
extension AccountMergeViewController: AccountMergeCellDelegate {
    func didTapMergeButton(for user: User) {
        mergeAccount(user)
    }
}

// MARK: - AccountMergeCell
protocol AccountMergeCellDelegate: AnyObject {
    func didTapMergeButton(for user: User)
}

class AccountMergeCell: UITableViewCell {
    weak var delegate: AccountMergeCellDelegate?
    private var user: User?
    
    private lazy var containerView: UIView = {
        let view = UIView()
        view.backgroundColor = Constants.Colors.secondaryBackground
        view.layer.cornerRadius = 12
        view.layer.shadowColor = UIColor.black.cgColor
        view.layer.shadowOffset = CGSize(width: 0, height: 2)
        view.layer.shadowRadius = 4
        view.layer.shadowOpacity = 0.1
        view.translatesAutoresizingMaskIntoConstraints = false
        return view
    }()
    
    private lazy var emailLabel: UILabel = {
        let label = UILabel()
        label.font = UIFont.systemFont(ofSize: 16, weight: .medium)
        label.textColor = Constants.Colors.label
        label.translatesAutoresizingMaskIntoConstraints = false
        return label
    }()
    
    private lazy var providerLabel: UILabel = {
        let label = UILabel()
        label.font = UIFont.systemFont(ofSize: 14)
        label.textColor = Constants.Colors.secondaryLabel
        label.translatesAutoresizingMaskIntoConstraints = false
        return label
    }()
    
    private lazy var warningLabel: UILabel = {
        let label = UILabel()
        label.text = "⚠️ Private relay email"
        label.font = UIFont.systemFont(ofSize: 12)
        label.textColor = Constants.Colors.warning
        label.translatesAutoresizingMaskIntoConstraints = false
        return label
    }()
    
    private lazy var mergeButton = UIButton.primaryButton(title: "Merge")
    
    override init(style: UITableViewCell.CellStyle, reuseIdentifier: String?) {
        super.init(style: style, reuseIdentifier: reuseIdentifier)
        setupCell()
    }
    
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }
    
    private func setupCell() {
        selectionStyle = .none
        backgroundColor = .clear
        
        contentView.addSubview(containerView)
        containerView.addSubview(emailLabel)
        containerView.addSubview(providerLabel)
        containerView.addSubview(warningLabel)
        containerView.addSubview(mergeButton)
        
        mergeButton.addTarget(self, action: #selector(mergeButtonTapped), for: .touchUpInside)
        
        NSLayoutConstraint.activate([
            containerView.topAnchor.constraint(equalTo: contentView.topAnchor, constant: 8),
            containerView.leadingAnchor.constraint(equalTo: contentView.leadingAnchor, constant: 16),
            containerView.trailingAnchor.constraint(equalTo: contentView.trailingAnchor, constant: -16),
            containerView.bottomAnchor.constraint(equalTo: contentView.bottomAnchor, constant: -8),
            
            emailLabel.topAnchor.constraint(equalTo: containerView.topAnchor, constant: 12),
            emailLabel.leadingAnchor.constraint(equalTo: containerView.leadingAnchor, constant: 16),
            emailLabel.trailingAnchor.constraint(equalTo: mergeButton.leadingAnchor, constant: -12),
            
            providerLabel.topAnchor.constraint(equalTo: emailLabel.bottomAnchor, constant: 4),
            providerLabel.leadingAnchor.constraint(equalTo: containerView.leadingAnchor, constant: 16),
            providerLabel.trailingAnchor.constraint(equalTo: mergeButton.leadingAnchor, constant: -12),
            
            warningLabel.topAnchor.constraint(equalTo: providerLabel.bottomAnchor, constant: 4),
            warningLabel.leadingAnchor.constraint(equalTo: containerView.leadingAnchor, constant: 16),
            warningLabel.trailingAnchor.constraint(equalTo: mergeButton.leadingAnchor, constant: -12),
            warningLabel.bottomAnchor.constraint(lessThanOrEqualTo: containerView.bottomAnchor, constant: -12),
            
            mergeButton.centerYAnchor.constraint(equalTo: containerView.centerYAnchor),
            mergeButton.trailingAnchor.constraint(equalTo: containerView.trailingAnchor, constant: -16),
            mergeButton.widthAnchor.constraint(equalToConstant: 80),
            mergeButton.heightAnchor.constraint(equalToConstant: 36)
        ])
    }
    
    func configure(with user: User, currentUser: User?) {
        self.user = user
        emailLabel.text = user.email ?? "No email"
        
        // Determine provider
        if user.email?.contains("@privaterelay.appleid.com") == true {
            providerLabel.text = "Apple Sign In (Private Relay)"
            warningLabel.isHidden = false
        } else {
            providerLabel.text = "Email Account"
            warningLabel.isHidden = true
        }
    }
    
    @objc private func mergeButtonTapped() {
        guard let user = user else { return }
        delegate?.didTapMergeButton(for: user)
    }
}
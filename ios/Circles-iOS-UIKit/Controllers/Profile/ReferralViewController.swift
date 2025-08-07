import UIKit

class ReferralViewController: BaseViewController {
    
    // MARK: - Properties
    private var referralStatus: ReferralStatus?
    
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
    
    private let headerView: UIView = {
        let view = UIView()
        view.translatesAutoresizingMaskIntoConstraints = false
        view.backgroundColor = Constants.Colors.primary
        return view
    }()
    
    private let giftImageView: UIImageView = {
        let imageView = UIImageView()
        imageView.translatesAutoresizingMaskIntoConstraints = false
        imageView.image = UIImage(systemName: "gift.circle.fill")
        imageView.tintColor = .white
        imageView.contentMode = .scaleAspectFit
        return imageView
    }()
    
    private let titleLabel: UILabel = {
        let label = UILabel()
        label.translatesAutoresizingMaskIntoConstraints = false
        label.text = "Invite Friends, Get Rewards"
        label.font = UIFont.systemFont(ofSize: 24, weight: .bold)
        label.textColor = .white
        label.textAlignment = .center
        return label
    }()
    
    private let descriptionLabel: UILabel = {
        let label = UILabel()
        label.translatesAutoresizingMaskIntoConstraints = false
        label.text = "Share your referral code and both you and your friend get a month free!"
        label.font = UIFont.systemFont(ofSize: 16)
        label.textColor = .white.withAlphaComponent(0.9)
        label.textAlignment = .center
        label.numberOfLines = 0
        return label
    }()
    
    private let referralCodeContainer: UIView = {
        let view = UIView()
        view.translatesAutoresizingMaskIntoConstraints = false
        view.backgroundColor = UIColor.systemGray6
        view.layer.cornerRadius = 12
        return view
    }()
    
    private let referralCodeLabel: UILabel = {
        let label = UILabel()
        label.translatesAutoresizingMaskIntoConstraints = false
        label.text = "Loading..."
        label.font = UIFont.systemFont(ofSize: 32, weight: .bold)
        label.textColor = Constants.Colors.primary
        label.textAlignment = .center
        return label
    }()
    
    private let copyButton = UIButton.secondaryButton(title: "Copy Code")
    private let shareButton = UIButton.primaryButton(title: "Share with Friends")
    
    private let statsContainer: UIView = {
        let view = UIView()
        view.translatesAutoresizingMaskIntoConstraints = false
        view.backgroundColor = UIColor.systemGray6
        view.layer.cornerRadius = 12
        return view
    }()
    
    private let friendsInvitedLabel: UILabel = {
        let label = UILabel()
        label.translatesAutoresizingMaskIntoConstraints = false
        label.font = UIFont.systemFont(ofSize: 14)
        label.textColor = .secondaryLabel
        label.textAlignment = .center
        return label
    }()
    
    private let monthsEarnedLabel: UILabel = {
        let label = UILabel()
        label.translatesAutoresizingMaskIntoConstraints = false
        label.font = UIFont.systemFont(ofSize: 14)
        label.textColor = .secondaryLabel
        label.textAlignment = .center
        return label
    }()
    
    private let remainingInvitesLabel: UILabel = {
        let label = UILabel()
        label.translatesAutoresizingMaskIntoConstraints = false
        label.font = UIFont.systemFont(ofSize: 14)
        label.textColor = .secondaryLabel
        label.textAlignment = .center
        return label
    }()
    
    private let claimRewardsButton = UIButton.primaryButton(title: "Claim Rewards")
    
    private let howItWorksLabel: UILabel = {
        let label = UILabel()
        label.translatesAutoresizingMaskIntoConstraints = false
        label.text = "How it works:"
        label.font = UIFont.systemFont(ofSize: 18, weight: .semibold)
        label.textColor = .label
        return label
    }()
    
    private let stepsLabel: UILabel = {
        let label = UILabel()
        label.translatesAutoresizingMaskIntoConstraints = false
        label.numberOfLines = 0
        label.font = UIFont.systemFont(ofSize: 14)
        label.textColor = .secondaryLabel
        
        let steps = """
        1. Share your unique referral code with friends
        2. They sign up using your code
        3. They get 1 month free
        4. You get 1 month free when they sign up
        5. Maximum 12 referrals per year
        """
        
        label.text = steps
        return label
    }()
    
    // MARK: - Lifecycle
    
    override func viewDidLoad() {
        super.viewDidLoad()
        title = "Invite Friends"
        view.backgroundColor = .systemBackground
        
        setupUI()
        setupActions()
    }
    
    override func viewWillAppear(_ animated: Bool) {
        super.viewWillAppear(animated)
        loadReferralStatus()
    }
    
    // MARK: - BaseViewController
    
    override func loadData(completion: (() -> Void)? = nil) {
        loadReferralStatus(completion: completion)
    }
    
    // MARK: - Setup
    
    private func setupUI() {
        view.addSubview(scrollView)
        scrollView.addSubview(contentView)
        
        contentView.addSubview(headerView)
        headerView.addSubview(giftImageView)
        headerView.addSubview(titleLabel)
        headerView.addSubview(descriptionLabel)
        
        contentView.addSubview(referralCodeContainer)
        referralCodeContainer.addSubview(referralCodeLabel)
        referralCodeContainer.addSubview(copyButton)
        
        contentView.addSubview(shareButton)
        
        contentView.addSubview(statsContainer)
        statsContainer.addSubview(friendsInvitedLabel)
        statsContainer.addSubview(monthsEarnedLabel)
        statsContainer.addSubview(remainingInvitesLabel)
        
        contentView.addSubview(claimRewardsButton)
        contentView.addSubview(howItWorksLabel)
        contentView.addSubview(stepsLabel)
        
        NSLayoutConstraint.activate([
            // ScrollView
            scrollView.topAnchor.constraint(equalTo: view.safeAreaLayoutGuide.topAnchor),
            scrollView.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            scrollView.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            scrollView.bottomAnchor.constraint(equalTo: view.bottomAnchor),
            
            // ContentView
            contentView.topAnchor.constraint(equalTo: scrollView.topAnchor),
            contentView.leadingAnchor.constraint(equalTo: scrollView.leadingAnchor),
            contentView.trailingAnchor.constraint(equalTo: scrollView.trailingAnchor),
            contentView.bottomAnchor.constraint(equalTo: scrollView.bottomAnchor),
            contentView.widthAnchor.constraint(equalTo: scrollView.widthAnchor),
            
            // Header
            headerView.topAnchor.constraint(equalTo: contentView.topAnchor),
            headerView.leadingAnchor.constraint(equalTo: contentView.leadingAnchor),
            headerView.trailingAnchor.constraint(equalTo: contentView.trailingAnchor),
            headerView.heightAnchor.constraint(equalToConstant: 200),
            
            giftImageView.centerXAnchor.constraint(equalTo: headerView.centerXAnchor),
            giftImageView.topAnchor.constraint(equalTo: headerView.topAnchor, constant: 20),
            giftImageView.widthAnchor.constraint(equalToConstant: 60),
            giftImageView.heightAnchor.constraint(equalToConstant: 60),
            
            titleLabel.topAnchor.constraint(equalTo: giftImageView.bottomAnchor, constant: 10),
            titleLabel.leadingAnchor.constraint(equalTo: headerView.leadingAnchor, constant: 20),
            titleLabel.trailingAnchor.constraint(equalTo: headerView.trailingAnchor, constant: -20),
            
            descriptionLabel.topAnchor.constraint(equalTo: titleLabel.bottomAnchor, constant: 10),
            descriptionLabel.leadingAnchor.constraint(equalTo: headerView.leadingAnchor, constant: 20),
            descriptionLabel.trailingAnchor.constraint(equalTo: headerView.trailingAnchor, constant: -20),
            
            // Referral Code
            referralCodeContainer.topAnchor.constraint(equalTo: headerView.bottomAnchor, constant: 20),
            referralCodeContainer.leadingAnchor.constraint(equalTo: contentView.leadingAnchor, constant: 20),
            referralCodeContainer.trailingAnchor.constraint(equalTo: contentView.trailingAnchor, constant: -20),
            referralCodeContainer.heightAnchor.constraint(equalToConstant: 120),
            
            referralCodeLabel.centerXAnchor.constraint(equalTo: referralCodeContainer.centerXAnchor),
            referralCodeLabel.topAnchor.constraint(equalTo: referralCodeContainer.topAnchor, constant: 20),
            
            copyButton.centerXAnchor.constraint(equalTo: referralCodeContainer.centerXAnchor),
            copyButton.bottomAnchor.constraint(equalTo: referralCodeContainer.bottomAnchor, constant: -15),
            copyButton.widthAnchor.constraint(equalToConstant: 120),
            
            // Share Button
            shareButton.topAnchor.constraint(equalTo: referralCodeContainer.bottomAnchor, constant: 15),
            shareButton.leadingAnchor.constraint(equalTo: contentView.leadingAnchor, constant: 20),
            shareButton.trailingAnchor.constraint(equalTo: contentView.trailingAnchor, constant: -20),
            
            // Stats
            statsContainer.topAnchor.constraint(equalTo: shareButton.bottomAnchor, constant: 30),
            statsContainer.leadingAnchor.constraint(equalTo: contentView.leadingAnchor, constant: 20),
            statsContainer.trailingAnchor.constraint(equalTo: contentView.trailingAnchor, constant: -20),
            statsContainer.heightAnchor.constraint(equalToConstant: 100),
            
            friendsInvitedLabel.leadingAnchor.constraint(equalTo: statsContainer.leadingAnchor, constant: 15),
            friendsInvitedLabel.centerYAnchor.constraint(equalTo: statsContainer.centerYAnchor, constant: -20),
            
            monthsEarnedLabel.centerXAnchor.constraint(equalTo: statsContainer.centerXAnchor),
            monthsEarnedLabel.centerYAnchor.constraint(equalTo: statsContainer.centerYAnchor, constant: -20),
            
            remainingInvitesLabel.trailingAnchor.constraint(equalTo: statsContainer.trailingAnchor, constant: -15),
            remainingInvitesLabel.centerYAnchor.constraint(equalTo: statsContainer.centerYAnchor, constant: -20),
            
            // Claim Rewards Button
            claimRewardsButton.topAnchor.constraint(equalTo: statsContainer.bottomAnchor, constant: 15),
            claimRewardsButton.leadingAnchor.constraint(equalTo: contentView.leadingAnchor, constant: 20),
            claimRewardsButton.trailingAnchor.constraint(equalTo: contentView.trailingAnchor, constant: -20),
            
            // How it works
            howItWorksLabel.topAnchor.constraint(equalTo: claimRewardsButton.bottomAnchor, constant: 30),
            howItWorksLabel.leadingAnchor.constraint(equalTo: contentView.leadingAnchor, constant: 20),
            howItWorksLabel.trailingAnchor.constraint(equalTo: contentView.trailingAnchor, constant: -20),
            
            stepsLabel.topAnchor.constraint(equalTo: howItWorksLabel.bottomAnchor, constant: 10),
            stepsLabel.leadingAnchor.constraint(equalTo: contentView.leadingAnchor, constant: 20),
            stepsLabel.trailingAnchor.constraint(equalTo: contentView.trailingAnchor, constant: -20),
            stepsLabel.bottomAnchor.constraint(equalTo: contentView.bottomAnchor, constant: -30)
        ])
        
        // Initially hide claim button
        claimRewardsButton.isHidden = true
    }
    
    private func setupActions() {
        copyButton.addTarget(self, action: #selector(copyTapped), for: .touchUpInside)
        shareButton.addTarget(self, action: #selector(shareTapped), for: .touchUpInside)
        claimRewardsButton.addTarget(self, action: #selector(claimTapped), for: .touchUpInside)
    }
    
    // MARK: - Data Loading
    
    private func loadReferralStatus(completion: (() -> Void)? = nil) {
        showLoadingState()
        
        ReferralService.shared.getReferralStatus { [weak self] result in
            DispatchQueue.main.async {
                self?.hideLoadingState()
                completion?()
                
                switch result {
                case .success(let status):
                    self?.referralStatus = status
                    self?.updateUI(with: status)
                    
                    // Generate code if needed
                    if status.referralCode == nil {
                        self?.generateReferralCode()
                    }
                    
                case .failure(let error):
                    self?.showError(error)
                }
            }
        }
    }
    
    private func generateReferralCode() {
        ReferralService.shared.generateReferralCode { [weak self] result in
            DispatchQueue.main.async {
                switch result {
                case .success(let code):
                    self?.referralCodeLabel.text = code
                    
                case .failure(let error):
                    self?.showError(error)
                }
            }
        }
    }
    
    private func updateUI(with status: ReferralStatus) {
        // Update referral code
        referralCodeLabel.text = status.referralCode ?? "Generating..."
        
        // Update stats
        let friendsText = NSMutableAttributedString()
        friendsText.append(NSAttributedString(string: "\(status.referralCount)\n", 
                                            attributes: [.font: UIFont.systemFont(ofSize: 24, weight: .bold),
                                                       .foregroundColor: UIColor.label]))
        friendsText.append(NSAttributedString(string: "Friends Invited", 
                                            attributes: [.font: UIFont.systemFont(ofSize: 12),
                                                       .foregroundColor: UIColor.secondaryLabel]))
        friendsInvitedLabel.attributedText = friendsText
        
        let monthsText = NSMutableAttributedString()
        monthsText.append(NSAttributedString(string: "\(status.totalRewards)\n", 
                                           attributes: [.font: UIFont.systemFont(ofSize: 24, weight: .bold),
                                                      .foregroundColor: UIColor.label]))
        monthsText.append(NSAttributedString(string: "Months Earned", 
                                           attributes: [.font: UIFont.systemFont(ofSize: 12),
                                                      .foregroundColor: UIColor.secondaryLabel]))
        monthsEarnedLabel.attributedText = monthsText
        
        let remainingText = NSMutableAttributedString()
        remainingText.append(NSAttributedString(string: "\(status.remainingReferrals)\n", 
                                              attributes: [.font: UIFont.systemFont(ofSize: 24, weight: .bold),
                                                         .foregroundColor: UIColor.label]))
        remainingText.append(NSAttributedString(string: "Invites Left", 
                                              attributes: [.font: UIFont.systemFont(ofSize: 12),
                                                         .foregroundColor: UIColor.secondaryLabel]))
        remainingInvitesLabel.attributedText = remainingText
        
        // Show/hide claim button
        if status.unclaimedRewards > 0 {
            claimRewardsButton.isHidden = false
            claimRewardsButton.setTitle("Claim \(status.unclaimedRewards) Month\(status.unclaimedRewards > 1 ? "s" : "") Free", for: .normal)
        } else {
            claimRewardsButton.isHidden = true
        }
    }
    
    // MARK: - Actions
    
    @objc private func copyTapped() {
        guard let code = referralStatus?.referralCode else { return }
        
        UIPasteboard.general.string = code
        
        // Show feedback
        let feedback = UILabel()
        feedback.text = "Copied!"
        feedback.font = UIFont.systemFont(ofSize: 14, weight: .medium)
        feedback.textColor = .white
        feedback.backgroundColor = UIColor.black.withAlphaComponent(0.8)
        feedback.textAlignment = .center
        feedback.layer.cornerRadius = 15
        feedback.clipsToBounds = true
        feedback.translatesAutoresizingMaskIntoConstraints = false
        
        view.addSubview(feedback)
        NSLayoutConstraint.activate([
            feedback.centerXAnchor.constraint(equalTo: copyButton.centerXAnchor),
            feedback.bottomAnchor.constraint(equalTo: copyButton.topAnchor, constant: -10),
            feedback.widthAnchor.constraint(equalToConstant: 80),
            feedback.heightAnchor.constraint(equalToConstant: 30)
        ])
        
        UIView.animate(withDuration: 0.3, animations: {
            feedback.alpha = 1
        }) { _ in
            UIView.animate(withDuration: 0.3, delay: 1.0, options: [], animations: {
                feedback.alpha = 0
            }) { _ in
                feedback.removeFromSuperview()
            }
        }
    }
    
    @objc private func shareTapped() {
        guard let code = referralStatus?.referralCode else { return }
        ReferralService.shared.shareReferralLink(code: code, from: self)
    }
    
    @objc private func claimTapped() {
        showLoadingState()
        claimRewardsButton.isEnabled = false
        
        ReferralService.shared.claimReferralRewards { [weak self] result in
            DispatchQueue.main.async {
                self?.hideLoadingState()
                
                switch result {
                case .success(let response):
                    AlertPresenter.showSuccess(response.message, from: self!)
                    self?.loadReferralStatus()
                    
                case .failure(let error):
                    self?.claimRewardsButton.isEnabled = true
                    self?.showError(error)
                }
            }
        }
    }
}
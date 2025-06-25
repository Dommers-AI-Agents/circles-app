import UIKit

class TermsOfServiceViewController: UIViewController {
    
    // MARK: - UI Elements
    private let scrollView: UIScrollView = {
        let scrollView = UIScrollView()
        scrollView.translatesAutoresizingMaskIntoConstraints = false
        return scrollView
    }()
    
    private let contentView: UIView = {
        let view = UIView()
        view.translatesAutoresizingMaskIntoConstraints = false
        return view
    }()
    
    private let termsTextView: UITextView = {
        let textView = UITextView()
        textView.isEditable = false
        textView.isScrollEnabled = false
        textView.font = UIFont.systemFont(ofSize: Constants.FontSize.medium)
        textView.textColor = Constants.Colors.darkGray
        textView.backgroundColor = .clear
        textView.translatesAutoresizingMaskIntoConstraints = false
        return textView
    }()
    
    // MARK: - Lifecycle
    override func viewDidLoad() {
        super.viewDidLoad()
        setupUI()
        loadTermsOfService()
    }
    
    // MARK: - UI Setup
    private func setupUI() {
        view.backgroundColor = Constants.Colors.background
        title = "Terms of Service"
        navigationItem.largeTitleDisplayMode = .never
        
        // Add subviews
        view.addSubview(scrollView)
        scrollView.addSubview(contentView)
        contentView.addSubview(termsTextView)
        
        // Layout constraints
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
            
            // Terms text view
            termsTextView.topAnchor.constraint(equalTo: contentView.topAnchor, constant: Constants.Spacing.medium),
            termsTextView.leadingAnchor.constraint(equalTo: contentView.leadingAnchor, constant: Constants.Spacing.medium),
            termsTextView.trailingAnchor.constraint(equalTo: contentView.trailingAnchor, constant: -Constants.Spacing.medium),
            termsTextView.bottomAnchor.constraint(equalTo: contentView.bottomAnchor, constant: -Constants.Spacing.medium)
        ])
    }
    
    private func loadTermsOfService() {
        termsTextView.text = """
        TERMS OF SERVICE
        
        Last updated: December 2024
        
        1. ACCEPTANCE OF TERMS
        
        By accessing and using Circles ("the App"), you accept and agree to be bound by the terms and provision of this agreement. If you do not agree to abide by the above, please do not use this service.
        
        2. USE LICENSE
        
        Permission is granted to temporarily download one copy of the App for personal, non-commercial transitory viewing only. This is the grant of a license, not a transfer of title, and under this license you may not:
        • modify or copy the materials
        • use the materials for any commercial purpose, or for any public display (commercial or non-commercial)
        • attempt to decompile or reverse engineer any software contained in the App
        • remove any copyright or other proprietary notations from the materials
        
        3. DISCLAIMER
        
        The materials within the App are provided on an 'as is' basis. Circles makes no warranties, expressed or implied, and hereby disclaims and negates all other warranties including, without limitation, implied warranties or conditions of merchantability, fitness for a particular purpose, or non-infringement of intellectual property or other violation of rights.
        
        4. USER CONTENT
        
        By posting content to the App, you grant Circles a non-exclusive, worldwide, royalty-free license to use, reproduce, and distribute your content in connection with the service. You represent and warrant that you own or have the necessary rights to all content you post.
        
        5. PRIVACY
        
        Your use of the App is also governed by our Privacy Policy. Please review our Privacy Policy, which also governs the Site and informs users of our data collection practices.
        
        6. PROHIBITED USES
        
        You may not use the App:
        • For any unlawful purpose or to solicit others to perform unlawful acts
        • To violate any international, federal, provincial, or state regulations, rules, laws, or local ordinances
        • To infringe upon or violate our intellectual property rights or the intellectual property rights of others
        • To harass, abuse, insult, harm, defame, slander, disparage, intimidate, or discriminate
        • To submit false or misleading information
        • To upload or transmit viruses or any other type of malicious code
        
        7. TERMINATION
        
        We may terminate or suspend your account and bar access to the App immediately, without prior notice or liability, under our sole discretion, for any reason whatsoever and without limitation, including but not limited to a breach of the Terms.
        
        8. GOVERNING LAW
        
        These Terms shall be governed and construed in accordance with the laws of the United States, without regard to its conflict of law provisions. Our failure to enforce any right or provision of these Terms will not be considered a waiver of those rights.
        
        9. CHANGES TO TERMS
        
        Circles reserves the right, at our sole discretion, to modify or replace these Terms at any time. If a revision is material, we will provide at least 30 days notice prior to any new terms taking effect.
        
        10. CONTACT INFORMATION
        
        If you have any questions about these Terms, please contact us at support@favcircles.com.
        """
    }
}
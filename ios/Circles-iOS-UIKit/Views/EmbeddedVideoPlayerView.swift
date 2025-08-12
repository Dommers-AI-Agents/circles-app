import UIKit
import WebKit

class EmbeddedVideoPlayerView: UIView {
    
    // MARK: - Properties
    private let webView: WKWebView
    private var video: PlaceVideo?
    
    // MARK: - UI Elements
    private let loadingIndicator: UIActivityIndicatorView = {
        let indicator = UIActivityIndicatorView(style: .medium)
        indicator.hidesWhenStopped = true
        indicator.translatesAutoresizingMaskIntoConstraints = false
        return indicator
    }()
    
    private let errorLabel: UILabel = {
        let label = UILabel()
        label.text = "Unable to load video"
        label.textAlignment = .center
        label.textColor = .secondaryLabel
        label.font = .systemFont(ofSize: 14)
        label.isHidden = true
        label.translatesAutoresizingMaskIntoConstraints = false
        return label
    }()
    
    private let platformBadge: UILabel = {
        let label = UILabel()
        label.font = .systemFont(ofSize: 12, weight: .medium)
        label.textColor = .white
        label.layer.cornerRadius = 4
        label.clipsToBounds = true
        label.textAlignment = .center
        label.translatesAutoresizingMaskIntoConstraints = false
        return label
    }()
    
    // MARK: - Initialization
    override init(frame: CGRect) {
        // Configure WKWebView
        let configuration = WKWebViewConfiguration()
        configuration.allowsInlineMediaPlayback = true
        configuration.mediaTypesRequiringUserActionForPlayback = []
        
        // Add YouTube/Instagram/TikTok iframe API support
        let preferences = WKPreferences()
        preferences.javaScriptEnabled = true
        configuration.preferences = preferences
        
        self.webView = WKWebView(frame: .zero, configuration: configuration)
        
        super.init(frame: frame)
        
        setupUI()
    }
    
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }
    
    // MARK: - Setup
    private func setupUI() {
        backgroundColor = .systemBackground
        
        webView.navigationDelegate = self
        webView.scrollView.isScrollEnabled = false
        webView.translatesAutoresizingMaskIntoConstraints = false
        webView.isOpaque = false
        webView.backgroundColor = .clear
        
        addSubview(webView)
        addSubview(loadingIndicator)
        addSubview(errorLabel)
        addSubview(platformBadge)
        
        NSLayoutConstraint.activate([
            webView.topAnchor.constraint(equalTo: topAnchor),
            webView.leadingAnchor.constraint(equalTo: leadingAnchor),
            webView.trailingAnchor.constraint(equalTo: trailingAnchor),
            webView.bottomAnchor.constraint(equalTo: bottomAnchor),
            
            loadingIndicator.centerXAnchor.constraint(equalTo: centerXAnchor),
            loadingIndicator.centerYAnchor.constraint(equalTo: centerYAnchor),
            
            errorLabel.centerXAnchor.constraint(equalTo: centerXAnchor),
            errorLabel.centerYAnchor.constraint(equalTo: centerYAnchor),
            errorLabel.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 20),
            errorLabel.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -20),
            
            platformBadge.topAnchor.constraint(equalTo: topAnchor, constant: 12),
            platformBadge.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -12),
            platformBadge.widthAnchor.constraint(greaterThanOrEqualToConstant: 60),
            platformBadge.heightAnchor.constraint(equalToConstant: 24)
        ])
        
        // Add padding to platform badge
        platformBadge.layoutMargins = UIEdgeInsets(top: 2, left: 8, bottom: 2, right: 8)
    }
    
    // MARK: - Public Methods
    func loadVideo(_ video: PlaceVideo) {
        self.video = video
        
        // Show platform badge
        if let platform = video.embedPlatform {
            platformBadge.text = " \(platform.uppercased()) "
            platformBadge.backgroundColor = platformColor(for: platform)
            platformBadge.isHidden = false
        } else {
            platformBadge.isHidden = true
        }
        
        // Load embedded content
        if video.isEmbedded {
            loadEmbeddedVideo()
        } else {
            // For uploaded videos, we could load a video player here
            loadUploadedVideo()
        }
    }
    
    private func loadEmbeddedVideo() {
        guard let video = video else { return }
        
        loadingIndicator.startAnimating()
        errorLabel.isHidden = true
        
        if let embedHtml = video.embedHtml {
            // Load the embed HTML directly
            let html = wrapEmbedHtml(embedHtml)
            webView.loadHTMLString(html, baseURL: nil)
        } else if let embedUrl = video.embedUrl {
            // Fallback: load the URL directly
            if let url = URL(string: embedUrl) {
                let request = URLRequest(url: url)
                webView.load(request)
            }
        } else {
            showError()
        }
    }
    
    private func loadUploadedVideo() {
        // For uploaded videos, show thumbnail or load video player
        if let thumbnailUrl = video?.thumbnailUrl {
            // We could load a thumbnail here and add play button overlay
            showError() // For now, just show error
        } else {
            showError()
        }
    }
    
    private func wrapEmbedHtml(_ embedHtml: String) -> String {
        return """
        <!DOCTYPE html>
        <html>
        <head>
            <meta name="viewport" content="width=device-width, initial-scale=1.0, maximum-scale=1.0, user-scalable=no">
            <style>
                body {
                    margin: 0;
                    padding: 0;
                    background: black;
                    display: flex;
                    justify-content: center;
                    align-items: center;
                    height: 100vh;
                    overflow: hidden;
                }
                iframe, video {
                    max-width: 100%;
                    max-height: 100%;
                    width: 100%;
                    height: 100vh;
                    border: none;
                }
            </style>
        </head>
        <body>
            \(embedHtml)
        </body>
        </html>
        """
    }
    
    private func showError() {
        loadingIndicator.stopAnimating()
        errorLabel.isHidden = false
        webView.isHidden = true
    }
    
    private func platformColor(for platform: String) -> UIColor {
        switch platform.lowercased() {
        case "tiktok": return .black
        case "instagram": return .systemPink
        case "youtube": return .systemRed
        case "twitter", "x": return .systemBlue
        default: return .systemGray
        }
    }
    
    // MARK: - Player Controls
    func play() {
        webView.evaluateJavaScript("document.querySelector('video')?.play() || document.querySelector('iframe')?.contentWindow.postMessage('{\"event\":\"command\",\"func\":\"playVideo\",\"args\":\"\"}', '*')", completionHandler: nil)
    }
    
    func pause() {
        webView.evaluateJavaScript("document.querySelector('video')?.pause() || document.querySelector('iframe')?.contentWindow.postMessage('{\"event\":\"command\",\"func\":\"pauseVideo\",\"args\":\"\"}', '*')", completionHandler: nil)
    }
    
    func mute() {
        webView.evaluateJavaScript("document.querySelector('video')?.muted = true", completionHandler: nil)
    }
    
    func unmute() {
        webView.evaluateJavaScript("document.querySelector('video')?.muted = false", completionHandler: nil)
    }
}

// MARK: - WKNavigationDelegate
extension EmbeddedVideoPlayerView: WKNavigationDelegate {
    func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
        loadingIndicator.stopAnimating()
        errorLabel.isHidden = true
        webView.isHidden = false
    }
    
    func webView(_ webView: WKWebView, didFail navigation: WKNavigation!, withError error: Error) {
        showError()
    }
    
    func webView(_ webView: WKWebView, didFailProvisionalNavigation navigation: WKNavigation!, withError error: Error) {
        showError()
    }
}
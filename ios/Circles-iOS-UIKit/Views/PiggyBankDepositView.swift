import UIKit

/// The coin-into-the-piggy-bank deposit moment. A small window-level toast
/// (~1.7s, non-blocking, survives navigation): a FavCoin drops into the piggy
/// bank while "+N FavCoins" fades in. Deliberately playful and deliberately
/// value-free — coins, not currency.
final class PiggyBankDepositView: UIView {

    private static var activeView: PiggyBankDepositView?

    /// Plays the deposit animation for a successful credit. Safe to call with
    /// anything — plays only when coins were actually credited.
    static func play(credit: PiggyBankCredit?) {
        guard let credit = credit, credit.credited, let coins = credit.coins, coins > 0 else { return }
        DispatchQueue.main.async { show(coins: coins) }
    }

    private static func show(coins: Int) {
        guard let window = UIApplication.shared.connectedScenes
            .compactMap({ ($0 as? UIWindowScene)?.keyWindow }).first else { return }

        // One at a time — a rapid second earn replaces the first.
        activeView?.removeFromSuperview()

        let view = PiggyBankDepositView(coins: coins)
        activeView = view
        window.addSubview(view)
        NSLayoutConstraint.activate([
            view.topAnchor.constraint(equalTo: window.safeAreaLayoutGuide.topAnchor, constant: 8),
            view.centerXAnchor.constraint(equalTo: window.centerXAnchor)
        ])
        view.animateIn()
    }

    private let piggyLabel: UILabel = {
        let label = UILabel()
        label.text = "🐷"
        label.font = .systemFont(ofSize: 34)
        label.translatesAutoresizingMaskIntoConstraints = false
        return label
    }()

    private let coinLabel: UILabel = {
        let label = UILabel()
        label.text = "🪙"
        label.font = .systemFont(ofSize: 20)
        label.translatesAutoresizingMaskIntoConstraints = false
        return label
    }()

    private let amountLabel: UILabel = {
        let label = UILabel()
        label.font = .systemFont(ofSize: 16, weight: .bold)
        label.textColor = Constants.Colors.primary
        label.translatesAutoresizingMaskIntoConstraints = false
        return label
    }()

    private init(coins: Int) {
        super.init(frame: .zero)
        translatesAutoresizingMaskIntoConstraints = false
        backgroundColor = Constants.Colors.background
        layer.cornerRadius = 22
        layer.shadowColor = UIColor.black.cgColor
        layer.shadowOpacity = 0.18
        layer.shadowRadius = 10
        layer.shadowOffset = CGSize(width: 0, height: 4)
        isUserInteractionEnabled = false

        amountLabel.text = "+\(coins) FavCoins"
        addSubview(piggyLabel)
        addSubview(amountLabel)
        addSubview(coinLabel)

        NSLayoutConstraint.activate([
            piggyLabel.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 14),
            piggyLabel.topAnchor.constraint(equalTo: topAnchor, constant: 6),
            piggyLabel.bottomAnchor.constraint(equalTo: bottomAnchor, constant: -6),
            amountLabel.leadingAnchor.constraint(equalTo: piggyLabel.trailingAnchor, constant: 10),
            amountLabel.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -16),
            amountLabel.centerYAnchor.constraint(equalTo: centerYAnchor),
            // Coin starts above the piggy, drops "into" it
            coinLabel.centerXAnchor.constraint(equalTo: piggyLabel.centerXAnchor),
            coinLabel.centerYAnchor.constraint(equalTo: piggyLabel.topAnchor, constant: -6)
        ])
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    private func animateIn() {
        alpha = 0
        transform = CGAffineTransform(translationX: 0, y: -16)
        coinLabel.alpha = 0

        UIView.animate(withDuration: 0.25, delay: 0, options: [.curveEaseOut], animations: {
            self.alpha = 1
            self.transform = .identity
        })

        // Coin drop: appear above the piggy, fall in, vanish behind it.
        UIView.animateKeyframes(withDuration: 0.7, delay: 0.15, options: []) {
            UIView.addKeyframe(withRelativeStartTime: 0, relativeDuration: 0.25) {
                self.coinLabel.alpha = 1
            }
            UIView.addKeyframe(withRelativeStartTime: 0.25, relativeDuration: 0.55) {
                self.coinLabel.transform = CGAffineTransform(translationX: 0, y: 22)
                    .scaledBy(x: 0.5, y: 0.5)
                self.coinLabel.alpha = 0
            }
        }

        // Piggy wiggle on receipt
        UIView.animateKeyframes(withDuration: 0.3, delay: 0.75, options: []) {
            UIView.addKeyframe(withRelativeStartTime: 0, relativeDuration: 0.5) {
                self.piggyLabel.transform = CGAffineTransform(scaleX: 1.15, y: 1.15)
            }
            UIView.addKeyframe(withRelativeStartTime: 0.5, relativeDuration: 0.5) {
                self.piggyLabel.transform = .identity
            }
        }

        // Gone by ~1.7s, no interaction required.
        UIView.animate(withDuration: 0.3, delay: 1.4, options: [.curveEaseIn], animations: {
            self.alpha = 0
            self.transform = CGAffineTransform(translationX: 0, y: -12)
        }, completion: { _ in
            self.removeFromSuperview()
            if PiggyBankDepositView.activeView === self { PiggyBankDepositView.activeView = nil }
        })
    }
}

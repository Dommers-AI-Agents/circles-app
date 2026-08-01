import UIKit

/// The coin-into-the-piggy-bank deposit moment. A window-level celebration
/// card, centered on screen (~3s, non-blocking, survives navigation): a
/// FavCoin drops into the piggy bank, the piggy bounces, and "+N FavCoins"
/// pops in. Deliberately playful and deliberately value-free — coins, not
/// currency.
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
            view.centerXAnchor.constraint(equalTo: window.centerXAnchor),
            view.centerYAnchor.constraint(equalTo: window.centerYAnchor),
            view.widthAnchor.constraint(equalToConstant: 240)
        ])
        view.animateIn()
    }

    private let piggyLabel: UILabel = {
        let label = UILabel()
        label.text = "🐷"
        label.font = .systemFont(ofSize: 88)
        label.textAlignment = .center
        label.translatesAutoresizingMaskIntoConstraints = false
        return label
    }()

    private let coinLabel: UILabel = {
        let label = UILabel()
        label.text = "🪙"
        label.font = .systemFont(ofSize: 44)
        label.textAlignment = .center
        label.translatesAutoresizingMaskIntoConstraints = false
        return label
    }()

    private let amountLabel: UILabel = {
        let label = UILabel()
        label.font = .systemFont(ofSize: 26, weight: .heavy)
        label.textColor = Constants.Colors.primary
        label.textAlignment = .center
        label.translatesAutoresizingMaskIntoConstraints = false
        return label
    }()

    private init(coins: Int) {
        super.init(frame: .zero)
        translatesAutoresizingMaskIntoConstraints = false
        backgroundColor = Constants.Colors.background
        layer.cornerRadius = 28
        layer.shadowColor = UIColor.black.cgColor
        layer.shadowOpacity = 0.25
        layer.shadowRadius = 18
        layer.shadowOffset = CGSize(width: 0, height: 8)
        // Never blocks a tap — the celebration floats over whatever the user
        // is doing next.
        isUserInteractionEnabled = false

        amountLabel.text = "+\(coins) FavCoins"
        addSubview(piggyLabel)
        addSubview(amountLabel)
        addSubview(coinLabel)

        NSLayoutConstraint.activate([
            // Room above the piggy for the coin's drop arc
            piggyLabel.topAnchor.constraint(equalTo: topAnchor, constant: 56),
            piggyLabel.centerXAnchor.constraint(equalTo: centerXAnchor),

            amountLabel.topAnchor.constraint(equalTo: piggyLabel.bottomAnchor, constant: 10),
            amountLabel.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 12),
            amountLabel.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -12),
            amountLabel.bottomAnchor.constraint(equalTo: bottomAnchor, constant: -22),

            // Coin starts high above the piggy, falls "into" it
            coinLabel.centerXAnchor.constraint(equalTo: piggyLabel.centerXAnchor),
            coinLabel.centerYAnchor.constraint(equalTo: piggyLabel.topAnchor, constant: -18)
        ])
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    private func animateIn() {
        alpha = 0
        transform = CGAffineTransform(scaleX: 0.7, y: 0.7)
        coinLabel.alpha = 0
        amountLabel.alpha = 0
        amountLabel.transform = CGAffineTransform(scaleX: 0.6, y: 0.6)

        // Card pops in
        UIView.animate(withDuration: 0.35, delay: 0, usingSpringWithDamping: 0.7,
                       initialSpringVelocity: 0.5, options: [], animations: {
            self.alpha = 1
            self.transform = .identity
        })

        // Coin drop: appear high, fall into the piggy, vanish behind it
        UIView.animateKeyframes(withDuration: 1.1, delay: 0.3, options: []) {
            UIView.addKeyframe(withRelativeStartTime: 0, relativeDuration: 0.25) {
                self.coinLabel.alpha = 1
            }
            UIView.addKeyframe(withRelativeStartTime: 0.3, relativeDuration: 0.7) {
                self.coinLabel.transform = CGAffineTransform(translationX: 0, y: 64)
                    .scaledBy(x: 0.45, y: 0.45)
                self.coinLabel.alpha = 0
            }
        }

        // Piggy bounces on receipt
        UIView.animateKeyframes(withDuration: 0.5, delay: 1.25, options: []) {
            UIView.addKeyframe(withRelativeStartTime: 0, relativeDuration: 0.4) {
                self.piggyLabel.transform = CGAffineTransform(scaleX: 1.22, y: 1.22)
            }
            UIView.addKeyframe(withRelativeStartTime: 0.4, relativeDuration: 0.6) {
                self.piggyLabel.transform = .identity
            }
        }

        // "+N FavCoins" pops as the piggy bounces
        UIView.animate(withDuration: 0.4, delay: 1.3, usingSpringWithDamping: 0.6,
                       initialSpringVelocity: 0.6, options: [], animations: {
            self.amountLabel.alpha = 1
            self.amountLabel.transform = .identity
        })

        // Linger, then float away (~3.2s total on screen)
        UIView.animate(withDuration: 0.45, delay: 2.75, options: [.curveEaseIn], animations: {
            self.alpha = 0
            self.transform = CGAffineTransform(translationX: 0, y: -24).scaledBy(x: 0.9, y: 0.9)
        }, completion: { _ in
            self.removeFromSuperview()
            if PiggyBankDepositView.activeView === self { PiggyBankDepositView.activeView = nil }
        })
    }
}

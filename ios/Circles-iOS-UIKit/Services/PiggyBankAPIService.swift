import Foundation

/// FavCoin piggy bank API. Earning happens server-side on the actions
/// themselves; this covers reads plus Phase 4 claiming (wallet linking and
/// sending confirmed coins on-chain).
final class PiggyBankAPIService {
    static let shared = PiggyBankAPIService()
    private init() {}

    func getPiggyBank(completion: @escaping (Result<PiggyBankResponse, Error>) -> Void) {
        APIService.shared.request(
            endpoint: "piggy-bank",
            method: .get,
            requiresAuth: true
        ) { (result: Result<PiggyBankResponse, APIError>) in
            switch result {
            case .success(let response): completion(.success(response))
            case .failure(let error): completion(.failure(error))
            }
        }
    }

    func getHistory(before: String?, completion: @escaping (Result<[PiggyLedgerEvent], Error>) -> Void) {
        var endpoint = "piggy-bank/history"
        if let before = before,
           let encoded = before.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) {
            endpoint += "?before=\(encoded)"
        }
        APIService.shared.request(
            endpoint: endpoint,
            method: .get,
            requiresAuth: true
        ) { (result: Result<PiggyBankHistoryResponse, APIError>) in
            switch result {
            case .success(let response): completion(.success(response.events))
            case .failure(let error): completion(.failure(error))
            }
        }
    }

    /// Link (or replace) the user's self-custody Cactus wallet address.
    func linkWallet(address: String, completion: @escaping (Result<String, Error>) -> Void) {
        APIService.shared.request(
            endpoint: "piggy-bank/wallet",
            method: .post,
            body: ["address": address],
            requiresAuth: true
        ) { (result: Result<PiggyLinkWalletResponse, APIError>) in
            switch result {
            case .success(let response): completion(.success(response.walletAddress))
            case .failure(let error): completion(.failure(error))
            }
        }
    }

    /// Claim the entire confirmed balance to the linked wallet.
    func claim(completion: @escaping (Result<PiggyActiveClaim, Error>) -> Void) {
        APIService.shared.request(
            endpoint: "piggy-bank/claim",
            method: .post,
            body: [:],
            requiresAuth: true
        ) { (result: Result<PiggyClaimResponse, APIError>) in
            switch result {
            case .success(let response): completion(.success(response.claim))
            case .failure(let error): completion(.failure(error))
            }
        }
    }
}

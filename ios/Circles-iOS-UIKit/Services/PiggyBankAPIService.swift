import Foundation

/// FavCoin piggy bank API. Reads only — earning happens server-side on the
/// actions themselves, and claiming is a future phase.
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
}

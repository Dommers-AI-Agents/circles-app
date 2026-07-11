import Foundation

// MARK: - API Response Models

struct ImportPreviewPlace: Decodable {
    let name: String
    let address: String?
    let lat: Double?
    let lng: Double?
    let category: String?
    let notes: String?
    let tags: [String]?
    let sourceExternalId: String?
    let sourceUrl: String?
    let googlePlaceId: String?
    let status: String // "new" | "duplicate" | "unresolved"
    let duplicateOf: ImportDuplicateRef?

    var isNew: Bool { status == "new" }
    var isDuplicate: Bool { status == "duplicate" }
    var isUnresolved: Bool { status == "unresolved" }

    /// Body for POST /api/import/execute — echoes back the resolved place.
    var asExecuteBody: [String: Any] {
        var body: [String: Any] = ["name": name]
        if let address = address { body["address"] = address }
        if let lat = lat { body["lat"] = lat }
        if let lng = lng { body["lng"] = lng }
        if let category = category { body["category"] = category }
        if let notes = notes { body["notes"] = notes }
        if let tags = tags, !tags.isEmpty { body["tags"] = tags }
        if let sourceExternalId = sourceExternalId { body["sourceExternalId"] = sourceExternalId }
        if let sourceUrl = sourceUrl { body["sourceUrl"] = sourceUrl }
        if let googlePlaceId = googlePlaceId { body["googlePlaceId"] = googlePlaceId }
        return body
    }
}

struct ImportDuplicateRef: Decodable {
    let placeId: String?
    let circleId: String?
}

struct ImportPreviewList: Decodable {
    let proposedCircleName: String
    let existingCircleId: String?
    let places: [ImportPreviewPlace]
}

struct ImportCounts: Decodable {
    let new: Int
    let duplicate: Int
    let unresolved: Int
}

struct ImportPreview: Decodable {
    let lists: [ImportPreviewList]
    let counts: ImportCounts
}

private struct ImportPrepareResponse: Decodable {
    let success: Bool
    let preview: ImportPreview
}

struct ImportExecuteListResult: Decodable {
    let circleId: String?
    let circleName: String
    let created: Int
    let skippedDuplicates: Int
    let failed: [ImportExecuteFailure]
}

struct ImportExecuteFailure: Decodable {
    let name: String
    let reason: String
}

struct ImportTotals: Decodable {
    let created: Int
    let skippedDuplicates: Int
    let failed: Int
}

private struct ImportExecuteResponse: Decodable {
    let success: Bool
    let results: [ImportExecuteListResult]
    let totals: ImportTotals
}

/// Aggregated outcome across all execute calls of one import run.
struct ImportRunSummary {
    var created = 0
    var skippedDuplicates = 0
    var failures: [ImportExecuteFailure] = []
    var circleNames: [String] = []
}

// MARK: - Import Service

/// Client for the /api/import endpoints. Chunks large imports so each
/// request stays under the backend's per-call place cap.
final class ImportService {

    static let shared = ImportService()
    private init() {}

    /// Keep in sync with MAX_PLACES_PER_REQUEST in backend/services/importService.js
    static let maxPlacesPerRequest = 300

    // MARK: Prepare

    /// Resolve + dedup parsed lists into a reviewable preview. Each list is
    /// sent separately (sliced to the cap) so progress is reportable and no
    /// single request exceeds the backend limit.
    func prepare(
        source: ImportSource,
        lists: [ImportList],
        progress: @escaping (String) -> Void,
        completion: @escaping (Result<ImportPreview, Error>) -> Void
    ) {
        // Build (list, slice) work items up front
        var workItems: [(name: String, places: [ImportPlaceCandidate])] = []
        for list in lists {
            let slices = stride(from: 0, to: list.places.count, by: Self.maxPlacesPerRequest).map {
                Array(list.places[$0..<min($0 + Self.maxPlacesPerRequest, list.places.count)])
            }
            for slice in slices {
                workItems.append((name: list.name, places: slice))
            }
        }

        var mergedLists: [ImportPreviewList] = []
        var counts = (new: 0, duplicate: 0, unresolved: 0)

        func processNext(_ index: Int) {
            guard index < workItems.count else {
                // Merge slices that belong to the same list back together
                var byName: [String: ImportPreviewList] = [:]
                var order: [String] = []
                for list in mergedLists {
                    if let existing = byName[list.proposedCircleName] {
                        byName[list.proposedCircleName] = ImportPreviewList(
                            proposedCircleName: existing.proposedCircleName,
                            existingCircleId: existing.existingCircleId,
                            places: existing.places + list.places
                        )
                    } else {
                        byName[list.proposedCircleName] = list
                        order.append(list.proposedCircleName)
                    }
                }
                let preview = ImportPreview(
                    lists: order.compactMap { byName[$0] },
                    counts: ImportCounts(new: counts.new, duplicate: counts.duplicate, unresolved: counts.unresolved)
                )
                completion(.success(preview))
                return
            }

            let item = workItems[index]
            progress("Preparing \(item.name) (\(index + 1) of \(workItems.count))…")

            let body: [String: Any] = [
                "source": source.rawValue,
                "lists": [["name": item.name, "places": item.places.map { $0.asRequestBody }]]
            ]

            APIService.shared.request(
                endpoint: "import/prepare",
                method: .post,
                body: body,
                requiresAuth: true
            ) { (result: Result<ImportPrepareResponse, APIError>) in
                switch result {
                case .success(let response):
                    mergedLists.append(contentsOf: response.preview.lists)
                    counts.new += response.preview.counts.new
                    counts.duplicate += response.preview.counts.duplicate
                    counts.unresolved += response.preview.counts.unresolved
                    processNext(index + 1)
                case .failure(let error):
                    completion(.failure(error))
                }
            }
        }

        processNext(0)
    }

    // MARK: Execute

    struct ExecuteList {
        let circleName: String
        var existingCircleId: String?
        let places: [ImportPreviewPlace]
    }

    /// Create circles + places. Lists run sequentially; when a list is larger
    /// than the per-request cap, the first slice creates the circle and later
    /// slices target it via existingCircleId.
    func execute(
        source: ImportSource,
        lists: [ExecuteList],
        progress: @escaping (String) -> Void,
        completion: @escaping (Result<ImportRunSummary, Error>) -> Void
    ) {
        var summary = ImportRunSummary()
        var remaining = lists.filter { !$0.places.isEmpty }

        func processNextList() {
            guard !remaining.isEmpty else {
                completion(.success(summary))
                return
            }
            var list = remaining.removeFirst()

            let slices = stride(from: 0, to: list.places.count, by: Self.maxPlacesPerRequest).map {
                Array(list.places[$0..<min($0 + Self.maxPlacesPerRequest, list.places.count)])
            }

            func processSlice(_ sliceIndex: Int) {
                guard sliceIndex < slices.count else {
                    processNextList()
                    return
                }
                progress("Importing \(list.circleName)…")

                var listBody: [String: Any] = [
                    "circleName": list.circleName,
                    "places": slices[sliceIndex].map { $0.asExecuteBody }
                ]
                if let existingCircleId = list.existingCircleId {
                    listBody["existingCircleId"] = existingCircleId
                }

                let body: [String: Any] = ["source": source.rawValue, "lists": [listBody]]

                APIService.shared.request(
                    endpoint: "import/execute",
                    method: .post,
                    body: body,
                    requiresAuth: true
                ) { (result: Result<ImportExecuteResponse, APIError>) in
                    switch result {
                    case .success(let response):
                        if let listResult = response.results.first {
                            summary.created += listResult.created
                            summary.skippedDuplicates += listResult.skippedDuplicates
                            summary.failures.append(contentsOf: listResult.failed)
                            if sliceIndex == 0, listResult.created > 0 || listResult.circleId != nil {
                                summary.circleNames.append(listResult.circleName)
                            }
                            // Later slices of this list must append to the
                            // circle the first slice created
                            if list.existingCircleId == nil {
                                list.existingCircleId = listResult.circleId
                            }
                        }
                        processSlice(sliceIndex + 1)
                    case .failure(let error):
                        completion(.failure(error))
                    }
                }
            }

            processSlice(0)
        }

        processNextList()
    }
}

import UIKit
import Foundation

// Response models, FollowListType, and the StatView subview used by
// ProfileViewController. Extracted from the controller file (Wave 4).

// MARK: - Response Types
struct UserCirclesResponse: Codable {
    let success: Bool
    let data: UserCirclesData
}

struct UserCirclesData: Codable {
    let user: User
    let circles: [Circle]
}

struct FollowResponse: Codable {
    let success: Bool
    let message: String
    let user: User?
}

// MARK: - FollowListType
enum FollowListType {
    case followers
    case following
}

// MARK: - StatView
class StatView: UIView {
    let numberLabel: UILabel = {
        let label = UILabel()
        label.font = UIFont.systemFont(ofSize: 18, weight: .semibold)
        label.textColor = Constants.Colors.label
        label.textAlignment = .center
        label.translatesAutoresizingMaskIntoConstraints = false
        return label
    }()
    
    let titleLabel: UILabel = {
        let label = UILabel()
        label.font = UIFont.systemFont(ofSize: 14)
        label.textColor = Constants.Colors.label
        label.textAlignment = .center
        label.translatesAutoresizingMaskIntoConstraints = false
        return label
    }()
    
    override init(frame: CGRect) {
        super.init(frame: frame)
        setupView()
    }
    
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }
    
    func setupView() {
        addSubview(numberLabel)
        addSubview(titleLabel)
        
        NSLayoutConstraint.activate([
            numberLabel.topAnchor.constraint(equalTo: topAnchor),
            numberLabel.leadingAnchor.constraint(equalTo: leadingAnchor),
            numberLabel.trailingAnchor.constraint(equalTo: trailingAnchor),
            
            titleLabel.topAnchor.constraint(equalTo: numberLabel.bottomAnchor, constant: 2),
            titleLabel.leadingAnchor.constraint(equalTo: leadingAnchor),
            titleLabel.trailingAnchor.constraint(equalTo: trailingAnchor),
            titleLabel.bottomAnchor.constraint(equalTo: bottomAnchor)
        ])
    }
    
    func configure(number: String, title: String) {
        numberLabel.text = number
        titleLabel.text = title
    }
}

// MARK: - Uploads grouped by place

/// One place's worth of uploaded photos, for the grouped Uploads grid
/// (one tile per place → tap to expand into that place's gallery).
struct UploadPlaceGroup {
    let placeId: String
    let placeName: String
    let placeCategory: PlaceCategory
    let placeAddress: String?
    let photos: [UserUploadedPhoto]   // newest first

    var cover: UserUploadedPhoto { photos[0] }
    var count: Int { photos.count }
}

extension Array where Element == UserUploadedPhoto {
    /// Groups uploads by place, preserving the order places first appear in
    /// the source array (server returns newest-first). Cover is the newest
    /// photo for each place.
    func groupedByPlace() -> [UploadPlaceGroup] {
        var order: [String] = []
        var byPlace: [String: [UserUploadedPhoto]] = [:]
        for photo in self {
            if byPlace[photo.placeId] == nil {
                order.append(photo.placeId)
                byPlace[photo.placeId] = []
            }
            byPlace[photo.placeId]?.append(photo)
        }
        return order.compactMap { placeId in
            guard let photos = byPlace[placeId], let first = photos.first else { return nil }
            let sorted = photos.sorted { $0.uploadedAt > $1.uploadedAt }
            return UploadPlaceGroup(
                placeId: placeId,
                placeName: first.placeName,
                placeCategory: first.placeCategory,
                placeAddress: first.placeAddress,
                photos: sorted
            )
        }
    }
}

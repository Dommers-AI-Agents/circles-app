import Foundation
import UIKit

// MARK: - CircleDisplayItem
/// Represents either an individual circle or a circle group for display in collection views
enum CircleDisplayItem {
    case circle(Circle)
    case group(CircleGroup)
    
    // MARK: - Common Properties
    
    var id: String {
        switch self {
        case .circle(let circle):
            return circle.id
        case .group(let group):
            return group.id
        }
    }
    
    var name: String {
        switch self {
        case .circle(let circle):
            return circle.name
        case .group(let group):
            return group.name
        }
    }
    
    var owner: String {
        switch self {
        case .circle(let circle):
            return circle.owner
        case .group(let group):
            return group.owner
        }
    }
    
    var isOwnedByCurrentUser: Bool {
        switch self {
        case .circle(let circle):
            return circle.isOwner
        case .group(let group):
            return group.isOwnedByCurrentUser
        }
    }
    
    var privacy: PrivacyLevel {
        switch self {
        case .circle(let circle):
            return circle.privacy
        case .group(let group):
            return group.privacy
        }
    }
    
    var createdAt: Date {
        switch self {
        case .circle(let circle):
            return circle.createdAt
        case .group(let group):
            return group.createdAt
        }
    }
    
    // MARK: - Type Checking
    
    var isCircle: Bool {
        switch self {
        case .circle:
            return true
        case .group:
            return false
        }
    }
    
    var isGroup: Bool {
        switch self {
        case .circle:
            return false
        case .group:
            return true
        }
    }
    
    // MARK: - Extract Values
    
    var circle: Circle? {
        switch self {
        case .circle(let circle):
            return circle
        case .group:
            return nil
        }
    }
    
    var group: CircleGroup? {
        switch self {
        case .circle:
            return nil
        case .group(let group):
            return group
        }
    }
}

// MARK: - Array Extensions

extension Array where Element == CircleDisplayItem {
    
    /// Filter to get only circles
    var circles: [Circle] {
        return compactMap { item in
            switch item {
            case .circle(let circle):
                return circle
            case .group:
                return nil
            }
        }
    }
    
    /// Filter to get only groups
    var groups: [CircleGroup] {
        return compactMap { item in
            switch item {
            case .circle:
                return nil
            case .group(let group):
                return group
            }
        }
    }
    
    /// Create display items from circles and groups
    static func createFrom(circles: [Circle], groups: [CircleGroup]) -> [CircleDisplayItem] {
        var items: [CircleDisplayItem] = []
        
        // Add groups first (preserving their order)
        items.append(contentsOf: groups.map { .group($0) })
        
        // Add ungrouped circles (preserving their order from the API)
        let ungroupedCircles = circles.filter { $0.groupId == nil }
        items.append(contentsOf: ungroupedCircles.map { .circle($0) })
        
        // Return items in the order they were provided (no sorting)
        // The backend already returns circles in the user's custom order
        return items
    }
}

// MARK: - Drag & Drop Support

extension CircleDisplayItem {
    
    /// Create a drag item for UIKit drag and drop
    func createDragItem() -> UIDragItem {
        let itemProvider: NSItemProvider
        
        switch self {
        case .circle(let circle):
            itemProvider = NSItemProvider(object: circle.id as NSString)
            itemProvider.suggestedName = "circle-\(circle.id)"
        case .group(let group):
            itemProvider = NSItemProvider(object: group.id as NSString)
            itemProvider.suggestedName = "group-\(group.id)"
        }
        
        let dragItem = UIDragItem(itemProvider: itemProvider)
        dragItem.localObject = self
        return dragItem
    }
    
    /// Extract display item from a drop session
    static func fromDropSession(_ session: UIDropSession) -> CircleDisplayItem? {
        guard let dragItem = session.items.first,
              let displayItem = dragItem.localObject as? CircleDisplayItem else {
            return nil
        }
        return displayItem
    }
}

// MARK: - Equatable

extension CircleDisplayItem: Equatable {
    static func == (lhs: CircleDisplayItem, rhs: CircleDisplayItem) -> Bool {
        return lhs.id == rhs.id
    }
}

// MARK: - Hashable

extension CircleDisplayItem: Hashable {
    func hash(into hasher: inout Hasher) {
        hasher.combine(id)
        hasher.combine(isGroup)
    }
}
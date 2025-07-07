import Foundation
import MapKit
import UIKit
import CoreLocation

@available(iOS 16.0, *)
class AppleLookAroundService {
    static let shared = AppleLookAroundService()
    
    private init() {}
    
    // MARK: - Check Look Around Availability
    
    func checkLookAroundAvailability(at coordinate: CLLocationCoordinate2D) async -> Bool {
        do {
            let scene = try await MKLookAroundSceneRequest(coordinate: coordinate).scene
            return scene != nil
        } catch {
            return false
        }
    }
    
    // MARK: - Get Look Around Snapshot
    
    func getLookAroundSnapshot(
        at coordinate: CLLocationCoordinate2D,
        size: CGSize = CGSize(width: 600, height: 400)
    ) async throws -> UIImage {
        // Get the scene using async/await
        guard let scene = try await MKLookAroundSceneRequest(coordinate: coordinate).scene else {
            throw LookAroundError.sceneNotAvailable
        }
        
        // Create snapshot options
        let snapshotOptions = MKLookAroundSnapshotter.Options()
        snapshotOptions.size = size
        
        // You can adjust the field of view and pitch
        // snapshotOptions.fieldOfView = 90
        // snapshotOptions.pitch = 0
        
        // Create snapshotter and get the snapshot using async
        let snapshotter = MKLookAroundSnapshotter(scene: scene, options: snapshotOptions)
        let snapshot = try await snapshotter.snapshot
        
        return snapshot.image
    }
    
    // MARK: - Get Look Around View Controller
    
    func getLookAroundViewController(at coordinate: CLLocationCoordinate2D) async throws -> MKLookAroundViewController {
        guard let scene = try await MKLookAroundSceneRequest(coordinate: coordinate).scene else {
            throw LookAroundError.sceneNotAvailable
        }
        
        return MKLookAroundViewController(scene: scene)
    }
}

// MARK: - Errors

enum LookAroundError: LocalizedError {
    case sceneNotAvailable
    case snapshotFailed
    
    var errorDescription: String? {
        switch self {
        case .sceneNotAvailable:
            return "Look Around is not available at this location"
        case .snapshotFailed:
            return "Failed to capture Look Around snapshot"
        }
    }
}
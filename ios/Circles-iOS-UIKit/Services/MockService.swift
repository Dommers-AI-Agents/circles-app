import Foundation
import CoreLocation

/// Service that provides mock data for testing the app without a backend
class MockService {
    static let shared = MockService()
    
    private var currentUserId = "user_1001"
    private var users: [User] = []
    private var circles: [Circle] = []
    private var places: [Place] = []
    private var friendRequests: [FriendRequest] = []
    
    private init() {
        generateMockData()
    }
    
    // MARK: - Data Generation
    
    private func generateMockData() {
        // Create mock users
        users = [
            User(
                id: "user_1001",
                email: "john@example.com",
                displayName: "John Smith",
                profilePicture: nil,
                bio: "Travel enthusiast and food lover. Always searching for the next great adventure.",
                location: "New York, NY",
                friends: ["user_1002", "user_1003"],
                friendRequests: [],
                createdAt: Date().addingTimeInterval(-86400 * 30) // 30 days ago
            ),
            User(
                id: "user_1002",
                email: "emma@example.com",
                displayName: "Emma Johnson",
                profilePicture: nil,
                bio: "Food critic and restaurant finder. Let me guide you to your next favorite meal!",
                location: "Los Angeles, CA",
                friends: ["user_1001"],
                friendRequests: [],
                createdAt: Date().addingTimeInterval(-86400 * 45) // 45 days ago
            ),
            User(
                id: "user_1003",
                email: "mike@example.com",
                displayName: "Mike Chen",
                profilePicture: nil,
                bio: "Professional photographer and urban explorer. I find the hidden gems in every city.",
                location: "San Francisco, CA",
                friends: ["user_1001"],
                friendRequests: [],
                createdAt: Date().addingTimeInterval(-86400 * 60) // 60 days ago
            ),
            User(
                id: "user_1004",
                email: "sarah@example.com",
                displayName: "Sarah Williams",
                profilePicture: nil,
                bio: "Travel blogger and adventure seeker. Follow me for the best tips on worldwide destinations!",
                location: "Chicago, IL",
                friends: [],
                friendRequests: [],
                createdAt: Date().addingTimeInterval(-86400 * 20) // 20 days ago
            ),
            User(
                id: "user_1005",
                email: "alex@example.com",
                displayName: "Alex Garcia",
                profilePicture: nil,
                bio: "Coffee connoisseur and cafe explorer. I've tried over 500 cafes worldwide.",
                location: "Seattle, WA",
                friends: [],
                friendRequests: [],
                createdAt: Date().addingTimeInterval(-86400 * 15) // 15 days ago
            )
        ]
        
        // Create mock circles
        circles = [
            Circle(
                id: "circle_1001",
                name: "NYC Food Tour",
                description: "My favorite restaurants in New York City",
                coverImage: nil,
                owner: "user_1001",
                ownerDetails: nil,
                editors: nil,
                editorsDetails: nil,
                places: ["place_1001", "place_1002", "place_1003"],
                placesCount: 3,
                placesWithDetails: nil,
                privacy: .public,
                allowNetworkEdit: false,
                category: .food,
                location: "New York, NY",
                tags: ["food", "nyc", "restaurants"],
                sharedWith: ["user_1002"],
                followers: ["user_1003", "user_1004"],
                activeShares: nil,
                shareSettings: nil,
                isSharedWithMe: false,
                sharedBy: nil,
                myAccessLevel: nil,
                createdAt: Date().addingTimeInterval(-86400 * 10), // 10 days ago
                updatedAt: Date().addingTimeInterval(-86400 * 2) // 2 days ago
            ),
            Circle(
                id: "circle_1002",
                name: "SF Coffee Shops",
                description: "Best cafes in San Francisco",
                coverImage: nil,
                owner: "user_1001",
                ownerDetails: nil,
                editors: nil,
                editorsDetails: nil,
                places: ["place_1004", "place_1005"],
                placesCount: 2,
                placesWithDetails: nil,
                privacy: .myNetwork,
                allowNetworkEdit: true,
                category: .food,
                location: "San Francisco, CA",
                tags: ["coffee", "cafe", "sf"],
                sharedWith: ["user_1003"],
                followers: [],
                activeShares: nil,
                shareSettings: nil,
                isSharedWithMe: false,
                sharedBy: nil,
                myAccessLevel: nil,
                createdAt: Date().addingTimeInterval(-86400 * 20), // 20 days ago
                updatedAt: Date().addingTimeInterval(-86400 * 5) // 5 days ago
            ),
            Circle(
                id: "circle_1003",
                name: "LA Shopping",
                description: "My favorite shopping spots in Los Angeles",
                coverImage: nil,
                owner: "user_1002",
                ownerDetails: nil,
                editors: nil,
                editorsDetails: nil,
                places: ["place_1006", "place_1007", "place_1008"],
                placesCount: 3,
                placesWithDetails: nil,
                privacy: .public,
                allowNetworkEdit: false,
                category: .shopping,
                location: "Los Angeles, CA",
                tags: ["shopping", "la", "fashion"],
                sharedWith: [],
                followers: ["user_1001", "user_1005"],
                activeShares: nil,
                shareSettings: nil,
                isSharedWithMe: false,
                sharedBy: nil,
                myAccessLevel: nil,
                createdAt: Date().addingTimeInterval(-86400 * 15), // 15 days ago
                updatedAt: Date().addingTimeInterval(-86400 * 3) // 3 days ago
            ),
            Circle(
                id: "circle_1004",
                name: "Chicago Entertainment",
                description: "Best entertainment venues in Chicago",
                coverImage: nil,
                owner: "user_1004",
                ownerDetails: nil,
                editors: nil,
                editorsDetails: nil,
                places: ["place_1009", "place_1010", "place_1011"],
                placesCount: 3,
                placesWithDetails: nil,
                privacy: .public,
                allowNetworkEdit: false,
                category: .entertainment,
                location: "Chicago, IL",
                tags: ["entertainment", "chicago", "music", "theater"],
                sharedWith: [],
                followers: ["user_1001", "user_1003"],
                activeShares: nil,
                shareSettings: nil,
                isSharedWithMe: false,
                sharedBy: nil,
                myAccessLevel: nil,
                createdAt: Date().addingTimeInterval(-86400 * 8), // 8 days ago
                updatedAt: Date().addingTimeInterval(-86400 * 1) // 1 day ago
            ),
            Circle(
                id: "circle_1005",
                name: "Seattle Coffee Tour",
                description: "The ultimate guide to Seattle's best coffee",
                coverImage: nil,
                owner: "user_1005",
                ownerDetails: nil,
                editors: nil,
                editorsDetails: nil,
                places: ["place_1012", "place_1013", "place_1014"],
                placesCount: 3,
                placesWithDetails: nil,
                privacy: .public,
                allowNetworkEdit: false,
                category: .food,
                location: "Seattle, WA",
                tags: ["coffee", "seattle", "cafes"],
                sharedWith: [],
                followers: ["user_1002", "user_1003"],
                activeShares: nil,
                shareSettings: nil,
                isSharedWithMe: false,
                sharedBy: nil,
                myAccessLevel: nil,
                createdAt: Date().addingTimeInterval(-86400 * 5), // 5 days ago
                updatedAt: Date() // today
            )
        ]
        
        // Create mock places
        places = [
            // NYC Food Tour places
            createPlace(
                id: "place_1001",
                name: "Le Bernardin",
                description: "High-end seafood restaurant with award-winning cuisine",
                address: "155 W 51st St, New York, NY 10019",
                lat: 40.7614, lon: -73.9818,
                category: .restaurant,
                circleId: "circle_1001",
                priceLevel: .veryExpensive
            ),
            createPlace(
                id: "place_1002",
                name: "Katz's Delicatessen",
                description: "Iconic deli serving massive sandwiches since 1888",
                address: "205 E Houston St, New York, NY 10002",
                lat: 40.7223, lon: -73.9874,
                category: .restaurant,
                circleId: "circle_1001",
                priceLevel: .moderate
            ),
            createPlace(
                id: "place_1003",
                name: "Levain Bakery",
                description: "Famous for their giant cookies and baked goods",
                address: "167 W 74th St, New York, NY 10023",
                lat: 40.7801, lon: -73.9813,
                category: .cafe,
                circleId: "circle_1001",
                priceLevel: .moderate
            ),
            
            // SF Coffee Shops places
            createPlace(
                id: "place_1004",
                name: "Blue Bottle Coffee",
                description: "Premium coffee roaster with minimalist aesthetic",
                address: "66 Mint St, San Francisco, CA 94103",
                lat: 37.7823, lon: -122.4071,
                category: .cafe,
                circleId: "circle_1002",
                priceLevel: .moderate
            ),
            createPlace(
                id: "place_1005",
                name: "Ritual Coffee Roasters",
                description: "Local favorite with exceptional single-origin coffees",
                address: "1026 Valencia St, San Francisco, CA 94110",
                lat: 37.7564, lon: -122.4213,
                category: .cafe,
                circleId: "circle_1002",
                priceLevel: .moderate
            ),
            
            // LA Shopping places
            createPlace(
                id: "place_1006",
                name: "The Grove",
                description: "Popular outdoor shopping and entertainment complex",
                address: "189 The Grove Dr, Los Angeles, CA 90036",
                lat: 34.0720, lon: -118.3578,
                category: .retail,
                circleId: "circle_1003",
                priceLevel: .expensive
            ),
            createPlace(
                id: "place_1007",
                name: "Rodeo Drive",
                description: "Luxury shopping district with high-end designer boutiques",
                address: "Rodeo Dr, Beverly Hills, CA 90210",
                lat: 34.0697, lon: -118.4032,
                category: .retail,
                circleId: "circle_1003",
                priceLevel: .veryExpensive
            ),
            createPlace(
                id: "place_1008",
                name: "Melrose Trading Post",
                description: "Trendy Sunday flea market with unique items",
                address: "7850 Melrose Ave, Los Angeles, CA 90046",
                lat: 34.0841, lon: -118.3622,
                category: .retail,
                circleId: "circle_1003",
                priceLevel: .inexpensive
            ),
            
            // Chicago Entertainment places
            createPlace(
                id: "place_1009",
                name: "Chicago Theatre",
                description: "Historic landmark venue for live performances",
                address: "175 N State St, Chicago, IL 60601",
                lat: 41.8854, lon: -87.6275,
                category: .entertainment,
                circleId: "circle_1004",
                priceLevel: .expensive
            ),
            createPlace(
                id: "place_1010",
                name: "The Second City",
                description: "Legendary comedy club that launched many famous careers",
                address: "1616 N Wells St, Chicago, IL 60614",
                lat: 41.9101, lon: -87.6368,
                category: .entertainment,
                circleId: "circle_1004",
                priceLevel: .moderate
            ),
            createPlace(
                id: "place_1011",
                name: "Kingston Mines",
                description: "Iconic blues club with nightly live music",
                address: "2548 N Halsted St, Chicago, IL 60614",
                lat: 41.9292, lon: -87.6493,
                category: .entertainment,
                circleId: "circle_1004",
                priceLevel: .moderate
            ),
            
            // Seattle Coffee Tour places
            createPlace(
                id: "place_1012",
                name: "Starbucks Reserve Roastery",
                description: "Premium Starbucks experience with exclusive coffees",
                address: "1124 Pike St, Seattle, WA 98101",
                lat: 47.6149, lon: -122.3273,
                category: .cafe,
                circleId: "circle_1005",
                priceLevel: .moderate
            ),
            createPlace(
                id: "place_1013",
                name: "Victrola Coffee Roasters",
                description: "Local roaster with artisanal approach to coffee",
                address: "310 E Pike St, Seattle, WA 98122",
                lat: 47.6141, lon: -122.3254,
                category: .cafe,
                circleId: "circle_1005",
                priceLevel: .moderate
            ),
            createPlace(
                id: "place_1014",
                name: "Espresso Vivace",
                description: "Seattle institution known for exceptional espresso",
                address: "532 Broadway E, Seattle, WA 98102",
                lat: 47.6234, lon: -122.3209,
                category: .cafe,
                circleId: "circle_1005",
                priceLevel: .moderate
            )
        ]
        
        // Create mock friend requests
        friendRequests = [
            FriendRequest(
                id: "request_1001",
                from: users.first { $0.id == "user_1004" }!,
                to: users.first { $0.id == "user_1001" }!,
                status: .pending,
                createdAt: Date().addingTimeInterval(-86400 * 2) // 2 days ago
            ),
            FriendRequest(
                id: "request_1002",
                from: users.first { $0.id == "user_1005" }!,
                to: users.first { $0.id == "user_1001" }!,
                status: .pending,
                createdAt: Date().addingTimeInterval(-86400 * 1) // 1 day ago
            )
        ]
    }
    
    private func createPlace(id: String, name: String, description: String, address: String, lat: Double, lon: Double, category: PlaceCategory, circleId: String, priceLevel: PriceLevel) -> Place {
        // Create a place using JSON decoding since Place only has a Decodable initializer
        let placeData: [String: Any] = [
            "_id": id,
            "name": name,
            "description": description,
            "address": address,
            "location": [
                "type": "Point",
                "coordinates": [lon, lat]
            ],
            "category": category.rawValue,
            "rating": Double.random(in: 3.0...5.0),
            "userRatingsTotal": Int.random(in: 10...200),
            "priceLevel": priceLevel.rawValue,
            "circleId": circleId,
            "addedBy": "user_1001",
            "privacy": "followCircle",
            "createdAt": ISO8601DateFormatter().string(from: Date().addingTimeInterval(Double.random(in: -86400 * 30 ... -86400 * 5))),
            "updatedAt": ISO8601DateFormatter().string(from: Date().addingTimeInterval(Double.random(in: -86400 * 5 ... -3600)))
        ]
        
        do {
            let jsonData = try JSONSerialization.data(withJSONObject: placeData)
            let decoder = JSONDecoder()
            decoder.dateDecodingStrategy = .iso8601
            return try decoder.decode(Place.self, from: jsonData)
        } catch {
            fatalError("Failed to create mock place: \(error)")
        }
    }
    
    // MARK: - Mock Authentication
    
    func login(email: String, password: String, completion: @escaping (Result<User, Error>) -> Void) {
        // Simulate network delay
        DispatchQueue.global().asyncAfter(deadline: .now() + 1.0) {
            // For mock purposes, we'll accept any email/password
            if let user = self.users.first(where: { $0.id == self.currentUserId }) {
                completion(.success(user))
            } else {
                completion(.failure(AuthError.accountNotFound))
            }
        }
    }
    
    func register(email: String, displayName: String, password: String, completion: @escaping (Result<User, Error>) -> Void) {
        // Simulate network delay
        DispatchQueue.global().asyncAfter(deadline: .now() + 1.5) {
            // For mock purposes, we'll always succeed
            // Create a new user
            let newUser = User(
                id: "user_\(Int.random(in: 2000...9999))",
                email: email,
                displayName: displayName,
                profilePicture: nil,
                bio: nil,
                location: nil,
                friends: [],
                friendRequests: [],
                createdAt: Date()
            )
            
            // Add to users array
            self.users.append(newUser)
            self.currentUserId = newUser.id
            
            completion(.success(newUser))
        }
    }
    
    // MARK: - User Related
    
    func getCurrentUser(completion: @escaping (Result<User, Error>) -> Void) {
        // Simulate network delay
        DispatchQueue.global().asyncAfter(deadline: .now() + 0.5) {
            if let user = self.users.first(where: { $0.id == self.currentUserId }) {
                completion(.success(user))
            } else {
                completion(.failure(UserError.notFound))
            }
        }
    }
    
    func getUserById(userId: String, completion: @escaping (Result<User, Error>) -> Void) {
        // Simulate network delay
        DispatchQueue.global().asyncAfter(deadline: .now() + 0.5) {
            if let user = self.users.first(where: { $0.id == userId }) {
                completion(.success(user))
            } else {
                completion(.failure(UserError.notFound))
            }
        }
    }
    
    func updateUserProfile(displayName: String? = nil, bio: String? = nil, location: String? = nil, completion: @escaping (Result<User, Error>) -> Void) {
        // Simulate network delay
        DispatchQueue.global().asyncAfter(deadline: .now() + 1.0) {
            if let index = self.users.firstIndex(where: { $0.id == self.currentUserId }) {
                var updatedUser = self.users[index]
                
                // Update user fields using copy method
                if let displayName = displayName {
                    updatedUser = updatedUser.copy(displayName: displayName)
                }
                
                if let bio = bio {
                    updatedUser = updatedUser.copy(bio: bio)
                }
                
                if let location = location {
                    updatedUser = updatedUser.copy(location: location)
                }
                
                // Update in array
                self.users[index] = updatedUser
                
                completion(.success(updatedUser))
            } else {
                completion(.failure(UserError.notFound))
            }
        }
    }
    
    func getFriends(completion: @escaping (Result<[User], Error>) -> Void) {
        // Simulate network delay
        DispatchQueue.global().asyncAfter(deadline: .now() + 0.7) {
            if let user = self.users.first(where: { $0.id == self.currentUserId }) {
                let friendIds = user.friends ?? []
                let friends = self.users.filter { friendIds.contains($0.id) }
                
                completion(.success(friends))
            } else {
                completion(.failure(UserError.notFound))
            }
        }
    }
    
    func getFriendRequests(completion: @escaping (Result<[FriendRequest], Error>) -> Void) {
        // Simulate network delay
        DispatchQueue.global().asyncAfter(deadline: .now() + 0.5) {
            let requests = self.friendRequests.filter { $0.to.id == self.currentUserId && $0.status == .pending }
            completion(.success(requests))
        }
    }
    
    // MARK: - Circle Related
    
    func getUserCircles(completion: @escaping (Result<[Circle], Error>) -> Void) {
        // Simulate network delay
        DispatchQueue.global().asyncAfter(deadline: .now() + 0.8) {
            let userCircles = self.circles.filter { $0.owner == self.currentUserId }
            completion(.success(userCircles))
        }
    }
    
    func getCircleById(circleId: String, completion: @escaping (Result<Circle, Error>) -> Void) {
        // Simulate network delay
        DispatchQueue.global().asyncAfter(deadline: .now() + 0.5) {
            if let circle = self.circles.first(where: { $0.id == circleId }) {
                // Check if user has access to this circle
                if circle.owner == self.currentUserId || 
                   circle.privacy == .public || 
                   (circle.sharedWith?.contains(self.currentUserId) ?? false) {
                    completion(.success(circle))
                } else {
                    completion(.failure(CircleError.permissionDenied))
                }
            } else {
                completion(.failure(CircleError.notFound))
            }
        }
    }
    
    func getPublicCircles(completion: @escaping (Result<[Circle], Error>) -> Void) {
        // Simulate network delay
        DispatchQueue.global().asyncAfter(deadline: .now() + 0.8) {
            let publicCircles = self.circles.filter { $0.privacy == .public && $0.owner != self.currentUserId }
            completion(.success(publicCircles))
        }
    }
    
    func createCircle(name: String, description: String?, privacy: PrivacyLevel, category: CircleCategory, location: String? = nil, tags: [String]? = nil, completion: @escaping (Result<Circle, Error>) -> Void) {
        // Simulate network delay
        DispatchQueue.global().asyncAfter(deadline: .now() + 1.2) {
            let newCircle = Circle(
                id: "circle_\(Int.random(in: 2000...9999))",
                name: name,
                description: description,
                coverImage: nil,
                owner: self.currentUserId,
                ownerDetails: nil,
                editors: nil,
                editorsDetails: nil,
                places: [],
                placesCount: 0,
                placesWithDetails: nil,
                privacy: privacy,
                allowNetworkEdit: privacy == .myNetwork,
                category: category,
                location: location,
                tags: tags,
                sharedWith: [],
                followers: [],
                activeShares: nil,
                shareSettings: nil,
                isSharedWithMe: false,
                sharedBy: nil,
                myAccessLevel: nil,
                createdAt: Date(),
                updatedAt: Date()
            )
            
            // Add to circles array
            self.circles.append(newCircle)
            
            completion(.success(newCircle))
        }
    }
    
    // MARK: - Place Related
    
    func getPlacesByCircleId(circleId: String, completion: @escaping (Result<[Place], Error>) -> Void) {
        // Simulate network delay
        DispatchQueue.global().asyncAfter(deadline: .now() + 0.7) {
            // Check if circle exists and user has access
            if let circle = self.circles.first(where: { $0.id == circleId }) {
                if circle.owner == self.currentUserId || 
                   circle.privacy == .public || 
                   (circle.sharedWith?.contains(self.currentUserId) ?? false) {
                    
                    // Get places for this circle
                    let circlePlaces = self.places.filter { $0.circleId == circleId }
                    completion(.success(circlePlaces))
                } else {
                    completion(.failure(CircleError.permissionDenied))
                }
            } else {
                completion(.failure(CircleError.notFound))
            }
        }
    }
    
    func getPlaceById(placeId: String, completion: @escaping (Result<Place, Error>) -> Void) {
        // Simulate network delay
        DispatchQueue.global().asyncAfter(deadline: .now() + 0.5) {
            if let place = self.places.first(where: { $0.id == placeId }) {
                // Check if user has access to the circle containing this place
                if let circle = self.circles.first(where: { $0.id == place.circleId }) {
                    if circle.owner == self.currentUserId || 
                       circle.privacy == .public || 
                       (circle.sharedWith?.contains(self.currentUserId) ?? false) {
                        
                        completion(.success(place))
                    } else {
                        completion(.failure(PlaceError.permissionDenied))
                    }
                } else {
                    completion(.failure(CircleError.notFound))
                }
            } else {
                completion(.failure(PlaceError.notFound))
            }
        }
    }
    
    func createPlace(name: String, description: String?, address: String, category: PlaceCategory, circleId: String, priceLevel: PriceLevel? = nil, completion: @escaping (Result<Place, Error>) -> Void) {
        // Simulate network delay
        DispatchQueue.global().asyncAfter(deadline: .now() + 1.5) {
            // Check if circle exists and user has permission
            if let circle = self.circles.first(where: { $0.id == circleId }) {
                if circle.owner == self.currentUserId {
                    // Generate random coordinates for mock purposes
                    let lat = Double.random(in: 37.0...42.0)
                    let lon = Double.random(in: -122.0...(-71.0))
                    
                    let newPlace = self.createPlace(
                        id: "place_\(Int.random(in: 2000...9999))",
                        name: name,
                        description: description ?? "",
                        address: address,
                        lat: lat,
                        lon: lon,
                        category: category,
                        circleId: circleId,
                        priceLevel: priceLevel ?? .moderate
                    )
                    
                    // Add to places array
                    self.places.append(newPlace)
                    
                    // Update the circle's places array
                    if let index = self.circles.firstIndex(where: { $0.id == circleId }) {
                        var updatedCircle = self.circles[index]
                        var placesArray = updatedCircle.places ?? []
                        placesArray.append(newPlace.id)
                        
                        // Create updated circle with new places
                        let newCircle = Circle(
                            id: updatedCircle.id,
                            name: updatedCircle.name,
                            description: updatedCircle.description,
                            coverImage: updatedCircle.coverImage,
                            owner: updatedCircle.owner,
                            ownerDetails: updatedCircle.ownerDetails,
                editors: nil,
                editorsDetails: nil,
                            places: placesArray,
                            placesCount: placesArray.count,
                            placesWithDetails: updatedCircle.placesWithDetails,
                            privacy: updatedCircle.privacy,
                            allowNetworkEdit: updatedCircle.allowNetworkEdit,
                            category: updatedCircle.category,
                            location: updatedCircle.location,
                            tags: updatedCircle.tags,
                            sharedWith: updatedCircle.sharedWith,
                            followers: updatedCircle.followers,
                            activeShares: updatedCircle.activeShares,
                            shareSettings: updatedCircle.shareSettings,
                            isSharedWithMe: updatedCircle.isSharedWithMe,
                            sharedBy: updatedCircle.sharedBy,
                            myAccessLevel: updatedCircle.myAccessLevel,
                            createdAt: updatedCircle.createdAt,
                            updatedAt: Date()
                        )
                        
                        self.circles[index] = newCircle
                    }
                    
                    completion(.success(newPlace))
                } else {
                    completion(.failure(PlaceError.permissionDenied))
                }
            } else {
                completion(.failure(CircleError.notFound))
            }
        }
    }
}
import SwiftUI
import MapKit

struct PlaceDetailView: View {
    let place: Place
    @Environment(\.dismiss) var dismiss
    @State private var region: MKCoordinateRegion
    @State private var showingShareSheet = false
    
    private let circlesBlue = Color(red: 0.0, green: 122.0/255.0, blue: 1.0)
    
    init(place: Place) {
        self.place = place
        let coordinate = place.location?.clLocation?.coordinate ?? CLLocationCoordinate2D(latitude: 0, longitude: 0)
        self._region = State(initialValue: MKCoordinateRegion(
            center: coordinate,
            span: MKCoordinateSpan(latitudeDelta: 0.01, longitudeDelta: 0.01)
        ))
    }
    
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                // Map
                if place.location != nil {
                    Map(coordinateRegion: $region, annotationItems: [place]) { place in
                        MapMarker(
                            coordinate: place.location?.clLocation?.coordinate ?? CLLocationCoordinate2D(),
                            tint: .red
                        )
                    }
                    .frame(height: 300)
                    .cornerRadius(12)
                    .padding(.horizontal)
                }
                
                VStack(alignment: .leading, spacing: 12) {
                    // Place name
                    Text(place.name)
                        .font(.largeTitle)
                        .fontWeight(.bold)
                    
                    // Category
                    HStack {
                        Image(systemName: place.category.systemIconName)
                            .foregroundColor(.gray)
                        Text(place.category.displayName)
                            .font(.subheadline)
                            .foregroundColor(.gray)
                    }
                    
                    // Address
                    if !place.address.isEmpty {
                        HStack(alignment: .top) {
                            Image(systemName: "mappin.circle")
                                .foregroundColor(.gray)
                            
                            Text(place.address)
                                .font(.subheadline)
                                .foregroundColor(.gray)
                        }
                    }
                    
                    // Description
                    if let description = place.description, !description.isEmpty {
                        VStack(alignment: .leading, spacing: 8) {
                            Text("Description")
                                .font(.headline)
                            
                            Text(description)
                                .font(.body)
                        }
                    }
                    
                    // Notes
                    if let notes = place.notes, !notes.isEmpty {
                        VStack(alignment: .leading, spacing: 8) {
                            Text("Notes")
                                .font(.headline)
                            
                            Text(notes)
                                .font(.body)
                                .padding()
                                .background(Color.gray.opacity(0.1))
                                .cornerRadius(8)
                        }
                    }
                    
                    // Website
                    if let website = place.website, !website.isEmpty {
                        HStack {
                            Image(systemName: "globe")
                                .foregroundColor(.gray)
                            
                            Link(website, destination: URL(string: website) ?? URL(string: "https://")!)
                                .font(.subheadline)
                        }
                    }
                    
                    // Phone
                    if let phone = place.phone, !phone.isEmpty {
                        HStack {
                            Image(systemName: "phone")
                                .foregroundColor(.gray)
                            
                            Link(phone, destination: URL(string: "tel:\(phone)") ?? URL(string: "tel:")!)
                                .font(.subheadline)
                        }
                    }
                    
                    // Privacy
                    HStack {
                        Image(systemName: place.privacy.systemIconName)
                            .foregroundColor(.gray)
                        
                        Text(place.privacy.displayName)
                            .font(.subheadline)
                            .foregroundColor(.gray)
                    }
                    
                    // Price Level
                    if let priceLevel = place.priceLevel {
                        HStack {
                            Image(systemName: "dollarsign.circle")
                                .foregroundColor(.gray)
                            
                            Text(priceLevel.displaySymbol)
                                .font(.subheadline)
                                .foregroundColor(.gray)
                        }
                    }
                    
                    // Added date
                    HStack {
                        Image(systemName: "calendar")
                            .foregroundColor(.gray)
                        
                        Text("Added \(place.createdAt, style: .date)")
                            .font(.subheadline)
                            .foregroundColor(.gray)
                    }
                }
                .padding(.horizontal)
                
                // Share button
                Button(action: {
                    showingShareSheet = true
                }) {
                    HStack {
                        Image(systemName: "square.and.arrow.up")
                        Text("Share Place")
                    }
                    .frame(maxWidth: .infinity)
                    .padding()
                    .background(circlesBlue)
                    .foregroundColor(.white)
                    .cornerRadius(10)
                }
                .padding(.horizontal)
                
                // Open in Maps button
                if place.location != nil {
                    Button(action: openInMaps) {
                        HStack {
                            Image(systemName: "map")
                            Text("Open in Maps")
                        }
                        .frame(maxWidth: .infinity)
                        .padding()
                        .background(Color.gray.opacity(0.2))
                        .foregroundColor(circlesBlue)
                        .cornerRadius(10)
                    }
                    .padding(.horizontal)
                }
            }
            .padding(.vertical)
        }
        .navigationTitle("Place Details")
        .navigationBarTitleDisplayMode(.inline)
        .sheet(isPresented: $showingShareSheet) {
            PlaceShareSheet(items: [shareContent()])
        }
    }
    
    private func openInMaps() {
        guard let location = place.location?.clLocation else { return }
        
        let mapItem = MKMapItem(placemark: MKPlacemark(coordinate: location.coordinate))
        mapItem.name = place.name
        mapItem.openInMaps(launchOptions: [
            MKLaunchOptionsDirectionsModeKey: MKLaunchOptionsDirectionsModeDriving
        ])
    }
    
    private func shareContent() -> String {
        var shareText = "📍 \(place.name)"
        
        if !place.address.isEmpty {
            shareText += "\n\(place.address)"
        }
        
        if let description = place.description, !description.isEmpty {
            shareText += "\n\n\(description)"
        }
        
        if let notes = place.notes, !notes.isEmpty {
            shareText += "\n\n\(notes)"
        }
        
        shareText += "\n\n📱 Shared from Circles App"
        
        return shareText
    }
}

struct PlaceShareSheet: UIViewControllerRepresentable {
    let items: [Any]
    
    func makeUIViewController(context: Context) -> UIActivityViewController {
        let controller = UIActivityViewController(
            activityItems: items,
            applicationActivities: nil
        )
        return controller
    }
    
    func updateUIViewController(_ uiViewController: UIActivityViewController, context: Context) {}
}

struct PlaceDetailView_Previews: PreviewProvider {
    static var previews: some View {
        NavigationView {
            PlaceDetailView(place: Place(
                id: "1",
                name: "Sample Place",
                description: "A great place to visit",
                address: "123 Main St, City, State",
                location: GeoLocation(type: "Point", coordinates: [-122.4194, 37.7749]),
                website: "https://example.com",
                phone: "+1234567890",
                googlePlaceId: nil,
                photos: nil,
                category: .restaurant,
                rating: 4.5,
                notes: "Great place to visit!",
                tags: ["food", "casual"],
                reviews: nil,
                openingHours: nil,
                priceLevel: .moderate,
                circleId: "1",
                addedBy: "user1",
                privacy: .public,
                createdAt: Date(),
                updatedAt: Date()
            ))
        }
    }
}
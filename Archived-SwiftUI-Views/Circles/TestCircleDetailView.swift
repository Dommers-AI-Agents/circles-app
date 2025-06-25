import SwiftUI
import CoreLocation

// Test view to verify map functionality
struct TestCircleDetailView: View {
    @State private var showingMapView = false
    @State private var mapCenter = CLLocationCoordinate2D(latitude: 40.7128, longitude: -74.0060)
    
    var body: some View {
        VStack {
            // Header with toggle
            HStack {
                Text("Places - TEST VIEW")
                    .font(.headline)
                
                Spacer()
                
                Button(action: { 
                    showingMapView.toggle()
                    print("Map toggle: \(showingMapView)")
                }) {
                    Text(showingMapView ? "Show List" : "Show Map")
                        .padding(8)
                        .background(Color.blue)
                        .foregroundColor(.white)
                        .cornerRadius(8)
                }
            }
            .padding()
            
            // Content
            if showingMapView {
                Text("MAP VIEW WOULD BE HERE")
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .background(Color.green.opacity(0.2))
            } else {
                Text("LIST VIEW")
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .background(Color.blue.opacity(0.2))
            }
        }
    }
}

#Preview {
    TestCircleDetailView()
}
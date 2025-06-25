import SwiftUI
import GooglePlaces

struct GooglePlaceSearchView: View {
    @StateObject private var viewModel = GooglePlaceSearchViewModel()
    @Binding var selectedPlace: GooglePlaceDetails?
    @Environment(\.dismiss) var dismiss
    @State private var showingManualEntry = false
    
    private let circlesBlue = Color(red: 0.0, green: 122.0/255.0, blue: 1.0)
    
    var body: some View {
        NavigationView {
            VStack(spacing: 0) {
                // Search bar
                HStack {
                    Image(systemName: "magnifyingglass")
                        .foregroundColor(.secondary)
                    
                    TextField("Search for a place...", text: $viewModel.searchText)
                        .textFieldStyle(RoundedBorderTextFieldStyle())
                    
                    if !viewModel.searchText.isEmpty {
                        Button(action: { viewModel.searchText = "" }) {
                            Image(systemName: "xmark.circle.fill")
                                .foregroundColor(.secondary)
                        }
                    }
                }
                .padding()
                
                // Search results
                if viewModel.isSearching {
                    ProgressView("Searching...")
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                } else if !viewModel.searchResults.isEmpty {
                    ScrollView {
                        LazyVStack(alignment: .leading, spacing: 0) {
                            ForEach(viewModel.searchResults, id: \.placeID) { prediction in
                                PlacePredictionRow(prediction: prediction) {
                                    viewModel.selectPlace(prediction)
                                }
                                
                                Divider()
                            }
                        }
                    }
                } else if !viewModel.searchText.isEmpty {
                    VStack(spacing: 20) {
                        Image(systemName: "magnifyingglass")
                            .font(.system(size: 50))
                            .foregroundColor(.gray)
                        
                        Text("No places found")
                            .font(.headline)
                            .foregroundColor(.secondary)
                        
                        Text("Try searching for a different place")
                            .font(.subheadline)
                            .foregroundColor(.secondary)
                        
                        Divider()
                            .padding(.vertical, 10)
                        
                        Button(action: {
                            // Create a place with just the address
                            viewModel.createPlaceFromAddress(viewModel.searchText)
                        }) {
                            HStack {
                                Image(systemName: "plus.circle.fill")
                                Text("Add \"\(viewModel.searchText)\" anyway")
                            }
                            .foregroundColor(circlesBlue)
                            .font(.headline)
                        }
                        .padding()
                        .background(Color.gray.opacity(0.1))
                        .cornerRadius(10)
                    }
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .padding()
                } else {
                    VStack(spacing: 20) {
                        Image(systemName: "map")
                            .font(.system(size: 50))
                            .foregroundColor(.gray)
                        
                        Text("Search for places")
                            .font(.headline)
                            .foregroundColor(.secondary)
                        
                        Text("Find restaurants, cafes, shops, and more")
                            .font(.subheadline)
                            .foregroundColor(.secondary)
                            .multilineTextAlignment(.center)
                    }
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .padding()
                }
            }
            .navigationTitle("Search Places")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) {
                    Button("Cancel") {
                        dismiss()
                    }
                }
                
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button("Manual Entry") {
                        showingManualEntry = true
                    }
                    .foregroundColor(circlesBlue)
                }
            }
        }
        .onReceive(viewModel.$selectedPlace) { place in
            if let place = place {
                selectedPlace = place
                dismiss()
            }
        }
        .alert("Error", isPresented: .constant(viewModel.errorMessage != nil)) {
            Button("OK") {
                viewModel.errorMessage = nil
            }
        } message: {
            Text(viewModel.errorMessage ?? "")
        }
        .overlay(
            Group {
                if viewModel.isLoadingDetails {
                    Color.black.opacity(0.5)
                        .ignoresSafeArea()
                    ProgressView("Loading place details...")
                        .progressViewStyle(CircularProgressViewStyle())
                        .padding()
                        .background(Color(.systemBackground))
                        .cornerRadius(10)
                }
            }
        )
        .sheet(isPresented: $showingManualEntry) {
            ManualAddressEntryView { address in
                showingManualEntry = false
                viewModel.createPlaceFromAddress(address)
            }
        }
    }
}

struct PlacePredictionRow: View {
    let prediction: GooglePlacePrediction
    let onTap: () -> Void
    
    var body: some View {
        Button(action: onTap) {
            HStack(spacing: 12) {
                Image(systemName: iconForTypes(prediction.types))
                    .font(.title2)
                    .foregroundColor(.blue)
                    .frame(width: 40)
                
                VStack(alignment: .leading, spacing: 4) {
                    Text(prediction.primaryText)
                        .font(.headline)
                        .foregroundColor(.primary)
                        .lineLimit(1)
                    
                    Text(prediction.secondaryText)
                        .font(.caption)
                        .foregroundColor(.secondary)
                        .lineLimit(2)
                }
                
                Spacer()
                
                Image(systemName: "chevron.right")
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
            .padding(.horizontal)
            .padding(.vertical, 12)
            .contentShape(Rectangle())
        }
        .buttonStyle(PlainButtonStyle())
    }
    
    private func iconForTypes(_ types: [String]) -> String {
        // Map Google place types to SF Symbols
        if types.contains("restaurant") { return "fork.knife" }
        if types.contains("cafe") { return "cup.and.saucer" }
        if types.contains("bar") { return "wineglass" }
        if types.contains("lodging") || types.contains("hotel") { return "bed.double" }
        if types.contains("store") || types.contains("shopping_mall") { return "bag" }
        if types.contains("health") || types.contains("hospital") { return "heart.text.square" }
        if types.contains("gas_station") { return "fuelpump" }
        if types.contains("bank") || types.contains("atm") { return "dollarsign.circle" }
        if types.contains("movie_theater") { return "ticket" }
        if types.contains("museum") { return "building.columns" }
        if types.contains("park") { return "tree" }
        if types.contains("gym") { return "figure.walk" }
        
        return "mappin.circle"
    }
}

#Preview {
    GooglePlaceSearchView(selectedPlace: .constant(nil))
}
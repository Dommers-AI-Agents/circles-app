import SwiftUI

struct EditNotesView: View {
    let place: Place
    @Binding var privateNotes: String
    @Binding var publicNotes: String
    let onSave: () -> Void
    @Environment(\.dismiss) var dismiss
    
    private let circlesBlue = Color(red: 0.0, green: 122.0/255.0, blue: 1.0)
    
    var body: some View {
        NavigationView {
            ScrollView {
                VStack(alignment: .leading, spacing: 20) {
                    // Public Notes Section
                    VStack(alignment: .leading, spacing: 8) {
                        HStack {
                            Label("Public Notes", systemImage: "globe")
                                .font(.headline)
                                .foregroundColor(.primary)
                            Spacer()
                        }
                        
                        Text("These notes will be visible to everyone who can see this place")
                            .font(.caption)
                            .foregroundColor(.secondary)
                        
                        TextEditor(text: $publicNotes)
                            .frame(minHeight: 100)
                            .padding(8)
                            .background(Color.blue.opacity(0.05))
                            .cornerRadius(8)
                            .overlay(
                                RoundedRectangle(cornerRadius: 8)
                                    .stroke(Color.blue.opacity(0.3), lineWidth: 1)
                            )
                    }
                    
                    // Private Notes Section
                    VStack(alignment: .leading, spacing: 8) {
                        HStack {
                            Label("Private Notes", systemImage: "lock.fill")
                                .font(.headline)
                                .foregroundColor(.primary)
                            Spacer()
                        }
                        
                        Text("These notes are only visible to you")
                            .font(.caption)
                            .foregroundColor(.secondary)
                        
                        TextEditor(text: $privateNotes)
                            .frame(minHeight: 100)
                            .padding(8)
                            .background(Color.gray.opacity(0.05))
                            .cornerRadius(8)
                            .overlay(
                                RoundedRectangle(cornerRadius: 8)
                                    .stroke(Color.gray.opacity(0.3), lineWidth: 1)
                            )
                    }
                    
                    // Place Info
                    VStack(alignment: .leading, spacing: 8) {
                        Text("Editing notes for:")
                            .font(.caption)
                            .foregroundColor(.secondary)
                        
                        HStack {
                            Image(systemName: place.category.systemIconName)
                                .foregroundColor(.gray)
                            Text(place.name)
                                .font(.subheadline)
                                .fontWeight(.medium)
                        }
                        .padding()
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .background(Color(.systemGray6))
                        .cornerRadius(8)
                    }
                }
                .padding()
            }
            .navigationTitle("Edit Notes")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) {
                    Button("Cancel") {
                        dismiss()
                    }
                }
                
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button("Save") {
                        onSave()
                    }
                    .fontWeight(.semibold)
                    .foregroundColor(circlesBlue)
                }
            }
        }
    }
}

#Preview {
    EditNotesView(
        place: Place(
            id: "1",
            name: "Sample Restaurant",
            description: "A great place to eat",
            address: "123 Main St",
            location: nil,
            website: nil,
            phone: nil,
            googlePlaceId: nil,
            photos: nil,
            category: .restaurant,
            rating: 4.5,
            userRatingsTotal: 100,
            notes: nil,
            privateNotes: nil,
            publicNotes: nil,
            tags: nil,
            reviews: nil,
            openingHours: nil,
            priceLevel: nil,
            circleId: "circle1",
            addedBy: "user1",
            addedByUser: nil,
            privacy: .public,
            createdAt: Date(),
            updatedAt: Date()
        ),
        privateNotes: .constant("My private thoughts"),
        publicNotes: .constant("Great atmosphere"),
        onSave: {}
    )
}
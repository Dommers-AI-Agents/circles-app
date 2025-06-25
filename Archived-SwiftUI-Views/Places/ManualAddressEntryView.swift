import SwiftUI

struct ManualAddressEntryView: View {
    @State private var street = ""
    @State private var city = ""
    @State private var state = ""
    @State private var zipCode = ""
    @State private var country = "United States"
    
    @Environment(\.dismiss) var dismiss
    let onSave: (String) -> Void
    
    private let circlesBlue = Color(red: 0.0, green: 122.0/255.0, blue: 1.0)
    
    var fullAddress: String {
        var components: [String] = []
        if !street.isEmpty { components.append(street) }
        if !city.isEmpty { components.append(city) }
        if !state.isEmpty { components.append(state) }
        if !zipCode.isEmpty { components.append(zipCode) }
        if !country.isEmpty { components.append(country) }
        return components.joined(separator: ", ")
    }
    
    var isValidAddress: Bool {
        !street.isEmpty && !city.isEmpty
    }
    
    var body: some View {
        NavigationView {
            Form {
                Section(header: Text("Address Information")) {
                    TextField("Street Address", text: $street)
                        .textContentType(.streetAddressLine1)
                    
                    TextField("City", text: $city)
                        .textContentType(.addressCity)
                    
                    HStack {
                        TextField("State", text: $state)
                            .textContentType(.addressState)
                        
                        TextField("ZIP Code", text: $zipCode)
                            .textContentType(.postalCode)
                            .keyboardType(.numberPad)
                    }
                    
                    TextField("Country", text: $country)
                        .textContentType(.countryName)
                }
                
                Section {
                    Text("Full Address:")
                        .font(.caption)
                        .foregroundColor(.secondary)
                    Text(fullAddress.isEmpty ? "Enter address above" : fullAddress)
                        .font(.body)
                        .foregroundColor(fullAddress.isEmpty ? .secondary : .primary)
                }
            }
            .navigationTitle("Enter Address Manually")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) {
                    Button("Cancel") {
                        dismiss()
                    }
                }
                
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button("Save") {
                        onSave(fullAddress)
                        dismiss()
                    }
                    .disabled(!isValidAddress)
                    .foregroundColor(isValidAddress ? circlesBlue : .gray)
                }
            }
        }
    }
}

#Preview {
    ManualAddressEntryView { address in
        print("Address: \(address)")
    }
}
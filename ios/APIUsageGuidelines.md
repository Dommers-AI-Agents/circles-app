# API Usage Guidelines for Circles iOS App

## IMPORTANT: Cost-Efficient API Usage Policy

### Primary Rule: Use Apple Maps for Everything Except Photos

**Apple Maps API** should be used for:
- 🗺️ Map displays and interactions
- 📍 Place search and discovery
- 🧭 Navigation and directions
- 📍 Geocoding and reverse geocoding
- 🔍 Points of Interest (POI) search
- 📸 Apple Look Around (street view)
- 🏢 Place details and information
- ⭐ Reviews and ratings (when available)

**Google Places API** should ONLY be used for:
- 📷 Fetching place photos

### Why This Policy?

1. **Cost Efficiency**: Apple Maps API is significantly more cost-efficient than Google Maps API
2. **Native Integration**: Apple Maps provides better integration with iOS features
3. **Performance**: Using native Apple services reduces external API calls

### Implementation Guidelines

1. **When creating new places**:
   - Use Apple Maps for place search and selection
   - Use Apple Look Around for street view imagery
   - Only use Google Places API to fetch the place photo

2. **When displaying maps**:
   - Always use MKMapView (Apple Maps)
   - Never use GMSMapView (Google Maps) for map display

3. **When searching for places**:
   - Use MKLocalSearch (Apple Maps)
   - Only use Google Places Autocomplete if absolutely necessary for photo metadata

### Code Examples

❌ **DON'T DO THIS**:
```swift
// Don't use Google Maps for general place operations
GooglePlacesService.shared.searchPlaces(query: "coffee shop")
```

✅ **DO THIS**:
```swift
// Use Apple Maps for place search
let request = MKLocalSearch.Request()
request.naturalLanguageQuery = "coffee shop"
let search = MKLocalSearch(request: request)
```

✅ **ONLY USE GOOGLE FOR PHOTOS**:
```swift
// This is the ONLY acceptable use of Google Places API
GooglePlacesService.shared.loadPhoto(from: photoMetadata)
```

### Remember

- Every Google API call costs money
- Apple Maps API calls are included with the Apple Developer Program
- When in doubt, use Apple Maps
- Only use Google Places API when you specifically need place photos

---

**Last Updated**: January 2025
**Policy Owner**: Development Team
**Enforcement**: All code reviews should verify compliance with this policy
import MapKit
import Contacts

extension DirectionsDestination {
    /// Apple Maps: the exact pin, labelled with the place's name and address
    /// (no pin: Maps looks the address up)
    func openInAppleMaps() {
        let options = [MKLaunchOptionsDirectionsModeKey: MKLaunchOptionsDirectionsModeDriving]
        if let coordinate {
            var addressDict: [String: Any] = [:]
            if !address.isEmpty { addressDict[CNPostalAddressStreetKey] = address }
            let item = MKMapItem(placemark: MKPlacemark(coordinate: coordinate, addressDictionary: addressDict))
            item.name = name
            item.openInMaps(launchOptions: options)
            return
        }
        CLGeocoder().geocodeAddressString(address) { placemarks, _ in
            guard let placemark = placemarks?.first else { return }
            let item = MKMapItem(placemark: MKPlacemark(placemark: placemark))
            item.name = name
            item.openInMaps(launchOptions: options)
        }
    }
}

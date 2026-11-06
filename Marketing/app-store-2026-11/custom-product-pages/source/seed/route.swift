import MapKit
// Freedom Park loop, Charlotte: walking directions through waypoints
let pts: [(Double, Double)] = [(35.1937,-80.8448),(35.1878,-80.8466),(35.1849,-80.8412),(35.1893,-80.8378),(35.1951,-80.8392),(35.1937,-80.8448)]
var out: [(Double, Double)] = []
let sem = DispatchSemaphore(value: 0)
func leg(_ i: Int) {
  if i >= pts.count - 1 { sem.signal(); return }
  let r = MKDirections.Request()
  r.source = MKMapItem(placemark: MKPlacemark(coordinate: .init(latitude: pts[i].0, longitude: pts[i].1)))
  r.destination = MKMapItem(placemark: MKPlacemark(coordinate: .init(latitude: pts[i+1].0, longitude: pts[i+1].1)))
  r.transportType = .walking
  MKDirections(request: r).calculate { resp, err in
    if let route = resp?.routes.first {
      var c = [CLLocationCoordinate2D](repeating: .init(), count: route.polyline.pointCount)
      route.polyline.getCoordinates(&c, range: NSRange(location: 0, length: c.count))
      out += c.map { ($0.latitude, $0.longitude) }
    } else { FileHandle.standardError.write("leg \(i) failed \(String(describing: err))\n".data(using: .utf8)!) }
    leg(i + 1)
  }
}
DispatchQueue.main.async { leg(0) }
DispatchQueue.global().async { sem.wait(); print(out.map { "\($0.0),\($0.1)" }.joined(separator: ";")); exit(0) }
dispatchMain()

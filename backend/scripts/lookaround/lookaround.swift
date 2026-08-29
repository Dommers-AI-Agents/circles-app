// Renders Apple Look Around snapshots for a list of coordinates — the same
// free, on-device imagery the app's ImportPhotoQueue uses, but runnable from a
// Mac so a backfill doesn't need the phone.
//
//   swiftc -O -framework MapKit -framework AppKit -o lookaround lookaround.swift
//   ./lookaround candidates.json outdir        # candidates: [{"id","lat","lng"}]
//
// Writes outdir/<id>.jpg for every coordinate with coverage and prints a JSON
// summary {"rendered":[ids],"unavailable":[ids],"failed":[ids]} on stdout.
import Foundation
import MapKit
import AppKit

struct Candidate: Decodable { let id: String; let lat: Double; let lng: Double }

func jpegData(_ image: NSImage) -> Data? {
    guard let tiff = image.tiffRepresentation, let rep = NSBitmapImageRep(data: tiff) else { return nil }
    return rep.representation(using: .jpeg, properties: [.compressionFactor: 0.8])
}

let args = CommandLine.arguments
guard args.count >= 3 else {
    FileHandle.standardError.write("usage: lookaround candidates.json outdir\n".data(using: .utf8)!)
    exit(2)
}
let candidates = try JSONDecoder().decode([Candidate].self, from: Data(contentsOf: URL(fileURLWithPath: args[1])))
let outDir = URL(fileURLWithPath: args[2])
try FileManager.default.createDirectory(at: outDir, withIntermediateDirectories: true)

var rendered: [String] = [], unavailable: [String] = [], failed: [String] = []

Task {
    for c in candidates {
        let coordinate = CLLocationCoordinate2D(latitude: c.lat, longitude: c.lng)
        do {
            guard let scene = try await MKLookAroundSceneRequest(coordinate: coordinate).scene else {
                unavailable.append(c.id)
                FileHandle.standardError.write("· \(c.id) no coverage\n".data(using: .utf8)!)
                continue
            }
            let options = MKLookAroundSnapshotter.Options()
            options.size = CGSize(width: 900, height: 600)
            let snapshot = try await MKLookAroundSnapshotter(scene: scene, options: options).snapshot
            guard let data = jpegData(snapshot.image) else { failed.append(c.id); continue }
            try data.write(to: outDir.appendingPathComponent("\(c.id).jpg"))
            rendered.append(c.id)
            FileHandle.standardError.write("✓ \(c.id) \(data.count / 1024) KB\n".data(using: .utf8)!)
        } catch {
            failed.append(c.id)
            FileHandle.standardError.write("✗ \(c.id) \(error.localizedDescription)\n".data(using: .utf8)!)
        }
        // Be polite to Apple's tile servers
        try? await Task.sleep(nanoseconds: 300_000_000)
    }
    let summary = try JSONSerialization.data(withJSONObject: ["rendered": rendered, "unavailable": unavailable, "failed": failed])
    FileHandle.standardOutput.write(summary)
    FileHandle.standardOutput.write("\n".data(using: .utf8)!)
    exit(0)
}
RunLoop.main.run()

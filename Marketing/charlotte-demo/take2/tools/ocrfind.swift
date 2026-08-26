import Foundation
import Vision
import AppKit
// usage: ocrfind <png> <needle> [needle2 ...] -> one line per needle: "x y" (image px) or "NOTFOUND"
let args = CommandLine.arguments
guard args.count >= 3, let img = NSImage(contentsOfFile: args[1]),
      let cg = img.cgImage(forProposedRect: nil, context: nil, hints: nil) else { print("ERR"); exit(1) }
let req = VNRecognizeTextRequest()
req.recognitionLevel = .accurate
req.usesLanguageCorrection = false
try? VNImageRequestHandler(cgImage: cg, options: [:]).perform([req])
let W = CGFloat(cg.width), H = CGFloat(cg.height)
var found: [(String, CGRect)] = []
for obs in (req.results ?? []) {
    if let c = obs.topCandidates(1).first { found.append((c.string.lowercased(), obs.boundingBox)) }
}
for needle in args[2...] {
    let n = needle.lowercased()
    if let hit = found.first(where: { $0.0.contains(n) }) {
        print("\(Int(hit.1.midX * W)) \(Int((1 - hit.1.midY) * H))")
    } else { print("NOTFOUND") }
}

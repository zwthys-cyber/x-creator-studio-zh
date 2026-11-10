import Foundation
import Vision

guard CommandLine.arguments.count == 3 else { fatalError("expected light and dark fixture images") }
var reports: [[String: Any]] = []
for path in CommandLine.arguments.dropFirst() {
    let request = VNRecognizeTextRequest()
    request.recognitionLevel = .accurate
    request.recognitionLanguages = ["zh-Hans", "en-US"]
    request.usesLanguageCorrection = false
    try VNImageRequestHandler(url: URL(fileURLWithPath: path)).perform([request])
    let lines = request.results?.compactMap { $0.topCandidates(1).first?.string } ?? []
    let text = lines.joined().replacingOccurrences(of: " ", with: "")
    let expected = ["创作者工作室", "原创内容奖励", "创作者学院"]
    let matched = expected.filter { text.contains($0) }
    let report: [String: Any] = ["image": URL(fileURLWithPath: path).lastPathComponent,
        "recognized": lines, "matched": matched, "passed": matched.count == expected.count]
    reports.append(report)
}
let passed = reports.allSatisfy { ($0["passed"] as? Bool) == true }
let data = try JSONSerialization.data(withJSONObject: ["passed": passed, "images": reports], options: [.prettyPrinted, .sortedKeys])
try data.write(to: URL(fileURLWithPath: "dist/RASTER_OCR_RESULTS.json"))
print(String(data: data, encoding: .utf8)!)
if !passed { exit(1) }

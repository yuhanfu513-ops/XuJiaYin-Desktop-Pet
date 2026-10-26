import Foundation
import AVFoundation
let file = try AVAudioFile(forReading: URL(fileURLWithPath: CommandLine.arguments[1]))
let format = file.processingFormat
let buffer = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: AVAudioFrameCount(file.length))!
try file.read(into: buffer)
let samples = buffer.floatChannelData!
let rate = format.sampleRate
let hop = Int(rate * 0.01)
let count = Int(buffer.frameLength) / hop
var energy = [Double](repeating: 0, count: count)
var low = 0.0
let alpha = 1 - exp(-2 * Double.pi * 180 / rate)
for i in 0..<(count * hop) {
    var x = 0.0
    for c in 0..<Int(format.channelCount) { x += Double(samples[c][i]) / Double(format.channelCount) }
    low += alpha * (x - low)
    energy[i / hop] += low * low / Double(hop)
}
var flux = [Double](repeating: 0, count: count)
for i in 3..<count {
    flux[i] = max(0, sqrt(energy[i]) - sqrt(energy[i-3]))
}
var beats = [[String: Double]]()
var last = -1.0
let maximum = flux.max() ?? 1
for i in 4..<(count-4) {
    let local = Array(flux[max(0,i-70)...min(count-1,i+70)]).sorted()
    let threshold = max(maximum * 0.06, local[local.count/2] * 2.2)
    let time = Double(i*hop)/rate
    if flux[i] > threshold && flux[i] == flux[(i-4)...(i+4)].max()! && time-last >= 0.24 && energy[i] > 0.00001 {
        let strength = min(1, max(0.35, flux[i] / max(maximum * 0.4, 0.000001)))
        beats.append(["time": time, "strength": strength]); last = time
    }
}
try JSONSerialization.data(withJSONObject: beats, options: [.prettyPrinted, .sortedKeys]).write(to: URL(fileURLWithPath: CommandLine.arguments[2]))
print("Detected \(beats.count) rhythm accents, duration \(Double(buffer.frameLength)/rate)s")

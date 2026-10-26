import AVFoundation
import Foundation
let asset = AVURLAsset(url: URL(fileURLWithPath: CommandLine.arguments[1]))
let exporter = AVAssetExportSession(asset: asset, presetName: AVAssetExportPresetAppleM4A)!
exporter.outputURL = URL(fileURLWithPath: CommandLine.arguments[2])
exporter.outputFileType = .m4a
exporter.exportAsynchronously { if exporter.status == .completed { print("Audio extracted"); exit(0) }; print(String(describing: exporter.error)); exit(1) }
dispatchMain()

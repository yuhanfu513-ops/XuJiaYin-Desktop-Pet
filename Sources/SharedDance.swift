import AppKit

struct DancePose: Codable {
    let compression: Double
    let lift: Double
    static func at(_ time: Double, beats: [Double]) -> DancePose {
        var lo = 0, hi = beats.count
        while lo < hi { let mid = (lo+hi)/2; if beats[mid] <= time { lo = mid+1 } else { hi = mid } }
        guard lo > 0 else { return DancePose(compression: 1, lift: 0) }
        let elapsed = time-beats[lo-1]
        guard elapsed >= 0 && elapsed < 0.48 else { return DancePose(compression: 1, lift: 0) }
        let phase = elapsed/0.48
        let squash = phase < 0.25 ? sin(phase/0.25 * .pi/2) : pow((1-phase)/0.75, 2)
        let lift = phase > 0.25 ? sin((phase-0.25)/0.75 * .pi) : 0
        return DancePose(compression: 1-0.15*squash, lift: 8*lift)
    }
}
struct DanceState: Codable {
    let pid: Int32
    let uptime: Double
    let position: Double
    let duration: Double
    let playing: Bool
    let beats: [Double]
    func pose(now: Double) -> DancePose? {
        guard playing, now >= uptime, now-uptime < 1.5, duration > 0, duration.isFinite,
              position.isFinite, !beats.isEmpty, kill(pid, 0) == 0 else { return nil }
        return DancePose.at((position+now-uptime).truncatingRemainder(dividingBy: duration), beats: beats)
    }
}
enum DanceBus {
    static var url: URL {
        if let path = ProcessInfo.processInfo.environment["DESKTOP_PET_DANCE_STATE"] { return URL(fileURLWithPath: path) }
        return FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent("Library/Application Support/DesktopPetDance/state.json")
    }
    static func publish(position: Double, duration: Double, playing: Bool, beats: [Double]) {
        let state = DanceState(pid: getpid(), uptime: ProcessInfo.processInfo.systemUptime, position: position, duration: duration, playing: playing, beats: beats)
        do {
            try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true, attributes: [.posixPermissions: 0o700])
            try JSONEncoder().encode(state).write(to: url, options: .atomic)
        } catch { NSLog("Dance coordination: %@", error.localizedDescription) }
    }
}
final class DanceFollower {
    private var timer: Timer?
    private var state: DanceState?
    private var lastRead = -1.0
    private var lastProbe = -1.0
    private let redraw: () -> Void
    private(set) var pose: DancePose?
    init(redraw: @escaping () -> Void) { self.redraw = redraw }
    func start() {
        guard timer == nil else { return }
        let timer = Timer(timeInterval: 1.0/30, repeats: true) { [weak self] _ in self?.tick() }
        self.timer = timer; RunLoop.main.add(timer, forMode: .common); tick()
    }
    private func tick() {
        let now = ProcessInfo.processInfo.systemUptime
        if now-lastRead >= 0.1 {
            lastRead = now
            state = (try? Data(contentsOf: DanceBus.url)).flatMap { try? JSONDecoder().decode(DanceState.self, from: $0) }
        }
        let wasActive = pose != nil
        pose = state?.pose(now: now)
        if pose != nil || wasActive { redraw() }
        if let i = CommandLine.arguments.firstIndex(of: "--dance-probe"), i+1 < CommandLine.arguments.count, now-lastProbe > 0.1 {
            lastProbe = now
            let value: [String: Any] = ["active": pose != nil, "compression": pose?.compression ?? 1, "lift": pose?.lift ?? 0, "time": now]
            if let data = try? JSONSerialization.data(withJSONObject: value) { try? data.write(to: URL(fileURLWithPath: CommandLine.arguments[i+1]), options: .atomic) }
        }
    }
    deinit { timer?.invalidate() }
}
class DanceImageView: NSImageView {
    lazy var dance = DanceFollower { [weak self] in
        guard let self else { return }
        // Own speech animation resumes on its next frame when the music stops.
        self.layer?.transform = CATransform3DIdentity
        self.needsDisplay = true
    }
    override func viewDidMoveToWindow() { super.viewDidMoveToWindow(); if window != nil { dance.start() } }
    override func draw(_ dirtyRect: NSRect) {
        guard let pose = dance.pose else { super.draw(dirtyRect); return }
        NSGraphicsContext.saveGraphicsState()
        let transform = NSAffineTransform()
        transform.translateX(by: 0, yBy: CGFloat(pose.lift))
        transform.scaleX(by: 1, yBy: CGFloat(pose.compression))
        transform.concat(); super.draw(bounds)
        NSGraphicsContext.restoreGraphicsState()
    }
}

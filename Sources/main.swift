import AppKit
import AVFoundation

struct Beat: Decodable { let time: Double; let strength: Double }
struct Rhythm {
    let beats: [Beat]
    init(beats: [Beat]) {
        // Follow every detected beat at the original frequency.
        self.beats = beats
    }
    func pose(at time: Double) -> (CGFloat, CGFloat) {
        let pose = DancePose.at(time, beats: beats.map { $0.time })
        return (CGFloat(pose.compression), CGFloat(pose.lift))
    }
}
final class PetView: NSView {
    var portrait: NSImage!
    var playingPortrait: NSImage!
    var dancePortrait: NSImage!
    var danceMode = false
    var isPlaying = false
    weak var owner: Controller?
    var compression: CGFloat = 1
    var lift: CGFloat = 0
    var down = NSPoint.zero
    var origin = NSPoint.zero
    var dragged = false
    override func draw(_ dirtyRect: NSRect) {
        let h = bounds.height - 24
        let image = danceMode ? dancePortrait! : (isPlaying ? playingPortrait! : portrait!)
        let imageRatio = image.size.width / image.size.height
        let targetWidth = min(bounds.width, h * imageRatio)
        image.draw(in: NSRect(x: (bounds.width-targetWidth)/2, y: lift, width: targetWidth, height: (targetWidth/imageRatio) * compression), from: .zero, operation: .sourceOver, fraction: 1)
    }
    override func mouseDown(with event: NSEvent) {
        down = NSEvent.mouseLocation; origin = window!.frame.origin; dragged = false
    }
    override func mouseDragged(with event: NSEvent) {
        let p = NSEvent.mouseLocation
        if hypot(p.x-down.x, p.y-down.y) > 4 { dragged = true }
        if dragged { window?.setFrameOrigin(NSPoint(x: origin.x+p.x-down.x, y: origin.y+p.y-down.y)) }
    }
    override func mouseUp(with event: NSEvent) {
        if !dragged { owner?.toggle() }
        owner?.save()
    }
    override func rightMouseDown(with event: NSEvent) {
        if let menu = owner?.makeMenu() { NSMenu.popUpContextMenu(menu, with: event, for: self) }
    }
}
final class Controller: NSObject, NSApplicationDelegate {
    var panel: NSPanel!
    var view: PetView!
    var player: AVAudioPlayer!
    var timer: Timer?
    var status: NSStatusItem!
    let prefs = UserDefaults.standard
    var rhythm = Rhythm(beats: [])
    var normalRhythm = Rhythm(beats: [])
    var bangyouRhythm = Rhythm(beats: [])
    var normalPlayer: AVAudioPlayer!
    var bangyouPlayer: AVAudioPlayer!
    var danceMode = false
    var lastBroadcast = -1.0
    let isTesting = CommandLine.arguments.contains("--self-test")
    func applicationDidFinishLaunching(_ notification: Notification) {
        do {
            guard let resources = Bundle.main.resourceURL, let portrait = NSImage(contentsOf: resources.appendingPathComponent("portrait.png")) else { throw NSError(domain: "素材缺失", code: 1) }
            guard let playingPortrait = NSImage(contentsOf: resources.appendingPathComponent("portrait-playing.png")) else { throw NSError(domain: "播放形象素材缺失", code: 1) }
            player = try AVAudioPlayer(contentsOf: resources.appendingPathComponent("audio.m4a"))
            rhythm = Rhythm(beats: try JSONDecoder().decode([Beat].self, from: Data(contentsOf: resources.appendingPathComponent("beats.json"))))
            normalPlayer = player; normalRhythm = rhythm
            bangyouPlayer = try AVAudioPlayer(contentsOf: resources.appendingPathComponent("bangyou.m4a"))
            bangyouPlayer.numberOfLoops = -1; bangyouPlayer.prepareToPlay()
            bangyouRhythm = Rhythm(beats: try JSONDecoder().decode([Beat].self, from: Data(contentsOf: resources.appendingPathComponent("beats-bangyou.json"))))
            guard let dancePortrait = NSImage(contentsOf: resources.appendingPathComponent("portrait-bangyou.png")) else { throw NSError(domain: "邦友形象缺失", code: 1) }
            player.numberOfLoops = -1
            player.volume = prefs.object(forKey: "volume") == nil ? 0.7 : prefs.float(forKey: "volume")
            player.currentTime = min(max(0, prefs.double(forKey: "position")), max(0, player.duration - 0.01))
            player.prepareToPlay()
            bangyouPlayer.volume = player.volume
            bangyouPlayer.currentTime = min(max(0, prefs.double(forKey: "bangyouPosition")), max(0, bangyouPlayer.duration-0.01))
            let savedWidth = prefs.object(forKey: "petWidth") == nil ? 280 : prefs.double(forKey: "petWidth")
            let width: CGFloat = CGFloat([160, 220, 280, 360].contains(Int(savedWidth)) ? savedWidth : 280)
            let size = NSSize(width: width, height: width * portrait.size.height / portrait.size.width + 24)
            panel = NSPanel(contentRect: NSRect(origin: .zero, size: size), styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: false)
            panel.isOpaque = false; panel.backgroundColor = .clear; panel.hasShadow = false
            panel.level = .floating; panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
            panel.hidesOnDeactivate = false; panel.isReleasedWhenClosed = false
            view = PetView(frame: NSRect(origin: .zero, size: size)); view.portrait = portrait; view.playingPortrait = playingPortrait; view.dancePortrait = dancePortrait; view.owner = self
            panel.contentView = view
            let screen = NSScreen.main!.visibleFrame
            var p = NSPoint(x: screen.maxX-size.width-40, y: screen.minY+30)
            if prefs.object(forKey: "x") != nil { p = NSPoint(x: prefs.double(forKey: "x"), y: prefs.double(forKey: "y")) }
            if !NSScreen.screens.contains(where: { $0.visibleFrame.intersects(NSRect(origin: p, size: size)) }) { p = screen.origin }
            panel.setFrameOrigin(p)
            status = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
            status.button?.title = "许"
            status.menu = makeMenu()
            let frameTimer = Timer(timeInterval: 1.0/30, repeats: true) { [weak self] _ in self?.animate() }
            timer = frameTimer; RunLoop.main.add(frameTimer, forMode: .common)
            if CommandLine.arguments.contains("--self-test") { selfTest(); return }
            panel.orderFrontRegardless()
        } catch {
            let alert = NSAlert(); alert.messageText = "桌宠无法启动"; alert.informativeText = error.localizedDescription; alert.runModal(); NSApp.terminate(nil)
        }
    }
    func animate() {
        view.isPlaying = player.isPlaying
        if player.isPlaying {
            let pose = rhythm.pose(at: player.currentTime)
            view.compression = pose.0
            view.lift = pose.1
        } else { view.compression = 1; view.lift = 0 }
        view.needsDisplay = true
        if danceMode && player.isPlaying && ProcessInfo.processInfo.systemUptime-lastBroadcast > 0.5 { broadcast() }
    }
    func broadcast() {
        guard !isTesting || ProcessInfo.processInfo.environment["DESKTOP_PET_DANCE_STATE"] != nil else { return }
        lastBroadcast = ProcessInfo.processInfo.systemUptime
        DanceBus.publish(position: player.currentTime, duration: player.duration, playing: danceMode && player.isPlaying, beats: bangyouRhythm.beats.map { $0.time })
    }
    @objc func changeDanceMode() {
        player.pause(); save()
        danceMode.toggle(); view.danceMode = danceMode
        let image = danceMode ? view.dancePortrait! : view.portrait!
        panel.setContentSize(NSSize(width: panel.frame.width, height: panel.frame.width*image.size.height/image.size.width+24))
        player = danceMode ? bangyouPlayer : normalPlayer
        rhythm = danceMode ? bangyouRhythm : normalRhythm
        view.isPlaying = false; animate(); broadcast()
        status.menu = makeMenu()
    }
    @objc func toggle() {
        if player.isPlaying { player.pause() } else { player.play() }
        animate(); broadcast(); save(); status.menu = makeMenu()
    }
    @objc func restart() {
        player.currentTime = 0; player.play()
        animate(); broadcast(); save(); status.menu = makeMenu()
    }
    @objc func volume(_ sender: NSMenuItem) { normalPlayer.volume = Float(sender.tag)/100; bangyouPlayer.volume = normalPlayer.volume; save(); status.menu = makeMenu() }
    @objc func resize(_ sender: NSMenuItem) {
        let old = panel.frame
        let width = CGFloat(sender.tag)
        let image = danceMode ? view.dancePortrait! : view.portrait!
        let height = width * image.size.height / image.size.width + 24
        panel.setFrame(NSRect(x: old.minX, y: old.minY, width: width, height: height), display: true)
        prefs.set(sender.tag, forKey: "petWidth")
        save(); status.menu = makeMenu()
    }
    @objc func moveToBottomLeft() {
        guard let screen = panel.screen ?? NSScreen.main else { return }
        let frame = screen.visibleFrame
        panel.setFrameOrigin(NSPoint(x: frame.minX + 24, y: frame.minY + 24))
        save()
    }
    @objc func quit() { save(); NSApp.terminate(nil) }
    func makeMenu() -> NSMenu {
        let menu = NSMenu()
        func add(_ title: String, _ action: Selector) { let item = NSMenuItem(title: title, action: action, keyEquivalent: ""); item.target = self; menu.addItem(item) }
        add("邦友跳舞", #selector(changeDanceMode))
        menu.items.last?.state = danceMode ? .on : .off
        menu.addItem(.separator())
        add(player.isPlaying ? "暂停播放" : "播放 / 继续播放", #selector(toggle))
        add("从头开始播放音频", #selector(restart))
        menu.addItem(.separator())
        let volumeItem = NSMenuItem(title: "音量", action: nil, keyEquivalent: "")
        let sub = NSMenu()
        for v in [0,25,50,75,100] { let i = NSMenuItem(title: "\(v)%", action: #selector(volume(_:)), keyEquivalent: ""); i.target = self; i.tag = v; i.state = abs(player.volume-Float(v)/100)<0.01 ? .on : .off; sub.addItem(i) }
        volumeItem.submenu = sub; menu.addItem(volumeItem)
        let sizeItem = NSMenuItem(title: "头像大小", action: nil, keyEquivalent: "")
        let sizes = NSMenu()
        for (width, label) in [(160, "小"), (220, "中"), (280, "标准"), (360, "大")] {
            let item = NSMenuItem(title: label, action: #selector(resize(_:)), keyEquivalent: "")
            item.target = self; item.tag = width
            item.state = abs(panel.frame.width-CGFloat(width)) < 1 ? .on : .off
            sizes.addItem(item)
        }
        sizeItem.submenu = sizes; menu.addItem(sizeItem)
        add("移回屏幕左下角", #selector(moveToBottomLeft))
        menu.addItem(.separator()); add("关闭桌宠", #selector(quit)); return menu
    }
    func save() {
        guard player != nil, panel != nil, !CommandLine.arguments.contains("--self-test") else { return }
        prefs.set(normalPlayer.currentTime, forKey: "position"); prefs.set(bangyouPlayer.currentTime, forKey: "bangyouPosition"); prefs.set(player.volume, forKey: "volume")
        prefs.set(panel.frame.origin.x, forKey: "x"); prefs.set(panel.frame.origin.y, forKey: "y")
    }
    func applicationWillTerminate(_ notification: Notification) { save(); player?.pause(); if player != nil { broadcast() } }
    func selfTest() {
        normalPlayer.volume = 0; bangyouPlayer.volume = 0
        precondition(!rhythm.beats.isEmpty)
        let synthetic = Rhythm(beats: [Beat(time: 1, strength: 1), Beat(time: 1.5, strength: 1), Beat(time: 2, strength: 0.5)])
        precondition(synthetic.pose(at: 0.9).0 == 1)
        precondition(synthetic.pose(at: 1.12).0 < 0.9)
        precondition(synthetic.pose(at: 1.36).1 > 0)
        precondition(synthetic.pose(at: 1.62).0 < 1)
        precondition(abs(synthetic.pose(at: 2.12).0 - synthetic.pose(at: 1.12).0) < 0.0001)
        precondition(player.duration > 0 && player.numberOfLoops == -1)
        player.currentTime = min(2, player.duration/2)
        toggle(); precondition(player.isPlaying && view.isPlaying && view.playingPortrait != nil)
        toggle(); let paused = player.currentTime; precondition(!player.isPlaying && !view.isPlaying)
        toggle(); precondition(player.isPlaying && abs(player.currentTime-paused)<0.15)
        restart(); precondition(player.isPlaying && player.currentTime<0.15)
        player.currentTime = player.duration - 0.08
        RunLoop.current.run(until: Date().addingTimeInterval(0.3))
        precondition(player.isPlaying && player.currentTime<0.5)
        toggle(); animate(); precondition(view.compression == 1 && view.lift == 0)
        precondition(makeMenu().items.contains { $0.title == "从头开始播放音频" })
        precondition(makeMenu().items.contains { $0.title == "音量" })
        precondition(makeMenu().items.contains { $0.title == "头像大小" })
        precondition(makeMenu().items.contains { $0.title == "移回屏幕左下角" })
        precondition(makeMenu().items.contains { $0.title == "关闭桌宠" })

        changeDanceMode()
        precondition(danceMode && view.danceMode && player === bangyouPlayer && !player.isPlaying)
        precondition(!bangyouRhythm.beats.isEmpty && bangyouPlayer.duration > 1)
        view.layoutSubtreeIfNeeded()
        if let bitmap = view.bitmapImageRepForCachingDisplay(in: view.bounds) {
            view.cacheDisplay(in: view.bounds, to: bitmap)
            try? bitmap.representation(using: .png, properties: [:])?.write(to: URL(fileURLWithPath: "/private/tmp/xujiayin-bangyou-preview.png"))
        }
        toggle(); precondition(player.isPlaying && view.danceMode)
        if ProcessInfo.processInfo.environment["DESKTOP_PET_DANCE_STATE"] != nil {
            let state = try! JSONDecoder().decode(DanceState.self, from: Data(contentsOf: DanceBus.url))
            precondition(state.playing && abs(state.duration-bangyouPlayer.duration)<0.1)
        }
        toggle(); precondition(!player.isPlaying && view.danceMode)
        if ProcessInfo.processInfo.environment["DESKTOP_PET_DANCE_STATE"] != nil {
            let state = try! JSONDecoder().decode(DanceState.self, from: Data(contentsOf: DanceBus.url))
            precondition(!state.playing)
        }
        changeDanceMode(); precondition(!danceMode && player === normalPlayer)
        print("PASS: dance mode, image switching, two audio tracks, pause/resume, restart, automatic looping, idle animation, menu. Audio duration: \(player.duration)s")
        NSApp.terminate(nil)
    }
}
let app = NSApplication.shared
app.setActivationPolicy(.accessory)
let delegate = Controller()
app.delegate = delegate
app.run()

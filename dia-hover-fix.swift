// dia-hover-fix: brings hover back in Dia after it leaves fullscreen.
//
// On macOS 27.0.1 with Dia 1.52 (Chromium 155), leaving fullscreen (a video's fullscreen button or
// Esc) with the cursor over the window stops AppKit delivering mouse moves to the page. Hover dies
// until the window is re-shown (Mission Control, switching Spaces). Clicks still work. This is the
// AppKit bug in electron/electron#54816. Measured 19.10.2026: four out of four exits killed hover.
// Activating another app and then Dia again did not bring it back. Showing a tiny, nearly invisible
// window from another process under the cursor for 150 ms did.
//
// While Dia is the active app, this polls Dia's large on-screen windows four times a second. When
// their layout changes and settles with the cursor over Dia, it shows that window twice, 1 s apart.
// It needs no permissions: window bounds, cursor position and button state are all public.
//
// Build: swiftc -O -swift-version 5 -o dia-hover-fix dia-hover-fix.swift
// Run:   dia-hover-fix [log file]   (default ~/Library/Logs/dia-hover-fix.log)

import AppKit

let diaBundleID = "company.thebrowser.dia"
let pollInterval: TimeInterval = 0.25
let minWindowWidth: CGFloat = 600
let flashSize: CGFloat = 40
let flashDuration: TimeInterval = 0.15
let flashDelays: [TimeInterval] = [0, 1]
let maxLogBytes = 512 * 1024

final class Log {
    private let handle: FileHandle?
    private let formatter = DateFormatter()
    private var written = 0

    init(path: String) {
        let fm = FileManager.default
        if let size = (try? fm.attributesOfItem(atPath: path))?[.size] as? Int, size > maxLogBytes {
            try? fm.removeItem(atPath: path)
        }
        if !fm.fileExists(atPath: path) { fm.createFile(atPath: path, contents: nil) }
        handle = FileHandle(forWritingAtPath: path)
        handle?.seekToEndOfFile()
        formatter.dateFormat = "yyyy-MM-dd HH:mm:ss.SSS"
    }

    func write(_ line: String) {
        guard let handle, let data = "\(formatter.string(from: Date())) \(line)\n".data(using: .utf8) else { return }
        written += data.count
        if written > maxLogBytes {
            handle.truncateFile(atOffset: 0)
            written = data.count
        }
        handle.write(data)
    }
}

final class HoverFixer {
    private let log: Log
    private let panel: NSPanel
    private var timer: Timer?
    private var diaPID: pid_t = 0
    private var settled: String?
    private var candidate: String?
    private var candidateCount = 0
    private var pendingFlashes: [Date] = []

    init(log: Log) {
        self.log = log
        // Takes mouse events, so the window server sees the cursor leave Dia's window and come
        // back. 4% grey keeps it hit-testable without being noticeable.
        panel = NSPanel(contentRect: NSRect(x: 0, y: 0, width: flashSize, height: flashSize),
                        styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: false)
        panel.level = NSWindow.Level(rawValue: 1000)
        panel.isOpaque = false
        panel.hasShadow = false
        panel.ignoresMouseEvents = false
        panel.backgroundColor = NSColor(calibratedWhite: 0.5, alpha: 0.04)
    }

    func start() {
        NSWorkspace.shared.notificationCenter.addObserver(
            forName: NSWorkspace.didActivateApplicationNotification, object: nil, queue: .main
        ) { [weak self] note in
            self?.activeAppChanged(note.userInfo?[NSWorkspace.applicationUserInfoKey] as? NSRunningApplication)
        }
        activeAppChanged(NSWorkspace.shared.frontmostApplication)
    }

    // Polls only while Dia is active, from a fresh baseline, so switching to Dia never counts as a
    // layout change.
    private func activeAppChanged(_ app: NSRunningApplication?) {
        timer?.invalidate()
        timer = nil
        settled = nil
        candidate = nil
        candidateCount = 0
        pendingFlashes = []
        guard let app, app.bundleIdentifier == diaBundleID else { return }
        diaPID = app.processIdentifier
        timer = Timer.scheduledTimer(withTimeInterval: pollInterval, repeats: true) { [weak self] _ in
            self?.poll()
        }
    }

    private func poll() {
        let windows = diaLargeWindows()
        let layout = windows
            .map { "\(Int($0.width))x\(Int($0.height))@\(Int($0.minX)),\(Int($0.minY))" }
            .sorted()
            .joined(separator: " ")
        if layout == candidate { candidateCount += 1 } else { candidate = layout; candidateCount = 1 }

        // A layout counts once it has held for two polls, and only between two on-screen layouts.
        if candidateCount == 2 && layout != settled {
            let previous = settled
            settled = layout
            if let previous, !previous.isEmpty, !layout.isEmpty {
                let now = Date()
                pendingFlashes = flashDelays.map { now.addingTimeInterval($0) }
                log.write("layout \(previous) -> \(layout)")
            }
        }

        guard let next = pendingFlashes.first, Date() >= next else { return }
        if layout.isEmpty { pendingFlashes = []; return }
        if CGEventSource.buttonState(.combinedSessionState, button: .left) { return }
        pendingFlashes.removeFirst()
        if cursorIsOver(windows) {
            flash()
            log.write("flash")
        }
    }

    // Dia's normal-level on-screen windows wide enough to be browser windows or their fullscreen
    // toolbar, in global top-left coordinates.
    private func diaLargeWindows() -> [CGRect] {
        let options: CGWindowListOption = [.optionOnScreenOnly, .excludeDesktopElements]
        guard let list = CGWindowListCopyWindowInfo(options, kCGNullWindowID) as? [[String: Any]] else { return [] }
        return list.compactMap { info in
            guard (info[kCGWindowOwnerPID as String] as? Int).map(pid_t.init) == diaPID,
                  info[kCGWindowLayer as String] as? Int == 0,
                  let bounds = info[kCGWindowBounds as String],
                  let rect = CGRect(dictionaryRepresentation: bounds as! CFDictionary),
                  rect.width >= minWindowWidth
            else { return nil }
            return rect
        }
    }

    private func cursorIsOver(_ windows: [CGRect]) -> Bool {
        guard let point = CGEvent(source: nil)?.location else { return false }
        return windows.contains { $0.contains(point) }
    }

    private func flash() {
        let mouse = NSEvent.mouseLocation // bottom-left origin, like window frames
        panel.setFrameOrigin(NSPoint(x: mouse.x - flashSize / 2, y: mouse.y - flashSize / 2))
        panel.orderFrontRegardless()
        DispatchQueue.main.asyncAfter(deadline: .now() + flashDuration) { [panel] in
            panel.orderOut(nil)
        }
    }
}

let logPath = CommandLine.arguments.dropFirst().first ?? NSHomeDirectory() + "/Library/Logs/dia-hover-fix.log"
let log = Log(path: logPath)
let app = NSApplication.shared
app.setActivationPolicy(.accessory)
let fixer = HoverFixer(log: log)
fixer.start()
log.write("started")
app.run()

import AppKit
import SwiftUI
import Carbon

@MainActor
final class ApplicationDelegate: NSObject, NSApplicationDelegate, NSWindowDelegate {
    private var model: AppModel!
    private var window: NSWindow!
    private var item: NSStatusItem!
    private var hotkeys: GlobalHotkeys?
    func applicationDidFinishLaunching(_ notification: Notification) {
        model = AppModel()
        if CommandLine.arguments.contains("--video-tab") { model.mode = .video }
        window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 1140, height: 820),
            styleMask: [.titled, .closable, .miniaturizable, .resizable], backing: .buffered, defer: false)
        window.title = "DLSS 5 — Apple Silicon"
        window.contentView = NSHostingView(rootView: ControlsView(model: model))
        window.minSize = NSSize(width: 940, height: 650)
        window.level = .normal
        window.delegate = self
        window.isReleasedWhenClosed = false; window.center()
        installMenus(); showControls()
        hotkeys = GlobalHotkeys { [weak self] id in
            guard let self else { return }
            if id == 1 { Task { await self.model.stopAll() } }
            if id == 2, self.model.running { self.model.overlayEnabled.toggle() }
        }
        if hotkeys?.registered != 2 { model.error = "Global shortcuts are in use by another application. Use the DLSS menu in the menu bar to stop processing." }
        Task { await model.initialize() }
    }
    private func installMenus() {
        let menu = NSMenu()
        for (title, action, key) in [("Show Controls", #selector(showControls), ""),
                                     ("Stop Processing", #selector(stopCapture), "0"),
                                     ("Quit", #selector(quit), "q")] {
            let entry = NSMenuItem(title: title, action: action, keyEquivalent: key)
            entry.target = self; menu.addItem(entry)
        }
        item = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        item.button?.title = "DLSS"; item.menu = menu
        let main = NSMenu()
        let app = NSMenuItem(); app.submenu = menu.copy() as? NSMenu; main.addItem(app)
        let edit = NSMenuItem(title: "Edit", action: nil, keyEquivalent: "")
        let editMenu = NSMenu(title: "Edit")
        editMenu.addItem(withTitle: "Copy", action: #selector(NSText.copy(_:)), keyEquivalent: "c")
        editMenu.addItem(withTitle: "Paste", action: #selector(NSText.paste(_:)), keyEquivalent: "v")
        editMenu.addItem(withTitle: "Select All", action: #selector(NSText.selectAll(_:)), keyEquivalent: "a")
        edit.submenu = editMenu; main.addItem(edit); NSApplication.shared.mainMenu = main
    }
    @objc private func showControls() {
        // Raise the controls only while the user is interacting with them. The
        // game regains the foreground as soon as this window loses focus.
        window.level = NSWindow.Level(rawValue: NSWindow.Level.floating.rawValue + 1)
        window.makeKeyAndOrderFront(nil); NSApplication.shared.activate(ignoringOtherApps: true)
    }
    func windowDidResignKey(_ notification: Notification) { window.level = .normal }
    @objc private func stopCapture() { Task { await model.stopAll() } }
    @objc private func quit() { NSApplication.shared.terminate(nil) }
    func applicationShouldTerminate(_ sender: NSApplication) -> NSApplication.TerminateReply {
        Task { await model.stopAll(); sender.reply(toApplicationShouldTerminate: true) }
        return .terminateLater
    }
    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool { false }
    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool { showControls(); return true }
}

@MainActor
final class GlobalHotkeys {
    private var handler: EventHandlerRef?
    private var refs = [EventHotKeyRef]()
    var registered: Int { refs.count }
    private let action: (UInt32) -> Void
    init(action: @escaping (UInt32) -> Void) {
        self.action = action
        var type = EventTypeSpec(eventClass: OSType(kEventClassKeyboard), eventKind: UInt32(kEventHotKeyPressed))
        InstallEventHandler(GetApplicationEventTarget(), { _, event, context in
            guard let event, let context else { return OSStatus(eventNotHandledErr) }
            var id = EventHotKeyID()
            GetEventParameter(event, EventParamName(kEventParamDirectObject), EventParamType(typeEventHotKeyID), nil,
                              MemoryLayout<EventHotKeyID>.size, nil, &id)
            let target = Unmanaged<GlobalHotkeys>.fromOpaque(context).takeUnretainedValue()
            let number = id.id
            Task { @MainActor in target.action(number) }
            return noErr
        }, 1, &type, Unmanaged.passUnretained(self).toOpaque(), &handler)
        for (id, key) in [(UInt32(1), UInt32(kVK_ANSI_0)), (UInt32(2), UInt32(kVK_ANSI_1))] {
            var ref: EventHotKeyRef?
            if RegisterEventHotKey(key, UInt32(cmdKey | optionKey), EventHotKeyID(signature: 0x444C5353, id: id),
                                  GetApplicationEventTarget(), 0, &ref) == noErr, let ref { refs.append(ref) }
        }
    }
    deinit { for ref in refs { UnregisterEventHotKey(ref) }; if let handler { RemoveEventHandler(handler) } }
}

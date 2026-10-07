import SwiftUI
import AppKit
import AVFoundation
import Speech
import Combine
import CoreGraphics
import ApplicationServices
import Carbon.HIToolbox
import ServiceManagement
import CoreAudio
import AudioToolbox

// MARK: - App entry

@main
struct LokaahTalkyApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate

    var body: some Scene {
        // No default window. the floating panel is created by the AppDelegate so
        // it can be a non-activating HUD that never steals focus from your terminal.
        Settings { EmptyView() }
    }
}

// MARK: - App delegate / floating panel

final class AppDelegate: NSObject, NSApplicationDelegate {
    private var panel: FloatingPanel?
    let speech = SpeechManager()
    private var hotKey: GlobalHotKey?
    private var cancelHotKey: GlobalHotKey?
    private var sizeObserver: AnyCancellable?

    /// Resize the panel between the compact presence and the full HUD, anchored
    /// on its center so it blooms in place.
    private func setPanelExpanded(_ expanded: Bool) {
        guard let panel else { return }
        let size = expanded ? NSSize(width: 380, height: 640) : NSSize(width: 230, height: 64)
        let f = panel.frame
        let origin = NSPoint(x: f.midX - size.width / 2, y: f.midY - size.height / 2)
        let target = NSRect(origin: origin, size: size)
        NSAnimationContext.runAnimationGroup { ctx in
            ctx.duration = 0.22
            panel.animator().setFrame(target, display: true)
        }
    }

    func applicationDidFinishLaunching(_ notification: Notification) {
        // Accessory app: no Dock icon, no menu bar. and crucially, interacting
        // with our panel does not activate us over the user's active window.
        NSApp.setActivationPolicy(.accessory)

        let panel = FloatingPanel()
        panel.contentView = FirstMouseHostingView(rootView: RootView(speech: speech))
        panel.center()
        panel.orderFrontRegardless()
        self.panel = panel

        // Global hotkey: ⌥Space starts/stops dictation from anywhere, hands-free.
        hotKey = GlobalHotKey(keyCode: UInt32(kVK_Space), modifiers: UInt32(optionKey)) { [weak self] in
            self?.speech.toggle()
        }
        speech.shortcutAvailable = hotKey?.isRegistered == true
        cancelHotKey = GlobalHotKey(keyCode: UInt32(kVK_Escape), modifiers: UInt32(optionKey)) { [weak self] in
            self?.speech.cancel()
        }

        // Lets Hermes / scripts drive dictation by writing start/stop/toggle to
        // ~/.talky/talky_cmd (also used for automated testing).
        speech.startCommandWatcher()

        // Grow/shrink the window as the app expands and minimizes.
        sizeObserver = speech.$expanded
            .removeDuplicates()
            .sink { [weak self] expanded in self?.setPanelExpanded(expanded) }

        speech.prepare()
    }

    func applicationSupportsSecureRestorableState(_ app: NSApplication) -> Bool { true }

    func applicationWillTerminate(_ notification: Notification) { speech.cancel() }
}

/// Temporarily lowers the always-on-top panel so a system permission dialog can
/// appear in front of it instead of being hidden behind the floating HUD.
enum PanelChrome {
    static func dropForPrompt(seconds: Double = 10) {
        guard let panel = NSApp.windows.first(where: { $0 is FloatingPanel }) else { return }
        panel.level = .normal
        DispatchQueue.main.asyncAfter(deadline: .now() + seconds) {
            (NSApp.windows.first(where: { $0 is FloatingPanel }))?.level = .floating
        }
    }
}

/// A system-wide hotkey using Carbon's RegisterEventHotKey, which intercepts the
/// key combo globally without needing Accessibility permission.
final class GlobalHotKey {
    private static var nextID: UInt32 = 0
    private let id: UInt32
    private(set) var isRegistered = false
    private var hotKeyRef: EventHotKeyRef?
    private var handlerRef: EventHandlerRef?
    private let action: @MainActor () -> Void

    init(keyCode: UInt32, modifiers: UInt32, action: @escaping @MainActor () -> Void) {
        self.action = action
        GlobalHotKey.nextID += 1
        id = GlobalHotKey.nextID

        var spec = EventTypeSpec(eventClass: OSType(kEventClassKeyboard),
                                 eventKind: OSType(kEventHotKeyPressed))
        InstallEventHandler(GetApplicationEventTarget(), { _, event, context in
            guard let event, let context else { return OSStatus(eventNotHandledErr) }
            var keyID = EventHotKeyID()
            guard GetEventParameter(event, EventParamName(kEventParamDirectObject), EventParamType(typeEventHotKeyID),
                    nil, MemoryLayout<EventHotKeyID>.size, nil, &keyID) == noErr else { return OSStatus(eventNotHandledErr) }
            return MainActor.assumeIsolated {
                let owner = Unmanaged<GlobalHotKey>.fromOpaque(context).takeUnretainedValue()
                guard keyID.signature == OSType(0x484B_4559), keyID.id == owner.id else { return OSStatus(eventNotHandledErr) }
                owner.action()
                return noErr
            }
        }, 1, &spec, Unmanaged.passUnretained(self).toOpaque(), &handlerRef)

        let keyID = EventHotKeyID(signature: OSType(0x484B_4559), id: id)
        isRegistered = RegisterEventHotKey(keyCode, modifiers, keyID, GetApplicationEventTarget(), 0, &hotKeyRef) == noErr
    }

    deinit {
        if let hotKeyRef { UnregisterEventHotKey(hotKeyRef) }
        if let handlerRef { RemoveEventHandler(handlerRef) }
    }
}

/// Hosting view that lets the very first click reach SwiftUI controls. Without
/// this, a non-activating panel swallows the first click just to become key, so
/// the orb needs two taps and feels unresponsive.
final class FirstMouseHostingView: NSHostingView<RootView> {
    required init(rootView: RootView) { super.init(rootView: rootView) }
    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }
    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }
}

/// Borderless, translucent, always-on-top panel that floats above other apps
/// without activating our process when clicked.
final class FloatingPanel: NSPanel {
    init() {
        super.init(
            contentRect: NSRect(x: 0, y: 0, width: 230, height: 64),
            styleMask: [.borderless, .nonactivatingPanel, .fullSizeContentView],
            backing: .buffered,
            defer: false
        )
        isFloatingPanel = true
        level = .floating
        collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .stationary]
        titleVisibility = .hidden
        titlebarAppearsTransparent = true
        isMovableByWindowBackground = true
        backgroundColor = .clear
        isOpaque = false
        hasShadow = true
        animationBehavior = .utilityWindow
    }

    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { false }
}

// MARK: - Color helper

extension Color {
    init(hex: UInt) {
        self.init(.sRGB,
                  red: Double((hex >> 16) & 0xFF) / 255,
                  green: Double((hex >> 8) & 0xFF) / 255,
                  blue: Double(hex & 0xFF) / 255,
                  opacity: 1)
    }
}

/// Phosphor-terminal palette.
enum Phos {
    static let green = Color(hex: 0x39FF14)
    static let amber = Color(hex: 0xFFB000)
}

/// One past dictation, for the history viewer.
struct HistoryItem: Identifiable {
    let id: String
    let date: String
    let time: String
    let text: String
}

// MARK: - Root view

struct RootView: View {
    @ObservedObject var speech: SpeechManager
    private enum Page { case dictate, history, settings }
    @State private var page: Page = .dictate
    @State private var historyItems: [HistoryItem] = []
    @State private var historySearch = ""
    @State private var confirmClearHistory = false

    var body: some View {
        Group { if speech.expanded { fullPanel } else { compactWidget } }
            .environment(\.colorScheme, .dark)
            .onAppear { speech.prepare() }
            .onChange(of: speech.phase) { _, phase in
                if phase == .idle && page == .history { historyItems = speech.loadHistory() }
            }
            .confirmationDialog("Delete all saved local dictation history?", isPresented: $confirmClearHistory) {
                Button("Delete history", role: .destructive) { speech.clearHistory(); historyItems = [] }
                Button("Cancel", role: .cancel) {}
            } message: { Text("This removes the history files from this Mac. Clipboard contents and exported files are separate.") }
    }

    private var compactWidget: some View {
        HStack(spacing: 10) {
            Button { speech.toggle() } label: {
                HStack(spacing: 10) {
                    if speech.isListening { MiniWaveform(level: speech.audioLevel).frame(width: 26, height: 26) }
                    else if speech.phase == .processing { ProgressView().controlSize(.small).frame(width: 26) }
                    else { Image(systemName: speech.needsSetup ? "mic.badge.xmark" : "mic.fill").foregroundStyle(speech.needsSetup ? Phos.amber : Phos.green).frame(width: 26) }
                    Text(compactLabel).font(.system(size: 12, weight: .medium)).lineLimit(2).frame(maxWidth: .infinity, alignment: .leading)
                }.contentShape(Rectangle())
            }
            .buttonStyle(.plain).disabled(speech.phase == .processing)
            .accessibilityLabel(speech.isListening ? "Stop dictation" : "Start dictation")
            .help(speech.statusMessage)
            if speech.isBusy {
                Button { speech.cancel() } label: { Image(systemName: "xmark.circle.fill").foregroundStyle(Phos.amber) }
                    .buttonStyle(.plain).accessibilityLabel("Cancel without sending").help("Cancel: Option-Escape")
            }
            Button { speech.expanded = true } label: { Image(systemName: "arrow.up.left.and.arrow.down.right").font(.system(size: 10, weight: .bold)) }
                .buttonStyle(.plain).accessibilityLabel("Open Talky").help("Open controls and settings")
        }
        .padding(.horizontal, 14).frame(width: 230, height: 64)
        .background(background)
    }

    private var compactLabel: String {
        if speech.isListening { return "Listening" }
        if speech.phase == .processing { return "Finishing transcript" }
        if speech.needsSetup { return "Set up Talky" }
        if speech.phase == .unavailable { return "Open settings" }
        return speech.statusMessage == "Option-Space to dictate" ? "Talky · Option-Space" : speech.statusMessage
    }

    private var fullPanel: some View {
        VStack(alignment: .leading, spacing: 14) {
            header
            HStack(spacing: 5) {
                Image(systemName: "lock.shield.fill")
                Text("On-device · \(speech.languageName)")
            }.font(.system(size: 11)).foregroundStyle(.secondary)

            if speech.needsSetup && page == .dictate { setupView }
            else {
                switch page {
                case .dictate: dictationView
                case .history: historyView
                case .settings: settingsView
                }
            }
            Spacer(minLength: 0)
            Text(speech.statusMessage)
                .font(.system(size: 11)).foregroundStyle(statusColor)
                .lineLimit(3).fixedSize(horizontal: false, vertical: true)
                .accessibilityLabel("Status: " + speech.statusMessage)
            captureControls
        }
        .padding(20).frame(width: 380, height: 640)
        .background(background)
    }

    private var header: some View {
        HStack(spacing: 8) {
            Text("Talky").font(.system(size: 21, weight: .semibold, design: .rounded)).foregroundStyle(Phos.green)
            Spacer()
            iconButton("waveform", "Dictation", selected: page == .dictate) { page = .dictate }
            iconButton("clock.arrow.circlepath", "History", selected: page == .history) { page = .history; historyItems = speech.loadHistory() }
            iconButton("gearshape", "Settings", selected: page == .settings) { page = .settings }
            iconButton("arrow.down.right.and.arrow.up.left", "Minimize") { speech.expanded = false }
            iconButton("xmark", "Quit Talky") { NSApp.terminate(nil) }
        }
    }

    private func iconButton(_ symbol: String, _ title: String, selected: Bool = false, action: @escaping () -> Void) -> some View {
        Button(action: action) { Image(systemName: symbol).font(.system(size: 12, weight: .medium)).frame(width: 26, height: 28).foregroundStyle(selected ? Phos.green : Color.white.opacity(0.65)) }
            .buttonStyle(.plain).help(title).accessibilityLabel(title)
    }

    private var dictationView: some View {
        VStack(alignment: .leading, spacing: 16) {
            Waveform(levels: speech.levels, phase: speech.phase).frame(height: 76).accessibilityHidden(true)
            HStack {
                Text(speech.isListening ? "LIVE TRANSCRIPT" : "TRANSCRIPT").font(.system(size: 10, weight: .semibold)).foregroundStyle(.secondary)
                Spacer()
                if !speech.transcribedText.isEmpty {
                    Button { speech.copy(speech.transcribedText) } label: { Label("Copy", systemImage: "doc.on.doc") }.buttonStyle(.borderless)
                }
            }
            ScrollViewReader { proxy in
                ScrollView {
                    Text(speech.transcribedText.isEmpty ? "Speak naturally. Your words will appear here.\n\nOption-Space starts and stops.\nOption-Escape cancels without sending." : speech.transcribedText)
                        .font(.system(size: 15)).lineSpacing(4).textSelection(.enabled)
                        .foregroundStyle(speech.transcribedText.isEmpty ? .secondary : .primary)
                        .frame(maxWidth: .infinity, alignment: .leading)
                    Color.clear.frame(height: 1).id("transcript-end")
                }.frame(height: 220)
                    .onChange(of: speech.transcribedText) { _, _ in proxy.scrollTo("transcript-end", anchor: .bottom) }
            }
            HStack {
                Label(speech.microphoneName, systemImage: "mic").lineLimit(1)
                Spacer()
                if speech.saveHistory { Label("History on", systemImage: "clock") }
                else { Label("History off", systemImage: "eye.slash") }
            }.font(.system(size: 10)).foregroundStyle(.secondary)
            if !speech.accessibilityAllowed {
                Button("Enable Accessibility for automatic paste") { speech.requestAccessibilityPermission() }
                    .buttonStyle(.borderless).font(.system(size: 12))
                Text("Dictation still works in clipboard mode.").font(.system(size: 11)).foregroundStyle(.secondary)
            }
        }
    }

    private var setupView: some View {
        VStack(alignment: .leading, spacing: 18) {
            Text("Welcome to Talky").font(.title3.bold())
            Text("Allow microphone and speech access to dictate. Recognition stays on this Mac. Accessibility is optional and lets Talky paste for you.")
                .font(.system(size: 13)).foregroundStyle(.secondary)
            permissionRow("Microphone", description: "Listens only while you record", granted: speech.microphoneAllowed, action: speech.requestMicrophonePermission)
            permissionRow("Speech recognition", description: "Uses Apple's on-device model", granted: speech.speechAllowed, action: speech.requestSpeechPermission)
            permissionRow("Accessibility", description: "Pastes into the original text field", granted: speech.accessibilityAllowed, action: speech.requestAccessibilityPermission)
            Text("On a fresh installation, history and automation output start off. Completed regular dictation is copied to your clipboard.")
                .font(.system(size: 11)).foregroundStyle(.secondary)
            Button("Check permissions again") { speech.refreshPermissions() }.buttonStyle(.borderless)
        }.padding(.vertical, 12)
    }

    private func permissionRow(_ title: String, description: String, granted: Bool, action: @escaping () -> Void) -> some View {
        HStack(spacing: 12) {
            Image(systemName: granted ? "checkmark.circle.fill" : "circle").foregroundStyle(granted ? Phos.green : Phos.amber)
            VStack(alignment: .leading, spacing: 3) { Text(title).font(.system(size: 13, weight: .medium)); Text(description).font(.system(size: 11)).foregroundStyle(.secondary) }
            Spacer()
            if !granted { Button("Allow", action: action).controlSize(.small) }
        }
    }

    private var settingsView: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 15) {
                Text("DICTATION").font(.system(size: 10, weight: .semibold)).foregroundStyle(.secondary)
                Picker("Language", selection: $speech.languageIdentifier) {
                    ForEach(speech.languages, id: \.identifier) { locale in Text(locale.localizedName).tag(locale.identifier) }
                }.disabled(speech.isBusy)
                Text(speech.localRecognitionAvailable ? "Local recognition is available." : "This language needs an installed on-device model. No cloud fallback is used.")
                    .font(.system(size: 11)).foregroundStyle(speech.localRecognitionAvailable ? .secondary : Color.orange)
                Toggle("Paste automatically", isOn: $speech.autoPaste)
                Toggle("Press Return after paste", isOn: $speech.autoSubmit).disabled(!speech.autoPaste)
                Text("Return can send a message or run a terminal command. It is sent only while the original field remains focused.")
                    .font(.system(size: 11)).foregroundStyle(.secondary)
                Text("Names and technical terms").font(.system(size: 12, weight: .medium))
                TextEditor(text: $speech.vocabulary).font(.system(size: 12)).frame(height: 60).disabled(speech.isBusy)
                    .overlay(RoundedRectangle(cornerRadius: 5).stroke(.white.opacity(0.15)))
                    .accessibilityLabel("Vocabulary, one phrase per line")
                Text("One phrase per line. These hints stay on this Mac.").font(.system(size: 11)).foregroundStyle(.secondary)
                Divider()
                Text("PRIVACY").font(.system(size: 10, weight: .semibold)).foregroundStyle(.secondary)
                Toggle("Save local history", isOn: $speech.saveHistory)
                if speech.saveHistory {
                    Picker("Keep history", selection: $speech.historyRetentionDays) {
                        Text("1 day").tag(1); Text("7 days").tag(7); Text("30 days").tag(30); Text("Until I delete it").tag(0)
                    }
                }
                Toggle("Write latest transcript for scripts", isOn: $speech.writeLatestTranscript)
                Text("History is local and unencrypted. Automation writes ~/.talky/voice_input.txt. Clipboard contents can be read by other apps.")
                Text("Turning history off stops new saves. Delete saved records in History. Exports and clipboard copies are separate.")
                    .font(.system(size: 11)).foregroundStyle(.secondary)
                    .font(.system(size: 11)).foregroundStyle(.secondary)
                Divider()
                Toggle("Launch at login", isOn: Binding(get: { speech.launchAtLogin }, set: speech.setLaunchAtLogin))
                if !speech.shortcutAvailable { Text("Option-Space is already in use. The record button still works.").font(.system(size: 11)).foregroundStyle(Phos.amber) }
                if !speech.accessibilityAllowed { Button("Open Accessibility settings") { speech.requestAccessibilityPermission() }.buttonStyle(.borderless) }
            }.font(.system(size: 13)).padding(.vertical, 4)
        }.frame(maxHeight: 420)
    }

    private var historyView: some View {
        VStack(alignment: .leading, spacing: 10) {
            TextField("Search history", text: $historySearch).textFieldStyle(.roundedBorder)
            HStack {
                Button("Export") { speech.exportHistory() }.disabled(historyItems.isEmpty)
                Spacer()
                Button("Delete history", role: .destructive) { confirmClearHistory = true }.disabled(historyItems.isEmpty)
            }.controlSize(.small)
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 16) {
                    if historyItems.isEmpty {
                        Text(speech.saveHistory ? "No saved dictations yet." : "History is off. Enable it in Settings if you want to save dictations.")
                            .font(.system(size: 13)).foregroundStyle(.secondary).padding(.vertical, 20)
                    }
                    ForEach(historyItems.filter { historySearch.isEmpty || $0.text.localizedCaseInsensitiveContains(historySearch) || $0.date.localizedCaseInsensitiveContains(historySearch) }) { item in
                        VStack(alignment: .leading, spacing: 5) {
                            HStack { Text(item.date + " · " + item.time).font(.system(size: 10)).foregroundStyle(.secondary); Spacer(); Button { speech.copy(item.text) } label: { Image(systemName: "doc.on.doc") }.buttonStyle(.borderless).accessibilityLabel("Copy dictation") }
                            Text(item.text).font(.system(size: 13)).textSelection(.enabled).frame(maxWidth: .infinity, alignment: .leading)
                        }
                    }
                }
            }.frame(maxHeight: 345)
        }
    }

    private var captureControls: some View {
        HStack(spacing: 10) {
            Button { speech.toggle() } label: {
                Label(speech.isListening ? "Stop dictation" : speech.phase == .processing ? "Finishing..." : "Start dictation",
                      systemImage: speech.isListening ? "stop.fill" : "mic.fill")
                    .frame(maxWidth: .infinity).padding(.vertical, 7)
            }.buttonStyle(.borderedProminent).tint(Phos.green).foregroundStyle(.black)
                .disabled(speech.phase == .processing || speech.needsSetup)
                .accessibilityHint("Option-Space")
            if speech.isBusy {
                Button("Cancel") { speech.cancel() }.buttonStyle(.bordered).keyboardShortcut(.cancelAction)
                    .help("Discard without copying or sending: Option-Escape")
            }
        }
    }

    private var statusColor: Color { speech.phase == .denied || speech.phase == .unavailable ? Phos.amber : .secondary }
    private var background: some View {
        RoundedRectangle(cornerRadius: 18).fill(.ultraThinMaterial)
            .overlay(RoundedRectangle(cornerRadius: 18).fill(.black.opacity(0.65)))
            .overlay(RoundedRectangle(cornerRadius: 18).stroke(Phos.green.opacity(speech.isListening ? 0.7 : 0.25), lineWidth: 1))
    }
}

// MARK: - Waveform. audio-reactive phosphor equalizer

// Clean 5-bar mini waveform for the compact widget; reacts to the mic level.
struct MiniWaveform: View {
    var level: CGFloat
    private let shape: [CGFloat] = [0.45, 0.8, 1.0, 0.7, 0.5]
    var body: some View {
        HStack(spacing: 3) {
            ForEach(0..<5, id: \.self) { i in
                Capsule()
                    .fill(Phos.green)
                    .frame(width: 3.5, height: 5 + min(1, max(0, level)) * 19 * shape[i])
                    .shadow(color: Phos.green.opacity(0.7), radius: 2)
            }
        }
        .frame(width: 26, height: 26)
        .animation(.easeOut(duration: 0.1), value: level)
    }
}

struct Waveform: View {
    var levels: [CGFloat]
    var phase: SpeechManager.Phase

    private var active: Bool { phase == .listening }
    private var muted: Bool { phase == .denied || phase == .unavailable }

    var body: some View {
        GeometryReader { geo in
            let n = max(levels.count, 1)
            let spacing: CGFloat = 5
            let barW = max(2, (geo.size.width - CGFloat(n - 1) * spacing) / CGFloat(n))
            HStack(alignment: .center, spacing: spacing) {
                ForEach(0..<n, id: \.self) { i in
                    Capsule()
                        .fill(barColor)
                        .frame(width: barW, height: barHeight(levels[i], geo.size.height))
                        .shadow(color: barColor.opacity(active ? 0.8 : 0.25),
                                radius: active ? 5 : 1)
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .center)
            .animation(.easeOut(duration: 0.09), value: levels)
        }
    }

    private func barHeight(_ level: CGFloat, _ maxH: CGFloat) -> CGFloat {
        let minH: CGFloat = 4
        let lvl = min(1, max(0, level))
        return minH + lvl * (maxH - minH)
    }

    private var barColor: Color { muted ? Color(hex: 0x2A6B22) : Phos.green }
}

// MARK: - Recognition lifecycle core BEGIN

/// Keeps every segment in capture order while older recognition sessions drain.
/// Audio and timers stay in SpeechManager. This value owns transcript state only.
nonisolated struct RecognitionLifecycle {
    struct Token: Hashable {
        let capture: Int
        let segment: Int
    }

    private struct Segment {
        var text = ""
        var complete = false
    }

    private(set) var capture = 0
    private(set) var activeToken: Token?
    private(set) var isStopping = false
    private var isActive = false
    private var nextSegment = 0
    private var segments: [Int: Segment] = [:]

    var transcript: String {
        segments.keys.sorted().compactMap { key in
            let text = segments[key]?.text.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
            return text.isEmpty ? nil : text
        }.joined(separator: " ")
    }

    var canFinalize: Bool {
        isActive && isStopping && segments.values.allSatisfy { $0.complete }
    }

    @discardableResult
    mutating func beginCapture() -> Int {
        capture += 1
        isActive = true
        isStopping = false
        activeToken = nil
        nextSegment = 0
        segments.removeAll(keepingCapacity: true)
        return capture
    }

    mutating func beginSegment() -> Token? {
        guard isActive && !isStopping else { return nil }
        nextSegment += 1
        let token = Token(capture: capture, segment: nextSegment)
        segments[token.segment] = Segment()
        activeToken = token
        return token
    }

    @discardableResult
    mutating func receive(_ text: String?, isFinal: Bool, failed: Bool, token: Token) -> Bool {
        guard isActive, token.capture == capture,
              var segment = segments[token.segment], !segment.complete else { return false }
        if let text { segment.text = text }
        if isFinal || failed { segment.complete = true }
        segments[token.segment] = segment
        return true
    }

    @discardableResult
    mutating func stop(capture: Int) -> Bool {
        guard isActive, capture == self.capture, !isStopping else { return false }
        isStopping = true
        return true
    }

    /// The caller waits for canFinalize or its capture-specific deadline first.
    mutating func finish(capture: Int) -> String? {
        guard isActive, capture == self.capture, isStopping else { return nil }
        let result = transcript
        isActive = false
        isStopping = false
        activeToken = nil
        return result
    }

    @discardableResult
    mutating func cancel(capture: Int) -> Bool {
        guard isActive, capture == self.capture else { return false }
        isActive = false
        isStopping = false
        activeToken = nil
        segments.removeAll(keepingCapacity: true)
        return true
    }
}

// MARK: - Recognition lifecycle core END

// MARK: - Product core BEGIN

nonisolated enum TalkyStorageError: LocalizedError {
    case unsafePath(String)
    var errorDescription: String? {
        switch self {
        case .unsafePath(let name): return "Cannot use \(name): expected a private, regular file or directory."
        }
    }
}

/// Local files stay private even when the process has a permissive umask.
nonisolated struct TalkyStore {
    let root: URL
    init(root: URL = TalkyStore.defaultRoot) {
        self.root = root
    }

    static var defaultRoot: URL {
        if let path = ProcessInfo.processInfo.environment["TALKY_DATA_DIR"], path.hasPrefix("/") {
            return URL(fileURLWithPath: path, isDirectory: true)
        }
        return FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent(".talky")
    }

    func prepare() throws {
        try directory(root)
        for name in ["voice_input.txt", "talky_cmd"] {
            let url = root.appendingPathComponent(name)
            if FileManager.default.fileExists(atPath: url.path) { try regularFile(url) }
        }
        let history = root.appendingPathComponent("voice_history")
        if FileManager.default.fileExists(atPath: history.path) {
            try directory(history)
            for url in try FileManager.default.contentsOfDirectory(at: history, includingPropertiesForKeys: nil) {
                if ["md", "jsonl"].contains(url.pathExtension) { try regularFile(url) }
            }
        }
    }

    func directory(_ url: URL) throws {
        let manager = FileManager.default
        if let attributes = try? manager.attributesOfItem(atPath: url.path) {
            guard attributes[.type] as? FileAttributeType == .typeDirectory,
                  (attributes[.ownerAccountID] as? NSNumber)?.uint32Value == getuid() else {
                throw TalkyStorageError.unsafePath(url.lastPathComponent)
            }
        } else {
            try manager.createDirectory(at: url, withIntermediateDirectories: false,
                                        attributes: [.posixPermissions: 0o700])
        }
        try privatePermissions(url, mode: 0o700)
    }

    func regularFile(_ url: URL) throws {
        let attributes = try FileManager.default.attributesOfItem(atPath: url.path)
        guard attributes[.type] as? FileAttributeType == .typeRegular,
              (attributes[.ownerAccountID] as? NSNumber)?.uint32Value == getuid() else {
            throw TalkyStorageError.unsafePath(url.lastPathComponent)
        }
        try privatePermissions(url, mode: 0o600)
    }

    private func privatePermissions(_ url: URL, mode: Int) throws {
        try FileManager.default.setAttributes([.posixPermissions: mode], ofItemAtPath: url.path)
        guard let acl = acl_init(0) else { throw NSError(domain: NSPOSIXErrorDomain, code: Int(errno)) }
        defer { acl_free(UnsafeMutableRawPointer(acl)) }
        guard acl_set_file(url.path, ACL_TYPE_EXTENDED, acl) == 0 else {
            throw NSError(domain: NSPOSIXErrorDomain, code: Int(errno))
        }
    }

    func write(_ data: Data, to url: URL) throws {
        try directory(root)
        if FileManager.default.fileExists(atPath: url.path) { try regularFile(url) }
        try data.write(to: url, options: .atomic)
        try regularFile(url)
    }

    func writeLatest(_ text: String) throws {
        try write(Data(text.utf8), to: root.appendingPathComponent("voice_input.txt"))
    }

    /// Clear inherited ACLs before any exported transcript reaches the file.
    func export(_ data: Data, to url: URL) throws {
        if FileManager.default.fileExists(atPath: url.path) { try regularFile(url) }
        var template = Array(url.deletingLastPathComponent().appendingPathComponent(".Talky-export-XXXXXX").path.utf8CString)
        let descriptor = mkstemp(&template)
        guard descriptor >= 0 else { throw NSError(domain: NSPOSIXErrorDomain, code: Int(errno)) }
        let temporaryPath = String(cString: template)
        defer { close(descriptor); unlink(temporaryPath) }
        guard fchmod(descriptor, 0o600) == 0, let acl = acl_init(0) else {
            throw NSError(domain: NSPOSIXErrorDomain, code: Int(errno))
        }
        defer { acl_free(UnsafeMutableRawPointer(acl)) }
        guard acl_set_fd(descriptor, acl) == 0 else { throw NSError(domain: NSPOSIXErrorDomain, code: Int(errno)) }
        let handle = FileHandle(fileDescriptor: descriptor, closeOnDealloc: false)
        try handle.write(contentsOf: data)
        guard fsync(descriptor) == 0, rename(temporaryPath, url.path) == 0 else {
            throw NSError(domain: NSPOSIXErrorDomain, code: Int(errno))
        }
    }

    func removeLatest() throws {
        let url = root.appendingPathComponent("voice_input.txt")
        if FileManager.default.fileExists(atPath: url.path) {
            try regularFile(url)
            try FileManager.default.removeItem(at: url)
        }
    }

    func consumeCommand() throws -> String? {
        let url = root.appendingPathComponent("talky_cmd")
        guard FileManager.default.fileExists(atPath: url.path) else { return nil }
        try regularFile(url)
        let attributes = try FileManager.default.attributesOfItem(atPath: url.path)
        guard (attributes[.size] as? NSNumber)?.intValue ?? 0 <= 1024 else {
            throw TalkyStorageError.unsafePath("talky_cmd")
        }
        let value = try String(contentsOf: url, encoding: .utf8).trimmingCharacters(in: .whitespacesAndNewlines)
        guard !value.isEmpty else { return nil }
        try write(Data(), to: url)
        return value
    }

    func appendHistory(_ record: TalkyHistoryRecord) throws {
        let dir = root.appendingPathComponent("voice_history")
        try directory(root)
        try directory(dir)
        let file = dir.appendingPathComponent(String(record.createdAt.prefix(10)) + ".jsonl")
        let encoder = JSONEncoder()
        var data = try encoder.encode(record)
        data.append(0x0a)
        if FileManager.default.fileExists(atPath: file.path) {
            try regularFile(file)
            let handle = try FileHandle(forWritingTo: file)
            defer { try? handle.close() }
            try handle.seekToEnd()
            try handle.write(contentsOf: data)
        } else {
            try write(data, to: file)
        }
    }

    func historyFiles() throws -> [URL] {
        let dir = root.appendingPathComponent("voice_history")
        guard FileManager.default.fileExists(atPath: dir.path) else { return [] }
        try directory(dir)
        return try FileManager.default.contentsOfDirectory(at: dir, includingPropertiesForKeys: nil)
            .filter { ["jsonl", "md"].contains($0.pathExtension) }
            .sorted { $0.lastPathComponent > $1.lastPathComponent }
    }

    func loadRecords() throws -> [TalkyHistoryRecord] {
        var records: [TalkyHistoryRecord] = []
        for url in try historyFiles() {
            try regularFile(url)
            let content = try String(contentsOf: url, encoding: .utf8)
            if url.pathExtension == "jsonl" {
                for line in content.split(separator: "\n") {
                    if let record = try? JSONDecoder().decode(TalkyHistoryRecord.self, from: Data(line.utf8)) {
                        records.append(record)
                    }
                }
            } else {
                records.append(contentsOf: TalkyHistoryRecord.parseLegacy(content, day: url.deletingPathExtension().lastPathComponent))
            }
        }
        return records.sorted { ($0.timestamp ?? .distantPast) > ($1.timestamp ?? .distantPast) }
    }

    func pruneHistory(olderThan cutoff: Date) throws {
        for url in try historyFiles() {
            try regularFile(url)
            let content = try String(contentsOf: url, encoding: .utf8)
            if url.pathExtension == "jsonl" {
                let lines = try content.split(separator: "\n").filter { line in
                    let record = try JSONDecoder().decode(TalkyHistoryRecord.self, from: Data(line.utf8))
                    return record.timestamp.map { $0 >= cutoff } ?? true
                }
                if lines.isEmpty { try FileManager.default.removeItem(at: url) }
                else { try write(Data((lines.joined(separator: "\n") + "\n").utf8), to: url) }
            } else {
                let records = TalkyHistoryRecord.parseLegacy(content, day: url.deletingPathExtension().lastPathComponent)
                let retained = records.filter { $0.timestamp.map { $0 >= cutoff } ?? true }
                guard retained.count != records.count else { continue }
                if retained.isEmpty { try FileManager.default.removeItem(at: url) }
                else {
                    let day = url.deletingPathExtension().lastPathComponent
                    let text = "# Voice history " + day + "\n\n" + retained.map {
                        "## " + String($0.createdAt.dropFirst(11)) + "\n" + $0.text + "\n"
                    }.joined(separator: "\n")
                    try write(Data(text.utf8), to: url)
                }
            }
        }
    }

    func clearHistory() throws {
        for url in try historyFiles() {
            try regularFile(url)
            try FileManager.default.removeItem(at: url)
        }
    }

    func writeTestResult(_ result: TalkyTestResult) throws {
        let dir = root.appendingPathComponent("test-results")
        try directory(root)
        try directory(dir)
        let data = try JSONEncoder().encode(result)
        try write(data, to: dir.appendingPathComponent(result.runID + ".json"))
    }
}

nonisolated struct TalkyHistoryRecord: Codable {
    let id: String
    let createdAt: String
    let text: String
    let language: String

    init(text: String, language: String, now: Date = Date()) {
        id = UUID().uuidString
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        createdAt = formatter.string(from: now)
        self.text = text
        self.language = language
    }

    var timestamp: Date? {
        let iso = ISO8601DateFormatter()
        iso.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        if let date = iso.date(from: createdAt) { return date }
        iso.formatOptions = [.withInternetDateTime]
        if let date = iso.date(from: createdAt) { return date }
        let legacy = DateFormatter()
        legacy.locale = Locale(identifier: "en_US_POSIX")
        legacy.dateFormat = "yyyy-MM-dd'T'HH:mm:ss"
        return legacy.date(from: createdAt)
    }

    private init(id: String, createdAt: String, text: String, language: String) {
        self.id = id; self.createdAt = createdAt; self.text = text; self.language = language
    }

    static func parseLegacy(_ content: String, day: String) -> [TalkyHistoryRecord] {
        var records: [TalkyHistoryRecord] = []
        var time: String?
        var lines: [String] = []
        func flush() {
            let text = lines.joined(separator: "\n").trimmingCharacters(in: .whitespacesAndNewlines)
            if let time, !text.isEmpty {
                records.append(TalkyHistoryRecord(id: "\(day)-\(time)-\(records.count)",
                    createdAt: day + "T" + time, text: text, language: "en-US"))
            }
            time = nil; lines = []
        }
        for line in content.components(separatedBy: "\n") {
            if line.hasPrefix("## "), line.dropFirst(3).range(of: #"^\d{2}:\d{2}:\d{2}$"#, options: .regularExpression) != nil {
                flush(); time = String(line.dropFirst(3))
            } else if line.hasPrefix("# Voice history") { flush() }
            else if time != nil { lines.append(line) }
        }
        flush()
        return records
    }
}

nonisolated struct TalkyTestResult: Codable {
    let runID: String
    let phase: String
    let transcript: String
    let error: String?
    let startedAt: String
    let finishedAt: String?
    let microphone: String
}

nonisolated struct DeliverySafety {
    let trusted: Bool
    let targetAlive: Bool
    let sameApplication: Bool
    let sameElement: Bool
    let clipboardUnchanged: Bool
    let secureField: Bool

    var blockedReason: String? {
        if !trusted { return "Enable Accessibility to paste" }
        if !targetAlive { return "The original app closed" }
        if !sameApplication { return "Focus moved to another app" }
        if !sameElement { return "The original text field changed" }
        if !clipboardUnchanged { return "The clipboard changed" }
        if secureField { return "The original field is protected" }
        return nil
    }
}
// MARK: - Product core END

// MARK: - Speech manager

/// Every append and swap shares one lock, including reference ownership.
nonisolated final class AudioRequestBox: @unchecked Sendable {
    private let lock = NSLock()
    private var request: SFSpeechAudioBufferRecognitionRequest?

    func append(_ buffer: AVAudioPCMBuffer) {
        lock.lock(); defer { lock.unlock() }
        request?.append(buffer)
    }

    @discardableResult
    func replace(with next: SFSpeechAudioBufferRecognitionRequest?) -> SFSpeechAudioBufferRecognitionRequest? {
        lock.lock(); defer { lock.unlock() }
        let old = request
        request = next
        return old
    }
}

@MainActor
final class SpeechManager: ObservableObject {
    enum Phase { case idle, listening, processing, denied, unavailable }
    @Published private(set) var transcribedText = ""
    @Published private(set) var phase: Phase = .idle
    @Published private(set) var statusMessage = "Option-Space to dictate"
    @Published private(set) var audioLevel: CGFloat = 0
    @Published var expanded = false
    static let barCount = 27
    @Published private(set) var levels: [CGFloat] = Array(repeating: 0, count: barCount)
    @Published private(set) var speechAllowed = false
    @Published private(set) var microphoneAllowed = false
    @Published private(set) var accessibilityAllowed = false
    @Published private(set) var localRecognitionAvailable = false
    @Published private(set) var launchAtLogin = SMAppService.mainApp.status == .enabled
    @Published var shortcutAvailable = true

    @Published var autoPaste = UserDefaults.standard.object(forKey: "autoPaste") as? Bool ?? true {
        didSet { UserDefaults.standard.set(autoPaste, forKey: "autoPaste"); if !autoPaste { autoSubmit = false } }
    }
    @Published var autoSubmit = UserDefaults.standard.object(forKey: "autoSubmit") as? Bool ?? false {
        didSet { UserDefaults.standard.set(autoSubmit, forKey: "autoSubmit") }
    }
    @Published var saveHistory = UserDefaults.standard.object(forKey: "saveHistory") as? Bool ?? false {
        didSet { UserDefaults.standard.set(saveHistory, forKey: "saveHistory"); pruneHistory() }
    }
    @Published var historyRetentionDays = UserDefaults.standard.object(forKey: "historyRetentionDays") as? Int ?? 7 {
        didSet { UserDefaults.standard.set(historyRetentionDays, forKey: "historyRetentionDays"); pruneHistory() }
    }
    @Published var writeLatestTranscript = UserDefaults.standard.object(forKey: "writeLatestTranscript") as? Bool ?? false {
        didSet {
            UserDefaults.standard.set(writeLatestTranscript, forKey: "writeLatestTranscript")
            if !writeLatestTranscript {
                do { try store.removeLatest() } catch { statusMessage = error.localizedDescription }
            }
        }
    }
    @Published var languageIdentifier = UserDefaults.standard.string(forKey: "languageIdentifier") ?? "en-US" {
        didSet { UserDefaults.standard.set(languageIdentifier, forKey: "languageIdentifier"); configureRecognizer() }
    }
    @Published var vocabulary = UserDefaults.standard.string(forKey: "vocabulary") ?? "" {
        didSet { UserDefaults.standard.set(vocabulary, forKey: "vocabulary") }
    }

    var isListening: Bool { phase == .listening }
    var isBusy: Bool { phase == .listening || phase == .processing }
    var needsSetup: Bool { !speechAllowed || !microphoneAllowed }
    var languages: [Locale] { SFSpeechRecognizer.supportedLocales().sorted { $0.localizedName < $1.localizedName } }
    var languageName: String { Locale(identifier: languageIdentifier).localizedName }
    var microphoneName: String { captureMicrophoneName ?? Self.systemInputName() ?? "System microphone" }

    private var recognizer: SFSpeechRecognizer?
    private let audioEngine = AVAudioEngine()
    private let requestBox = AudioRequestBox()
    private var lifecycle = RecognitionLifecycle()
    private struct Segment {
        let request: SFSpeechAudioBufferRecognitionRequest
        let task: SFSpeechRecognitionTask
    }
    private var segments: [RecognitionLifecycle.Token: Segment] = [:]
    private var drainDeadlines: [RecognitionLifecycle.Token: Task<Void, Never>] = [:]
    private var stopDeadline: Task<Void, Never>?
    private var deliveryTask: Task<Void, Never>?
    private var commandTimer: Timer?
    private var audioConfigurationObserver: NSObjectProtocol?
    private var sleepObserver: NSObjectProtocol?
    private var sessionStartedAt: Date?
    private var consecutiveFailures = 0
    private var totalFailures = 0
    private var tapInstalled = false
    private var peakLevel: CGFloat = 0
    private var targetApp: NSRunningApplication?
    private var targetElement: AXUIElement?
    private var targetWasSecure = false
    private var testRunID: String?
    private var captureStartedAt = Date()
    private let store = TalkyStore()
    private var storageProblem: String?
    private var captureProblem: String?
    private var captureMicrophoneName: String?
    private var showingAvailabilityProblem = false

    init() {
        configureRecognizer()
        do { try store.prepare() } catch { storageProblem = error.localizedDescription }
        refreshPermissions()
        pruneHistory()
        audioConfigurationObserver = NotificationCenter.default.addObserver(
            forName: .AVAudioEngineConfigurationChange, object: audioEngine, queue: nil
        ) { [weak self] _ in
            Task { @MainActor [weak self] in
                guard let self, self.phase == .listening, !self.audioEngine.isRunning else { return }
                self.interruptCapture("Audio input changed. Copied the available transcript. Start again when ready.")
            }
        }
        sleepObserver = NSWorkspace.shared.notificationCenter.addObserver(
            forName: NSWorkspace.willSleepNotification, object: nil, queue: .main
        ) { [weak self] _ in
            MainActor.assumeIsolated {
                self?.interruptCapture("Recording stopped for sleep. Copied the available transcript.")
            }
        }
    }

    func prepare() {
        refreshPermissions()
        if needsSetup { expanded = true }
    }

    func refreshPermissions() {
        speechAllowed = SFSpeechRecognizer.authorizationStatus() == .authorized
        microphoneAllowed = AVCaptureDevice.authorizationStatus(for: .audio) == .authorized
        accessibilityAllowed = Paster.isTrusted
        localRecognitionAvailable = recognizer?.supportsOnDeviceRecognition == true && recognizer?.isAvailable == true
        guard !isBusy else { return }
        if needsSetup {
            showingAvailabilityProblem = true
            phase = .denied
            statusMessage = "Set up microphone and speech access"
        } else if !localRecognitionAvailable {
            showingAvailabilityProblem = true
            phase = .unavailable
            statusMessage = "On-device recognition unavailable for \(languageName)"
        } else if showingAvailabilityProblem {
            showingAvailabilityProblem = false
            phase = .idle
            statusMessage = "Option-Space to dictate"
        }
    }

    func requestSpeechPermission() {
        if SFSpeechRecognizer.authorizationStatus() == .denied || SFSpeechRecognizer.authorizationStatus() == .restricted {
            openPrivacySettings("SpeechRecognition"); return
        }
        PanelChrome.dropForPrompt()
        SFSpeechRecognizer.requestAuthorization { [weak self] _ in
            Task { @MainActor in self?.refreshPermissions() }
        }
    }

    func requestMicrophonePermission() {
        if AVCaptureDevice.authorizationStatus(for: .audio) == .denied || AVCaptureDevice.authorizationStatus(for: .audio) == .restricted {
            openPrivacySettings("Microphone"); return
        }
        PanelChrome.dropForPrompt()
        AVCaptureDevice.requestAccess(for: .audio) { [weak self] _ in
            Task { @MainActor in self?.refreshPermissions() }
        }
    }

    func requestAccessibilityPermission() {
        PanelChrome.dropForPrompt()
        _ = Paster.requestTrust()
        openPrivacySettings("Accessibility")
    }

    private func openPrivacySettings(_ pane: String) {
        guard let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_" + pane) else { return }
        PanelChrome.dropForPrompt()
        NSWorkspace.shared.open(url)
    }

    func setLaunchAtLogin(_ enabled: Bool) {
        do {
            if enabled { try SMAppService.mainApp.register() }
            else { try SMAppService.mainApp.unregister() }
            launchAtLogin = SMAppService.mainApp.status == .enabled
            if enabled && !launchAtLogin {
                SMAppService.openSystemSettingsLoginItems()
                statusMessage = "Approve Talky in Login Items"
            }
        } catch { statusMessage = "Login item: \(error.localizedDescription)" }
    }

    private func configureRecognizer() {
        guard !isBusy else { return }
        recognizer = SFSpeechRecognizer(locale: Locale(identifier: languageIdentifier))
        recognizer?.queue = .main
        refreshPermissions()
    }

    func toggle() {
        switch phase {
        case .listening: stop()
        case .processing: break
        default: start()
        }
    }

    func cancel() {
        guard isBusy else { return }
        let capture = lifecycle.capture
        stopDeadline?.cancel(); stopDeadline = nil
        deliveryTask?.cancel(); deliveryTask = nil
        teardownAudio()
        requestBox.replace(with: nil)?.endAudio()
        cancelSegments()
        _ = lifecycle.cancel(capture: capture)
        transcribedText = ""
        phase = .idle
        flattenLevels()
        statusMessage = "Cancelled. Nothing was copied or sent."
        writeTestState("cancelled", error: nil)
        testRunID = nil
    }

    private func interruptCapture(_ message: String) {
        deliveryTask?.cancel(); deliveryTask = nil
        guard isBusy else { return }
        captureProblem = message
        if phase == .listening { stop(problem: message) }
        else { statusMessage = message }
    }

    private func start(testID: String? = nil) {
        guard !isBusy else {
            if let testID {
                let now = ISO8601DateFormatter().string(from: Date())
                try? store.writeTestResult(TalkyTestResult(runID: testID, phase: "failed", transcript: "",
                    error: "Another capture is already active", startedAt: now, finishedAt: now, microphone: microphoneName))
            }
            return
        }
        deliveryTask?.cancel(); deliveryTask = nil
        testRunID = testID
        captureStartedAt = Date()
        transcribedText = ""
        captureProblem = nil
        captureMicrophoneName = nil
        refreshPermissions()
        guard speechAllowed, microphoneAllowed else {
            expanded = true
            statusMessage = "Allow microphone and speech access, then try again"
            writeTestState("failed", error: statusMessage)
            testRunID = nil
            return
        }
        guard let recognizer, recognizer.supportsOnDeviceRecognition, recognizer.isAvailable else {
            phase = .unavailable
            statusMessage = "Local speech model unavailable. Choose another language in Settings."
            expanded = true
            writeTestState("failed", error: statusMessage)
            testRunID = nil
            return
        }
        deliveryTask?.cancel(); deliveryTask = nil
        stopDeadline?.cancel(); stopDeadline = nil
        teardownAudio()
        cancelSegments()
        let capture = lifecycle.beginCapture()
        transcribedText = ""
        consecutiveFailures = 0; totalFailures = 0; peakLevel = 0
        flattenLevels()
        targetApp = testID == nil ? NSWorkspace.shared.frontmostApplication : nil
        targetElement = targetApp.flatMap { Paster.focusedElement(in: $0.processIdentifier) }
        targetWasSecure = targetElement.map(Paster.isSecure) ?? false

        let input = audioEngine.inputNode
        let format = input.outputFormat(forBus: 0)
        guard format.sampleRate > 0, format.channelCount > 0 else {
            failStart("No microphone detected", capture: capture); return
        }
        input.installTap(onBus: 0, bufferSize: 1024, format: format) { [weak self, box = requestBox] buffer, _ in
            box.append(buffer)
            let rms = Self.rms(of: buffer)
            Task { @MainActor [weak self] in self?.updateLevel(rms, capture: capture) }
        }
        tapInstalled = true
        guard startRecognitionSession() != nil else {
            failStart("Cannot create a local recognition session", capture: capture); return
        }
        audioEngine.prepare()
        do { try audioEngine.start() }
        catch { failStart("Could not start microphone: \(error.localizedDescription)", capture: capture); return }
        captureMicrophoneName = Self.inputName(unit: input.audioUnit) ?? Self.systemInputName()
        phase = .listening
        statusMessage = "Listening. Option-Space to stop, Option-Escape to cancel."
        writeTestState("listening", error: nil)
    }

    private func failStart(_ message: String, capture: Int) {
        teardownAudio()
        requestBox.replace(with: nil)?.endAudio()
        cancelSegments()
        _ = lifecycle.cancel(capture: capture)
        showingAvailabilityProblem = false
        phase = .unavailable
        statusMessage = message
        writeTestState("failed", error: message)
        testRunID = nil
    }

    @discardableResult
    private func startRecognitionSession() -> RecognitionLifecycle.Token? {
        guard let recognizer, recognizer.supportsOnDeviceRecognition, recognizer.isAvailable,
              let token = lifecycle.beginSegment() else { return nil }
        let request = SFSpeechAudioBufferRecognitionRequest()
        request.requiresOnDeviceRecognition = true
        request.shouldReportPartialResults = true
        request.addsPunctuation = true
        request.contextualStrings = Array(vocabulary.components(separatedBy: .newlines)
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }.prefix(100))
        let task = recognizer.recognitionTask(with: request) { [weak self] result, error in
            MainActor.assumeIsolated {
                self?.handleResult(result?.bestTranscription.formattedString,
                    isFinal: result?.isFinal ?? false, error: error, token: token)
            }
        }
        segments[token] = Segment(request: request, task: task)
        requestBox.replace(with: request)?.endAudio()
        sessionStartedAt = Date()
        return token
    }

    private func handleResult(_ text: String?, isFinal: Bool, error: Error?, token: RecognitionLifecycle.Token) {
        let wasActive = lifecycle.activeToken == token
        guard lifecycle.receive(text, isFinal: isFinal, failed: error != nil, token: token) else { return }
        transcribedText = lifecycle.transcript
        if isFinal || error != nil {
            if error != nil { captureProblem = "Recognition was interrupted. Copied the available transcript." }
            drainDeadlines.removeValue(forKey: token)?.cancel()
            segments.removeValue(forKey: token)
            if phase == .listening && wasActive {
                if error != nil {
                    consecutiveFailures += 1; totalFailures += 1
                    if consecutiveFailures > 3 || totalFailures > 12 {
                        stop(problem: "Recognition was interrupted. Copied the available transcript.")
                        finalize(capture: token.capture, problem: captureProblem)
                        return
                    }
                } else if !(text ?? "").isEmpty { consecutiveFailures = 0 }
                if startRecognitionSession() == nil {
                    stop(problem: "The local recognizer became unavailable. Copied the available transcript.")
                    finalize(capture: token.capture, problem: captureProblem)
                    return
                }
            }
            if lifecycle.canFinalize { finalize(capture: token.capture) }
        }
    }

    private func renewRecognition() {
        guard phase == .listening, let oldToken = lifecycle.activeToken,
              let old = segments[oldToken] else { return }
        guard startRecognitionSession() != nil else {
            stop(problem: "The local recognizer became unavailable. Copied the available transcript.")
            return
        }
        old.request.endAudio()
        old.task.finish()
        drainDeadlines[oldToken] = Task { @MainActor [weak self] in
            do { try await Task.sleep(nanoseconds: 5_000_000_000) } catch { return }
            guard let self, self.lifecycle.capture == oldToken.capture,
                  self.segments[oldToken] != nil else { return }
            self.segments.removeValue(forKey: oldToken)?.task.cancel()
            self.drainDeadlines.removeValue(forKey: oldToken)
            self.captureProblem = "A speech segment timed out. Copied the available transcript."
            _ = self.lifecycle.receive(nil, isFinal: false, failed: true, token: oldToken)
            self.transcribedText = self.lifecycle.transcript
            if self.lifecycle.canFinalize { self.finalize(capture: oldToken.capture) }
        }
    }

    private func stop(problem: String? = nil) {
        guard phase == .listening else { return }
        if let problem { captureProblem = problem }
        let capture = lifecycle.capture
        guard lifecycle.stop(capture: capture) else { return }
        phase = .processing
        statusMessage = "Finishing transcription. Option-Escape to cancel."
        teardownAudio()
        requestBox.replace(with: nil)?.endAudio()
        sessionStartedAt = nil
        flattenLevels()
        for segment in segments.values { segment.request.endAudio(); segment.task.finish() }
        if lifecycle.canFinalize { finalize(capture: capture); return }
        stopDeadline?.cancel()
        stopDeadline = Task { @MainActor [weak self] in
            do { try await Task.sleep(nanoseconds: 5_000_000_000) } catch { return }
            guard let self, self.lifecycle.capture == capture, self.lifecycle.isStopping else { return }
            self.finalize(capture: capture, problem: "Final recognition timed out. Copied the available transcript.")
        }
    }

    private func finalize(capture: Int, problem: String? = nil) {
        guard let text = lifecycle.finish(capture: capture) else { return }
        let problem = problem ?? captureProblem
        stopDeadline?.cancel(); stopDeadline = nil
        teardownAudio()
        requestBox.replace(with: nil)?.endAudio()
        cancelSegments()
        sessionStartedAt = nil
        phase = .idle
        flattenLevels()
        transcribedText = text
        if testRunID != nil {
            writeTestState(problem == nil && !text.isEmpty ? "completed" : "failed",
                error: problem ?? (text.isEmpty ? "No speech recognized" : nil))
            testRunID = nil
            statusMessage = problem == nil && !text.isEmpty ? "Test completed. No text was pasted." : "Test failed. No text was pasted."
        } else if text.isEmpty {
            statusMessage = problem ?? (peakLevel < 0.02 ? "No sound from \(microphoneName). Check your input device." : "No words recognized. Try again.")
        } else {
            deliver(text, problem: problem)
        }
    }

    private func cancelSegments() {
        for task in drainDeadlines.values { task.cancel() }
        drainDeadlines.removeAll()
        for segment in segments.values { segment.task.cancel() }
        segments.removeAll()
    }

    private func teardownAudio() {
        if audioEngine.isRunning { audioEngine.stop() }
        if tapInstalled { audioEngine.inputNode.removeTap(onBus: 0); tapInstalled = false }
    }

    private func updateLevel(_ rms: Float, capture: Int) {
        guard lifecycle.capture == capture, phase == .listening else { return }
        let target = min(1, CGFloat(rms) * 14)
        audioLevel = audioLevel * 0.6 + target * 0.4
        peakLevel = max(peakLevel, audioLevel)
        levels.removeFirst(); levels.append(audioLevel)
        if let started = sessionStartedAt {
            let age = Date().timeIntervalSince(started)
            if (age > 20 && audioLevel < 0.06 && !transcribedText.isEmpty) || age > 45 { renewRecognition() }
        }
    }

    private func flattenLevels() { audioLevel = 0; levels = Array(repeating: 0, count: Self.barCount) }
    nonisolated static func rms(of buffer: AVAudioPCMBuffer) -> Float {
        guard let data = buffer.floatChannelData?[0], buffer.frameLength > 0 else { return 0 }
        var sum: Float = 0
        for i in 0..<Int(buffer.frameLength) { sum += data[i] * data[i] }
        return (sum / Float(buffer.frameLength)).squareRoot()
    }

    nonisolated private static func deviceName(_ device: AudioDeviceID) -> String? {
        var address = AudioObjectPropertyAddress(mSelector: kAudioObjectPropertyName,
            mScope: kAudioObjectPropertyScopeGlobal, mElement: kAudioObjectPropertyElementMain)
        var name: Unmanaged<CFString>?
        var size = UInt32(MemoryLayout<Unmanaged<CFString>?>.size)
        guard AudioObjectGetPropertyData(device, &address, 0, nil, &size, &name) == noErr else { return nil }
        return name?.takeRetainedValue() as String?
    }

    nonisolated private static func systemInputName() -> String? {
        var device = AudioDeviceID()
        var size = UInt32(MemoryLayout<AudioDeviceID>.size)
        var address = AudioObjectPropertyAddress(mSelector: kAudioHardwarePropertyDefaultInputDevice,
            mScope: kAudioObjectPropertyScopeGlobal, mElement: kAudioObjectPropertyElementMain)
        guard AudioObjectGetPropertyData(AudioObjectID(kAudioObjectSystemObject), &address, 0, nil, &size, &device) == noErr else { return nil }
        return deviceName(device)
    }

    nonisolated private static func inputName(unit: AudioUnit?) -> String? {
        guard let unit else { return nil }
        var device = AudioDeviceID()
        var size = UInt32(MemoryLayout<AudioDeviceID>.size)
        guard AudioUnitGetProperty(unit, kAudioOutputUnitProperty_CurrentDevice, kAudioUnitScope_Global, 0, &device, &size) == noErr else { return nil }
        return deviceName(device)
    }

    private func writeTestState(_ state: String, error: String?) {
        guard let id = testRunID else { return }
        let formatter = ISO8601DateFormatter()
        let result = TalkyTestResult(runID: id, phase: state, transcript: transcribedText, error: error,
            startedAt: formatter.string(from: captureStartedAt),
            finishedAt: state == "listening" ? nil : formatter.string(from: Date()), microphone: microphoneName)
        do { try store.writeTestResult(result) }
        catch { statusMessage = "Test output: \(error.localizedDescription)" }
    }

    func startCommandWatcher() {
        do {
            try store.prepare()
            let cmd = store.root.appendingPathComponent("talky_cmd")
            if !FileManager.default.fileExists(atPath: cmd.path) { try store.write(Data(), to: cmd) }
        } catch { storageProblem = error.localizedDescription; statusMessage = error.localizedDescription; return }
        commandTimer?.invalidate()
        var ticks = 0
        commandTimer = Timer.scheduledTimer(withTimeInterval: 0.25, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated {
                guard let self else { return }
                ticks += 1
                if ticks % 8 == 0 { self.refreshPermissions() }
                do {
                    guard let command = try self.store.consumeCommand() else { return }
                    if command.hasPrefix("test-start:"), let id = UUID(uuidString: String(command.dropFirst(11))) {
                        self.start(testID: id.uuidString)
                    } else if command.hasPrefix("test-stop:"), let id = UUID(uuidString: String(command.dropFirst(10))), id.uuidString == self.testRunID {
                        self.stop()
                    } else {
                        switch command.lowercased() {
                        case "start": if !self.isBusy { self.start() }
                        case "stop": self.stop()
                        case "cancel": self.cancel()
                        case "toggle": self.toggle()
                        default: break
                        }
                    }
                } catch { self.statusMessage = error.localizedDescription }
            }
        }
    }

    func loadHistory() -> [HistoryItem] {
        do {
            return try store.loadRecords().map { record in
                let time: String
                let day: String
                if let date = record.timestamp {
                    let df = DateFormatter(); df.dateStyle = .medium; df.timeStyle = .none
                    day = df.string(from: date); df.dateStyle = .none; df.timeStyle = .short
                    time = df.string(from: date)
                } else { day = String(record.createdAt.prefix(10)); time = String(record.createdAt.dropFirst(11).prefix(8)) }
                return HistoryItem(id: record.id, date: day, time: time, text: record.text)
            }
        } catch { statusMessage = "History: \(error.localizedDescription)"; return [] }
    }

    func clearHistory() {
        do { try store.clearHistory(); statusMessage = "Local history cleared" }
        catch { statusMessage = "History: \(error.localizedDescription)" }
    }

    func exportHistory() {
        let panel = NSSavePanel()
        panel.nameFieldStringValue = "Talky-history.txt"
        panel.title = "Export local dictation history"
        PanelChrome.dropForPrompt()
        guard panel.runModal() == .OK, let url = panel.url else { return }
        do {
            let content = try store.loadRecords().map { "\($0.createdAt)\n\($0.text)" }.joined(separator: "\n\n")
            try store.export(Data(content.utf8), to: url)
            statusMessage = "History exported"
        } catch { statusMessage = "Export: \(error.localizedDescription)" }
    }

    private func pruneHistory() {
        guard saveHistory, [1, 7, 30].contains(historyRetentionDays),
              let cutoff = Calendar.current.date(byAdding: .day, value: -historyRetentionDays, to: Date()) else { return }
        do { try store.pruneHistory(olderThan: cutoff) }
        catch { storageProblem = error.localizedDescription }
    }

    func copy(_ text: String) {
        NSPasteboard.general.clearContents()
        if NSPasteboard.general.setString(text, forType: .string) { statusMessage = "Copied to clipboard" }
        else { statusMessage = "Could not write to clipboard" }
    }

    private func deliver(_ text: String, problem: String?) {
        var storageErrors: [String] = []
        if saveHistory {
            do { try store.appendHistory(TalkyHistoryRecord(text: text, language: languageIdentifier)); pruneHistory() }
            catch { storageErrors.append("history was not saved") }
        }
        if writeLatestTranscript {
            do { try store.writeLatest(text) } catch { storageErrors.append("automation file was not saved") }
        }
        copy(text)
        guard NSPasteboard.general.string(forType: .string) == text else { return }
        let storageNotice = storageErrors.isEmpty ? "" : ". " + storageErrors.joined(separator: "; ")
        statusMessage += storageNotice
        let clipboardVersion = NSPasteboard.general.changeCount
        if let problem { statusMessage = problem + storageNotice; return }
        guard autoPaste else { return }
        let target = targetApp
        let element = targetElement
        let secure = targetWasSecure
        let submit = autoSubmit
        let capture = lifecycle.capture
        deliveryTask?.cancel()
        deliveryTask = Task { @MainActor [weak self] in
            do { try await Task.sleep(nanoseconds: 120_000_000) } catch { return }
            guard let self, self.lifecycle.capture == capture else { return }
            let safety = Paster.safety(target: target, element: element, clipboardVersion: clipboardVersion, secure: secure)
            if let reason = safety.blockedReason { self.statusMessage = "Copied. \(reason)." + storageNotice; return }
            guard let target, Paster.paste(to: target.processIdentifier) else {
                self.statusMessage = "Copied. Could not send the paste shortcut." + storageNotice; return
            }
            self.statusMessage = "Copied and sent to \(target.localizedName ?? "your app")" + storageNotice
            if submit {
                do { try await Task.sleep(nanoseconds: 120_000_000) } catch { return }
                guard self.lifecycle.capture == capture,
                      Paster.safety(target: target, element: element, clipboardVersion: clipboardVersion, secure: secure).blockedReason == nil,
                      Paster.pressReturn(to: target.processIdentifier) else {
                    self.statusMessage = "Copied. Return was not sent because delivery checks failed." + storageNotice; return
                }
                self.statusMessage = "Paste and Return sent to \(target.localizedName ?? "your app")" + storageNotice
            }
        }
    }
}

extension Locale {
    var localizedName: String { Locale.current.localizedString(forIdentifier: identifier) ?? identifier }
}

// MARK: - Safe keyboard delivery

@MainActor
enum Paster {
    static var isTrusted: Bool { AXIsProcessTrusted() }
    @discardableResult static func requestTrust() -> Bool {
        let key = kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String
        return AXIsProcessTrustedWithOptions([key: true] as CFDictionary)
    }

    static func focusedElement(in pid: pid_t) -> AXUIElement? {
        guard isTrusted else { return nil }
        var value: CFTypeRef?
        guard AXUIElementCopyAttributeValue(AXUIElementCreateApplication(pid), kAXFocusedUIElementAttribute as CFString, &value) == .success,
              let value, CFGetTypeID(value) == AXUIElementGetTypeID() else { return nil }
        return (value as! AXUIElement)
    }

    static func isSecure(_ element: AXUIElement) -> Bool {
        var value: CFTypeRef?
        return AXUIElementCopyAttributeValue(element, kAXSubroleAttribute as CFString, &value) == .success
            && value as? String == kAXSecureTextFieldSubrole as String
    }

    static func safety(target: NSRunningApplication?, element: AXUIElement?, clipboardVersion: Int, secure: Bool) -> DeliverySafety {
        let current = target.flatMap { focusedElement(in: $0.processIdentifier) }
        return DeliverySafety(trusted: isTrusted, targetAlive: target?.isTerminated == false,
            sameApplication: target?.processIdentifier == NSWorkspace.shared.frontmostApplication?.processIdentifier,
            sameElement: element != nil && current != nil && CFEqual(element, current),
            clipboardUnchanged: NSPasteboard.general.changeCount == clipboardVersion,
            secureField: secure || current.map(isSecure) == true)
    }

    private static func key(_ key: CGKeyCode, flags: CGEventFlags = [], to pid: pid_t) -> Bool {
        guard isTrusted, NSWorkspace.shared.frontmostApplication?.processIdentifier == pid,
              let source = CGEventSource(stateID: .combinedSessionState),
              let down = CGEvent(keyboardEventSource: source, virtualKey: key, keyDown: true),
              let up = CGEvent(keyboardEventSource: source, virtualKey: key, keyDown: false) else { return false }
        down.flags = flags; up.flags = flags
        down.postToPid(pid); up.postToPid(pid)
        return true
    }
    static func paste(to pid: pid_t) -> Bool { key(9, flags: .maskCommand, to: pid) }
    static func pressReturn(to pid: pid_t) -> Bool { key(36, to: pid) }
}

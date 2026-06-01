import SwiftUI
import AppKit
import AVFoundation
import Speech
import Combine
import CoreGraphics
import ApplicationServices
import Carbon.HIToolbox
import ServiceManagement

// MARK: - App entry

@main
struct LokaahTalkyApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate

    var body: some Scene {
        // No default window — the floating panel is created by the AppDelegate so
        // it can be a non-activating HUD that never steals focus from your terminal.
        Settings { EmptyView() }
    }
}

// MARK: - App delegate / floating panel

final class AppDelegate: NSObject, NSApplicationDelegate {
    private var panel: FloatingPanel?
    let speech = SpeechManager()
    private var hotKey: GlobalHotKey?
    private var sizeObserver: AnyCancellable?

    /// Resize the panel between the compact presence and the full HUD, anchored
    /// on its center so it blooms in place.
    private func setPanelExpanded(_ expanded: Bool) {
        guard let panel else { return }
        let size = expanded ? NSSize(width: 360, height: 540) : NSSize(width: 210, height: 58)
        let f = panel.frame
        let origin = NSPoint(x: f.midX - size.width / 2, y: f.midY - size.height / 2)
        let target = NSRect(origin: origin, size: size)
        NSAnimationContext.runAnimationGroup { ctx in
            ctx.duration = 0.22
            panel.animator().setFrame(target, display: true)
        }
    }

    func applicationDidFinishLaunching(_ notification: Notification) {
        // Accessory app: no Dock icon, no menu bar — and crucially, interacting
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

        // Lets Hermes / scripts drive dictation by writing start/stop/toggle to
        // ~/.talky/talky_cmd (also used for automated testing).
        speech.startCommandWatcher()

        // Grow/shrink the window as the app expands and minimizes.
        sizeObserver = speech.$expanded
            .removeDuplicates()
            .sink { [weak self] expanded in self?.setPanelExpanded(expanded) }

        // Launch automatically at login (registers as a background item).
        do {
            if SMAppService.mainApp.status != .enabled {
                try SMAppService.mainApp.register()
            }
        } catch {
            NSLog("Lokaah Talky: login-item registration failed: \(error)")
        }
    }

    func applicationSupportsSecureRestorableState(_ app: NSApplication) -> Bool { true }
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
    fileprivate static var shared: GlobalHotKey?
    private var hotKeyRef: EventHotKeyRef?
    private var handlerRef: EventHandlerRef?
    private let action: @MainActor () -> Void

    init(keyCode: UInt32, modifiers: UInt32, action: @escaping @MainActor () -> Void) {
        self.action = action
        GlobalHotKey.shared = self

        var spec = EventTypeSpec(eventClass: OSType(kEventClassKeyboard),
                                 eventKind: OSType(kEventHotKeyPressed))
        InstallEventHandler(GetApplicationEventTarget(), { _, _, _ in
            // Carbon delivers this on the main run loop.
            MainActor.assumeIsolated { GlobalHotKey.shared?.action() }
            return noErr
        }, 1, &spec, nil, &handlerRef)

        let id = EventHotKeyID(signature: OSType(0x484B_4559), id: 1) // 'HKEY'
        RegisterEventHotKey(keyCode, modifiers, id, GetApplicationEventTarget(), 0, &hotKeyRef)
    }

    deinit {
        if let hotKeyRef { UnregisterEventHotKey(hotKeyRef) }
        if let handlerRef { RemoveEventHandler(handlerRef) }
    }
}

/// Hosting view that lets the very first click reach SwiftUI controls. Without
/// this, a non-activating panel swallows the first click just to become key, so
/// the orb needs two taps and feels unresponsive.
final class FirstMouseHostingView<Content: View>: NSHostingView<Content> {
    required init(rootView: Content) { super.init(rootView: rootView) }
    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }
    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }
}

/// Borderless, translucent, always-on-top panel that floats above other apps
/// without activating our process when clicked.
final class FloatingPanel: NSPanel {
    init() {
        super.init(
            contentRect: NSRect(x: 0, y: 0, width: 210, height: 58),
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
    let id = UUID()
    let date: String
    let time: String
    let text: String
}

// MARK: - Root view

struct RootView: View {
    @ObservedObject var speech: SpeechManager
    @State private var closeHover = false
    @State private var pressed = false
    @State private var cursorOn = false
    @State private var showHistory = false
    @State private var historyItems: [HistoryItem] = []

    private let size: CGFloat = 360

    var body: some View {
        Group {
            if speech.expanded { fullPanel } else { collapsedWidget }
        }
        .environment(\.colorScheme, .dark)
        .onAppear {
            speech.requestPermissions()
            withAnimation(.easeInOut(duration: 0.55).repeatForever(autoreverses: true)) { cursorOn = true }
        }
    }

    // Full HUD (shown while in use).
    private var fullPanel: some View {
        VStack(spacing: 0) {
            header
            Spacer(minLength: 6)
            waveform
            Spacer(minLength: 10)
            transcript
            statusLine
        }
        .padding(.horizontal, 20)
        .padding(.top, 16)
        .padding(.bottom, 18)
        .frame(width: size, height: 540)
        .background(panelBackground)
    }

    // Compact "presence" — clean widget you can dictate into in place.
    // Tap the body to start/stop; the ⤢ button opens the full panel.
    private var collapsedWidget: some View {
        HStack(spacing: 10) {
            Button { speech.toggle() } label: {
                HStack(spacing: 11) {
                    compactIndicator
                        .frame(width: 26, height: 26)
                    Text(compactLabel)
                        .font(.system(size: 13, weight: .medium, design: .rounded))
                        .foregroundStyle(compactLabelColor)
                        .lineLimit(1)
                    Spacer(minLength: 0)
                }
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)

            Button { speech.expanded = true } label: {
                Image(systemName: "arrow.up.left.and.arrow.down.right")
                    .font(.system(size: 10, weight: .bold))
                    .foregroundStyle(.white.opacity(0.4))
                    .frame(width: 22, height: 22)
            }
            .buttonStyle(.plain)
            .help("Open full panel")
            .accessibilityLabel("Open full panel")
        }
        .padding(.horizontal, 15)
        .frame(width: 210, height: 58)
        .background(widgetBackground)
    }

    @ViewBuilder private var compactIndicator: some View {
        switch speech.phase {
        case .listening:   MiniWaveform(level: speech.audioLevel)
        case .processing:  Image(systemName: "ellipsis").font(.system(size: 16, weight: .bold)).foregroundStyle(Phos.green)
        case .denied, .unavailable: Image(systemName: "mic.slash.fill").font(.system(size: 14)).foregroundStyle(Phos.amber)
        case .idle:        Image(systemName: "mic.fill").font(.system(size: 15, weight: .medium)).foregroundStyle(Phos.green).shadow(color: Phos.green.opacity(0.6), radius: 3)
        }
    }

    private var compactLabel: String {
        switch speech.phase {
        case .listening:   return "listening…"
        case .processing:  return "transcribing…"
        case .denied:      return "enable access"
        case .unavailable: return "unavailable"
        case .idle:        return "lokaah talky"
        }
    }

    private var compactLabelColor: Color {
        switch speech.phase {
        case .denied, .unavailable: return Phos.amber
        case .idle:                 return .white.opacity(0.85)
        default:                    return Phos.green
        }
    }

    private var widgetBackground: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 16, style: .continuous).fill(.ultraThinMaterial)
            RoundedRectangle(cornerRadius: 16, style: .continuous).fill(Color.black.opacity(0.5))
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .strokeBorder(Phos.green.opacity(speech.isListening ? 0.7 : 0.35), lineWidth: 1)
        }
        .environment(\.colorScheme, .dark)
        .shadow(color: .black.opacity(0.45), radius: 9, y: 3)
        .animation(.easeInOut(duration: 0.2), value: speech.isListening)
    }

    // MARK: Header

    private var header: some View {
        HStack(spacing: 6) {
            Text("lokaah talky")
                .font(.system(size: 13, weight: .semibold, design: .monospaced))
                .foregroundStyle(Phos.green)
                .shadow(color: Phos.green.opacity(0.6), radius: 3)
            // Blinking block cursor
            Rectangle()
                .fill(Phos.green)
                .frame(width: 7, height: 14)
                .opacity(cursorOn ? 1 : 0.1)
                .shadow(color: Phos.green.opacity(0.8), radius: 3)

            Spacer()

            // REC indicator while listening
            if speech.isListening {
                HStack(spacing: 5) {
                    Circle().fill(Phos.amber).frame(width: 7, height: 7)
                        .shadow(color: Phos.amber.opacity(0.9), radius: 3)
                    Text("REC")
                        .font(.system(size: 11, weight: .bold, design: .monospaced))
                        .foregroundStyle(Phos.amber)
                }
                .padding(.trailing, 4)
            }

            // Minimize to the compact presence
            Button { showHistory = false; speech.expanded = false } label: {
                Image(systemName: "arrow.down.right.and.arrow.up.left")
                    .font(.system(size: 11, weight: .bold))
                    .foregroundStyle(Phos.green.opacity(0.6))
                    .frame(width: 24, height: 22)
                    .overlay(RoundedRectangle(cornerRadius: 4).stroke(Phos.green.opacity(0.15), lineWidth: 1))
            }
            .buttonStyle(.plain)
            .help("Minimize")
            .accessibilityLabel("Minimize")

            // History viewer toggle
            Button {
                showHistory.toggle()
                if showHistory { historyItems = speech.loadHistory() }
            } label: {
                Image(systemName: "clock.arrow.circlepath")
                    .font(.system(size: 11, weight: .bold))
                    .foregroundStyle(showHistory ? Phos.green : Phos.green.opacity(0.3))
                    .frame(width: 24, height: 22)
                    .overlay(RoundedRectangle(cornerRadius: 4)
                        .stroke(Phos.green.opacity(showHistory ? 0.5 : 0.15), lineWidth: 1))
            }
            .buttonStyle(.plain)
            .help(showHistory ? "Hide history" : "Show past conversations")
            .accessibilityLabel("History")
            .accessibilityValue(showHistory ? "Showing" : "Hidden")

            // Auto-send toggle
            Button { speech.autoSubmit.toggle() } label: {
                Image(systemName: "return")
                    .font(.system(size: 11, weight: .bold))
                    .foregroundStyle(speech.autoSubmit ? Phos.green : Phos.green.opacity(0.3))
                    .frame(width: 24, height: 22)
                    .overlay(RoundedRectangle(cornerRadius: 4)
                        .stroke(Phos.green.opacity(speech.autoSubmit ? 0.5 : 0.15), lineWidth: 1))
            }
            .buttonStyle(.plain)
            .help(speech.autoSubmit ? "Auto-send on — types then presses Return"
                                    : "Auto-send off — types only")
            .accessibilityLabel("Auto-send")
            .accessibilityValue(speech.autoSubmit ? "On" : "Off")
            .accessibilityHint("When on, presses Return after inserting")

            // Quit
            Button { NSApp.terminate(nil) } label: {
                Text("×")
                    .font(.system(size: 16, weight: .bold, design: .monospaced))
                    .foregroundStyle(Phos.green.opacity(closeHover ? 0.9 : 0.4))
                    .frame(width: 22, height: 22)
            }
            .buttonStyle(.plain)
            .onHover { closeHover = $0 }
            .help("Quit Lokaah Talky")
            .accessibilityLabel("Quit Lokaah Talky")
        }
    }

    // MARK: The waveform (tap to talk)

    private var waveform: some View {
        Button { showHistory = false; speech.toggle() } label: {
            Waveform(levels: speech.levels, phase: speech.phase)
                .frame(height: 92)
                .frame(maxWidth: .infinity)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .scaleEffect(pressed ? 0.98 : 1.0)
        .animation(.spring(response: 0.3, dampingFraction: 0.6), value: pressed)
        .onLongPressGesture(minimumDuration: 0, maximumDistance: .infinity,
                            pressing: { pressed = $0 }, perform: {})
        .disabled(speech.phase == .processing)
        .accessibilityLabel("Voice dictation")
        .accessibilityValue(accessibilityState)
        .accessibilityHint("Starts or stops listening. Or press Option-Space anywhere.")
        .accessibilityAddTraits(.isButton)
    }

    private var accessibilityState: String {
        switch speech.phase {
        case .listening:   return "Listening"
        case .processing:  return "Transcribing"
        case .denied:      return "Permission needed"
        case .unavailable: return "Unavailable"
        case .idle:        return "Idle"
        }
    }

    // MARK: Transcript

    @ViewBuilder
    private var transcript: some View {
        if showHistory {
            historyView
        } else {
            liveTranscript
        }
    }

    // Live dictation: full text, scrolls, auto-follows the latest words.
    private var liveTranscript: some View {
        let isEmpty = speech.transcribedText.isEmpty
        return ScrollViewReader { proxy in
            ScrollView(.vertical, showsIndicators: true) {
                VStack(spacing: 0) {
                    Spacer(minLength: 0)
                    Text(isEmpty ? placeholder : speech.transcribedText)
                        .font(.system(size: 14, weight: .regular, design: .monospaced))
                        .foregroundStyle(isEmpty
                                         ? AnyShapeStyle(Phos.green.opacity(0.3))
                                         : AnyShapeStyle(Phos.green.opacity(0.92)))
                        .multilineTextAlignment(.leading)
                        .lineSpacing(3)
                        .textSelection(.enabled)
                        .frame(maxWidth: .infinity, alignment: .leading)
                    Spacer(minLength: 0)
                    Color.clear.frame(height: 1).id("bottom")
                }
                .frame(minHeight: 240)
                .padding(.horizontal, 2)
            }
            .frame(height: 240)
            .mask(edgeFade)
            .onChange(of: speech.transcribedText) { _, _ in
                withAnimation(.easeOut(duration: 0.15)) {
                    proxy.scrollTo("bottom", anchor: .bottom)
                }
            }
        }
    }

    // Past conversations, newest day first, read from ~/.talky/voice_history.
    private var historyView: some View {
        ScrollView(.vertical, showsIndicators: true) {
            LazyVStack(alignment: .leading, spacing: 14) {
                if historyItems.isEmpty {
                    Text("No past conversations yet.")
                        .font(.system(size: 13, design: .monospaced))
                        .foregroundStyle(Phos.green.opacity(0.4))
                        .padding(.top, 10)
                } else {
                    Text("\(historyItems.count) entries · newest first")
                        .font(.system(size: 10, weight: .semibold, design: .monospaced))
                        .foregroundStyle(Phos.green.opacity(0.4))
                    ForEach(historyItems) { item in
                        VStack(alignment: .leading, spacing: 3) {
                            Text("\(item.date)  \(item.time)")
                                .font(.system(size: 10, weight: .semibold, design: .monospaced))
                                .foregroundStyle(Phos.amber.opacity(0.85))
                            Text(item.text)
                                .font(.system(size: 13, design: .monospaced))
                                .foregroundStyle(Phos.green.opacity(0.9))
                                .multilineTextAlignment(.leading)
                                .lineSpacing(2)
                                .textSelection(.enabled)
                                .fixedSize(horizontal: false, vertical: true)
                        }
                        .frame(maxWidth: .infinity, alignment: .leading)
                    }
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, 2)
            .padding(.vertical, 4)
        }
        .frame(height: 240)
        .mask(edgeFade)
    }

    // Soft top/bottom edge fade so long text dissolves instead of hard-clipping.
    private var edgeFade: some View {
        LinearGradient(stops: [
            .init(color: .clear, location: 0.0),
            .init(color: .black, location: 0.08),
            .init(color: .black, location: 0.92),
            .init(color: .clear, location: 1.0),
        ], startPoint: .top, endPoint: .bottom)
    }

    // MARK: Status

    private var statusLine: some View {
        Text("> " + speech.statusMessage)
            .font(.system(size: 11, weight: .medium, design: .monospaced))
            .foregroundStyle(statusColor)
            .frame(maxWidth: .infinity, alignment: .leading)
            .animation(.easeInOut(duration: 0.2), value: speech.statusMessage)
            .padding(.top, 4)
    }

    private var statusColor: Color {
        switch speech.phase {
        case .denied, .unavailable: return Phos.amber
        default:                    return Phos.green.opacity(0.8)
        }
    }

    // MARK: Background

    private var panelBackground: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 16, style: .continuous).fill(Color.black)
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .fill(RadialGradient(colors: [Phos.green.opacity(0.06), .clear],
                                     center: .center, startRadius: 0, endRadius: 260))
            scanlines
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .strokeBorder(Phos.green.opacity(0.55), lineWidth: 1)
                .shadow(color: Phos.green.opacity(0.4), radius: 6)
        }
    }

    // Faint CRT scanline texture.
    private var scanlines: some View {
        Canvas { ctx, size in
            var y: CGFloat = 0
            while y < size.height {
                ctx.fill(Path(CGRect(x: 0, y: y, width: size.width, height: 1)),
                         with: .color(Phos.green.opacity(0.05)))
                y += 3
            }
        }
        .allowsHitTesting(false)
        .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
    }

    private var placeholder: String {
        switch speech.phase {
        case .denied:      return "allow Speech access in Settings"
        case .unavailable: return "speech recognition unavailable"
        case .processing:  return "transcribing…"
        case .listening:   return "listening…"
        default:           return "tap, or press ⌥Space, to dictate"
        }
    }
}

// MARK: - Waveform — audio-reactive phosphor equalizer

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

// MARK: - Speech manager

/// Holds the current recognition request so the audio tap (which runs off the
/// main actor) can append to whichever session is live, even as long dictations
/// renew the underlying request. Pointer swap only; safe enough for audio.
final class AudioRequestBox: @unchecked Sendable {
    var request: SFSpeechAudioBufferRecognitionRequest?
}

@MainActor
final class SpeechManager: ObservableObject {
    enum Phase { case idle, listening, processing, denied, unavailable }

    @Published private(set) var transcribedText = ""
    @Published private(set) var phase: Phase = .idle
    @Published private(set) var statusMessage = "Tap to speak"
    @Published private(set) var audioLevel: CGFloat = 0

    /// Compact "presence" vs full panel. User-controlled (maximize / minimize);
    /// dictation works in either size. The window resizes to match.
    @Published var expanded = false

    /// Recent audio levels, scrolling right, that drive the waveform bars.
    static let barCount = 27
    @Published private(set) var levels: [CGFloat] = Array(repeating: 0, count: SpeechManager.barCount)

    /// When on, presses Return after pasting so the text is submitted (e.g. runs
    /// in a terminal). Persisted across launches.
    @Published var autoSubmit: Bool = UserDefaults.standard.object(forKey: "autoSubmit") as? Bool ?? false {
        didSet { UserDefaults.standard.set(autoSubmit, forKey: "autoSubmit") }
    }

    var isListening: Bool { phase == .listening }

    private let recognizer = SFSpeechRecognizer(locale: Locale(identifier: "en-US"))
    private var request: SFSpeechAudioBufferRecognitionRequest?
    private var task: SFSpeechRecognitionTask?
    private let audioEngine = AVAudioEngine()
    private let requestBox = AudioRequestBox()
    private var committedText = ""               // text from finished recognition segments
    private var sessionStartedAt: Date?          // current session start, for pause-aligned renewal
    private var sessionGen = 0                   // ignores callbacks from superseded sessions
    private var warmedUp = false                 // on-device model preloaded?
    private var failureRenewals = 0              // guards against an endless error→renew loop
    private var tapInstalled = false
    private var didFinalize = true
    private var peakLevel: CGFloat = 0   // loudest level heard this session
    private var targetApp: NSRunningApplication?   // where text should land

    // MARK: Command file (Hermes / scripts can write start|stop|toggle)

    private var commandTimer: Timer?

    func startCommandWatcher() {
        let url = FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent(".talky/talky_cmd")
        commandTimer = Timer.scheduledTimer(withTimeInterval: 0.4, repeats: true) { [weak self] _ in
            guard let raw = try? String(contentsOf: url, encoding: .utf8) else { return }
            let cmd = raw.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
            guard !cmd.isEmpty else { return }
            try? "".write(to: url, atomically: true, encoding: .utf8)   // consume
            Task { @MainActor in
                guard let self else { return }
                switch cmd {
                case "start":  if !self.isListening { self.toggle() }
                case "stop":   if self.isListening { self.toggle() }
                case "toggle": self.toggle()
                default:       break
                }
            }
        }
    }

    // MARK: Permissions

    func requestPermissions() {
        // If a system prompt is about to appear, drop the always-on-top panel so
        // the dialog isn't hidden behind it.
        if SFSpeechRecognizer.authorizationStatus() == .notDetermined {
            PanelChrome.dropForPrompt()
        }
        SFSpeechRecognizer.requestAuthorization { status in
            Task { @MainActor [weak self] in
                guard let self else { return }
                switch status {
                case .authorized:
                    if self.recognizer?.isAvailable == true {
                        self.phase = .idle
                        self.statusMessage = "Tap to speak"
                        self.warmUpRecognizer()
                    } else {
                        self.phase = .unavailable
                        self.statusMessage = "Recognition unavailable"
                    }
                case .denied, .restricted:
                    self.phase = .denied
                    self.statusMessage = "Allow Speech Recognition in Settings"
                case .notDetermined:
                    self.statusMessage = "Awaiting permission…"
                @unknown default:
                    self.phase = .unavailable
                    self.statusMessage = "Recognition unavailable"
                }
            }
        }
    }

    // MARK: Control

    func toggle() {
        switch phase {
        case .listening:  stop()
        case .processing: break
        default:          start()
        }
    }


    private func start() {
        guard let recognizer, recognizer.isAvailable else {
            phase = .unavailable
            statusMessage = "Recognition unavailable"
            return
        }

        teardownAudio()   // ensure the mic isn't already held

        // Reset state for a fresh capture.
        transcribedText = ""
        committedText = ""
        didFinalize = false
        failureRenewals = 0
        peakLevel = 0
        flattenLevels()
        // Remember which app was frontmost NOW, before any focus shift, so we insert
        // the text back into it rather than wherever focus ends up later.
        targetApp = NSWorkspace.shared.frontmostApplication

        // First mic use triggers the system microphone prompt — make room for it.
        if AVCaptureDevice.authorizationStatus(for: .audio) == .notDetermined {
            PanelChrome.dropForPrompt()
        }

        let input = audioEngine.inputNode
        let format = input.outputFormat(forBus: 0)
        guard format.sampleRate > 0 else {
            phase = .idle
            statusMessage = "No microphone detected"
            return
        }

        // Tap appends to whatever request is currently live (via the box), so long
        // dictations can renew the recognition session without losing the mic.
        input.installTap(onBus: 0, bufferSize: 1024, format: format) { [weak self, box = requestBox] buffer, _ in
            box.request?.append(buffer)
            let rms = Self.rms(of: buffer)
            Task { @MainActor [weak self] in self?.updateLevel(rms) }
        }
        tapInstalled = true

        // Open the recognition session BEFORE the engine starts so the very first
        // audio buffers are captured instead of dropped.
        startRecognitionSession()

        audioEngine.prepare()
        do {
            try audioEngine.start()
        } catch {
            task?.cancel(); task = nil
            teardownAudio()
            phase = .idle
            statusMessage = "Couldn’t start the microphone"
            return
        }

        phase = .listening
        statusMessage = "Listening…"
    }

    /// Opens a fresh recognition request + task on the already-running engine.
    /// A long dictation spans several of these; `committedText` holds the finished
    /// segments so nothing is lost across renewals.
    /// Loads the on-device speech model into memory at launch by running a short
    /// silent recognition. Without this, the first real capture loses its opening
    /// seconds while the model cold-loads. Mic-free (feeds silence, not the mic).
    private func warmUpRecognizer() {
        guard !warmedUp, let recognizer, recognizer.supportsOnDeviceRecognition else { return }
        warmedUp = true
        let req = SFSpeechAudioBufferRecognitionRequest()
        req.requiresOnDeviceRecognition = true
        req.shouldReportPartialResults = false
        guard let fmt = AVAudioFormat(standardFormatWithSampleRate: 16000, channels: 1),
              let buf = AVAudioPCMBuffer(pcmFormat: fmt, frameCapacity: 16000) else { return }
        buf.frameLength = 16000   // 1s of silence
        let warmTask = recognizer.recognitionTask(with: req) { _, _ in }
        req.append(buf)
        req.endAudio()
        Task { @MainActor in
            try? await Task.sleep(nanoseconds: 3_000_000_000)
            warmTask.cancel()
        }
    }

    private func startRecognitionSession() {
        guard let recognizer else { return }
        sessionGen += 1
        sessionStartedAt = Date()
        let gen = sessionGen
        let request = SFSpeechAudioBufferRecognitionRequest()
        request.shouldReportPartialResults = true
        if recognizer.supportsOnDeviceRecognition { request.requiresOnDeviceRecognition = true }
        requestBox.request = request
        self.request = request
        task = recognizer.recognitionTask(with: request) { [weak self] result, error in
            let seg = result?.bestTranscription.formattedString
            let isFinal = result?.isFinal ?? false
            let failed = error != nil
            Task { @MainActor [weak self] in self?.handleResult(seg, isFinal: isFinal, failed: failed, gen: gen) }
        }
    }

    private func handleResult(_ segment: String?, isFinal: Bool, failed: Bool, gen: Int) {
        guard gen == sessionGen else { return }                 // stale session — ignore
        guard phase == .listening || phase == .processing else { return }

        if let segment, !segment.isEmpty {
            transcribedText = combine(committedText, segment)
            failureRenewals = 0                                 // healthy output resets the guard
        }

        if failed {
            // A session can end early (limit hit / transient error). While the user
            // is still talking, commit what we have and start a fresh session rather
            // than ending the whole capture.
            if phase == .listening {
                committedText = transcribedText
                failureRenewals += 1
                if failureRenewals <= 6 { startRecognitionSession() } else { finalize() }
            } else {
                finalize()
            }
            return
        }

        if isFinal {
            if let segment, !segment.isEmpty { committedText = combine(committedText, segment) }
            transcribedText = committedText
            if phase == .listening {
                renewRecognition()   // user hasn't stopped — keep capturing
            } else {
                finalize()
            }
        }
    }

    /// Ends the current recognition session and immediately opens a new one,
    /// keeping the mic/tap running. Lets capture continue indefinitely.
    private func renewRecognition() {
        guard phase == .listening else { return }
        committedText = transcribedText
        task?.cancel(); task = nil
        requestBox.request?.endAudio()
        startRecognitionSession()
    }

    private func combine(_ a: String, _ b: String) -> String {
        if a.isEmpty { return b }
        if b.isEmpty { return a }
        return a + " " + b
    }

    private func stop() {
        guard phase == .listening else { return }
        phase = .processing
        statusMessage = "Transcribing…"
        sessionStartedAt = nil
        flattenLevels()

        teardownAudio()
        request?.endAudio()

        // Fallback: if no final result arrives shortly, finalize with what we have.
        Task { @MainActor [weak self] in
            try? await Task.sleep(nanoseconds: 1_500_000_000)
            self?.finalize()
        }
    }

    private func finalize() {
        guard !didFinalize else { return }
        didFinalize = true

        sessionStartedAt = nil
        task?.cancel()
        task = nil
        requestBox.request = nil
        request = nil
        teardownAudio()

        phase = .idle
        flattenLevels()
        let text = transcribedText.trimmingCharacters(in: .whitespacesAndNewlines)
        committedText = ""
        if text.isEmpty {
            // Distinguish "mic heard nothing" from "heard you but couldn't transcribe".
            if peakLevel < 0.02 {
                let mic = AVCaptureDevice.default(for: .audio)?.localizedName ?? "your mic"
                statusMessage = "No sound from \(mic) — move closer or speak up"
            } else {
                statusMessage = "Didn’t catch that — try again"
            }
        } else {
            deliver(text)
        }
    }

    private func teardownAudio() {
        if audioEngine.isRunning { audioEngine.stop() }
        if tapInstalled {
            audioEngine.inputNode.removeTap(onBus: 0)
            tapInstalled = false
        }
    }

    private func updateLevel(_ rms: Float) {
        let target = min(1, CGFloat(rms) * 14)
        audioLevel = audioLevel * 0.6 + target * 0.4
        peakLevel = max(peakLevel, audioLevel)
        var l = levels
        l.removeFirst()
        l.append(audioLevel)
        levels = l

        // Pause-aligned renewal: renew the recognition session during a brief
        // silence (no words to clip) once it's run a while, or force it before any
        // per-session limit. Keeps long captures gapless.
        if phase == .listening, let started = sessionStartedAt {
            let age = Date().timeIntervalSince(started)
            let silent = audioLevel < 0.06
            let hasNewSpeech = transcribedText.count > committedText.count
            if (age > 16 && silent && hasNewSpeech) || age > 45 {
                renewRecognition()
            }
        }
    }

    private func flattenLevels() {
        audioLevel = 0
        levels = Array(repeating: 0, count: Self.barCount)
    }

    /// Root-mean-square amplitude of a buffer, used to drive the orb.
    nonisolated static func rms(of buffer: AVAudioPCMBuffer) -> Float {
        guard let data = buffer.floatChannelData?[0] else { return 0 }
        let n = Int(buffer.frameLength)
        guard n > 0 else { return 0 }
        var sum: Float = 0
        for i in 0..<n { let s = data[i]; sum += s * s }
        return (sum / Float(n)).squareRoot()
    }

    // MARK: History

    private static let dayFormatter: DateFormatter = {
        let f = DateFormatter()
        f.locale = Locale(identifier: "en_US_POSIX")
        f.dateFormat = "yyyy-MM-dd"
        return f
    }()

    private static let timeFormatter: DateFormatter = {
        let f = DateFormatter()
        f.locale = Locale(identifier: "en_US_POSIX")
        f.dateFormat = "HH:mm:ss"
        return f
    }()

    /// Appends one timestamped entry to a per-day history file so every dictation
    /// is kept, browsable by date. Never overwrites.
    private func appendHistory(_ text: String, in hermesDir: URL) {
        let now = Date()
        let historyDir = hermesDir.appendingPathComponent("voice_history")
        try? FileManager.default.createDirectory(at: historyDir, withIntermediateDirectories: true)

        let dayFile = historyDir.appendingPathComponent("\(Self.dayFormatter.string(from: now)).md")
        let isNew = !FileManager.default.fileExists(atPath: dayFile.path)

        var chunk = ""
        if isNew {
            chunk += "# Voice history — \(Self.dayFormatter.string(from: now))\n\n"
        }
        chunk += "## \(Self.timeFormatter.string(from: now))\n\(text)\n\n"

        guard let data = chunk.data(using: .utf8) else { return }
        if isNew {
            try? data.write(to: dayFile)
        } else if let handle = try? FileHandle(forWritingTo: dayFile) {
            defer { try? handle.close() }
            _ = try? handle.seekToEnd()
            try? handle.write(contentsOf: data)
        }
    }

    /// Full history as structured entries, newest first, across all days.
    func loadHistory() -> [HistoryItem] {
        let dir = FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent(".talky/voice_history")
        guard let files = try? FileManager.default.contentsOfDirectory(
            at: dir, includingPropertiesForKeys: nil) else { return [] }
        let days = files.filter { $0.pathExtension == "md" }
            .sorted { $0.lastPathComponent > $1.lastPathComponent }   // newest day first

        var items: [HistoryItem] = []
        for file in days {
            let date = file.deletingPathExtension().lastPathComponent
            guard let content = try? String(contentsOf: file, encoding: .utf8) else { continue }
            var dayItems: [HistoryItem] = []
            var time: String?
            var lines: [String] = []
            func flush() {
                if let t = time {
                    let body = lines.joined(separator: "\n").trimmingCharacters(in: .whitespacesAndNewlines)
                    if !body.isEmpty { dayItems.append(HistoryItem(date: date, time: t, text: body)) }
                }
                time = nil; lines = []
            }
            for line in content.components(separatedBy: "\n") {
                if line.hasPrefix("## ") {
                    flush()
                    time = String(line.dropFirst(3)).trimmingCharacters(in: .whitespaces)
                } else if line.hasPrefix("# ") {
                    flush()                       // day header
                } else if time != nil {
                    lines.append(line)
                }
            }
            flush()
            items.append(contentsOf: dayItems.reversed())   // newest entry of the day first
        }
        return items
    }

    // MARK: Delivery — clipboard, auto-paste, and the Hermes hand-off file

    private func deliver(_ text: String) {
        // 1. Persist for any Hermes process watching the file (latest only).
        let dir = FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent(".talky")
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        try? text.write(to: dir.appendingPathComponent("voice_input.txt"),
                        atomically: true, encoding: .utf8)

        // 1b. Append to the dated, timestamped conversation history (never overwritten).
        appendHistory(text, in: dir)

        // 2. Always put it on the clipboard — a universal fallback you can ⌘V
        //    anywhere, even if auto-paste fails.
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(text, forType: .string)

        // 3. Auto-paste into the app that was focused when you started, using ⌘V.
        //    ⌘V works everywhere (Terminal, editors, chat) — unlike per-app text
        //    insertion, which some apps (e.g. Terminal) reject.
        guard Paster.isTrusted else {
            statusMessage = "Copied — enable Accessibility to auto-paste"
            PanelChrome.dropForPrompt()
            Paster.requestTrust()
            return
        }

        let submit = autoSubmit
        let target = targetApp
        let appName = target?.localizedName ?? "the active app"
        statusMessage = submit ? "Sent to \(appName) ✓" : "Pasted into \(appName) ✓"
        Task { @MainActor in
            target?.activate()   // make sure the paste lands in the intended app
            try? await Task.sleep(nanoseconds: 120_000_000)
            Paster.paste()
            if submit {
                try? await Task.sleep(nanoseconds: 90_000_000)
                Paster.pressReturn()
            }
        }
    }
}

// MARK: - Direct text insertion

enum TextInserter {
    /// Inserts text at the cursor in the target app. Tries the Accessibility API
    /// against that specific app first, then the system-wide focused element, then
    /// falls back to synthesizing Unicode keystrokes. Returns true if a real text
    /// field accepted the text (AX path), false if it had to type blind.
    @discardableResult
    static func insert(_ text: String, into app: NSRunningApplication?) -> Bool {
        if let pid = app?.processIdentifier, axInsert(text, pid: pid) { return true }
        if axInsertSystemWide(text) { return true }
        typeUnicode(text)
        return false
    }

    /// Sets the focused text element of a specific application (by pid).
    private static func axInsert(_ text: String, pid: pid_t) -> Bool {
        let appElement = AXUIElementCreateApplication(pid)
        var focusedRef: CFTypeRef?
        guard AXUIElementCopyAttributeValue(appElement, kAXFocusedUIElementAttribute as CFString, &focusedRef) == .success,
              let focused = focusedRef else { return false }
        return setSelectedText(focused as! AXUIElement, text)
    }

    /// Sets the system-wide focused text element (fallback when the app-targeted
    /// lookup misses).
    private static func axInsertSystemWide(_ text: String) -> Bool {
        let system = AXUIElementCreateSystemWide()
        var focusedRef: CFTypeRef?
        guard AXUIElementCopyAttributeValue(system, kAXFocusedUIElementAttribute as CFString, &focusedRef) == .success,
              let focused = focusedRef else { return false }
        return setSelectedText(focused as! AXUIElement, text)
    }

    /// Inserts at the caret (replacing any selection) if the element accepts it.
    private static func setSelectedText(_ element: AXUIElement, _ text: String) -> Bool {
        var settable: DarwinBoolean = false
        guard AXUIElementIsAttributeSettable(element, kAXSelectedTextAttribute as CFString, &settable) == .success,
              settable.boolValue else { return false }
        return AXUIElementSetAttributeValue(element, kAXSelectedTextAttribute as CFString, text as CFString) == .success
    }

    /// Types the text as synthetic Unicode keystrokes. Works in nearly every app
    /// and never touches the clipboard.
    private static func typeUnicode(_ text: String) {
        guard let source = CGEventSource(stateID: .combinedSessionState) else { return }
        let utf16 = Array(text.utf16)
        let chunkSize = 20
        var index = 0
        while index < utf16.count {
            let chunk = Array(utf16[index..<min(index + chunkSize, utf16.count)])
            for isKeyDown in [true, false] {
                guard let event = CGEvent(keyboardEventSource: source, virtualKey: 0, keyDown: isKeyDown) else { continue }
                chunk.withUnsafeBufferPointer { buffer in
                    event.keyboardSetUnicodeString(stringLength: chunk.count, unicodeString: buffer.baseAddress)
                }
                event.post(tap: .cghidEventTap)
            }
            index += chunkSize
        }
    }
}

// MARK: - Accessibility trust + key synthesis

enum Paster {
    /// Whether we're allowed to post synthetic keyboard events (Accessibility permission).
    static var isTrusted: Bool { AXIsProcessTrusted() }

    /// Prompts the user to grant Accessibility access (shows the system dialog once).
    @discardableResult
    static func requestTrust() -> Bool {
        let key = kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String
        return AXIsProcessTrustedWithOptions([key: true] as CFDictionary)
    }

    /// Simulates ⌘V to paste the clipboard into the focused app.
    static func paste() {
        guard let source = CGEventSource(stateID: .combinedSessionState) else { return }
        let v: CGKeyCode = 9 // ANSI "v"
        let down = CGEvent(keyboardEventSource: source, virtualKey: v, keyDown: true)
        down?.flags = .maskCommand
        let up = CGEvent(keyboardEventSource: source, virtualKey: v, keyDown: false)
        up?.flags = .maskCommand
        down?.post(tap: .cghidEventTap)
        up?.post(tap: .cghidEventTap)
    }

    /// Simulates Return to submit whatever was just pasted.
    static func pressReturn() {
        guard let source = CGEventSource(stateID: .combinedSessionState) else { return }
        let returnKeyCode: CGKeyCode = 36 // Return

        let keyDown = CGEvent(keyboardEventSource: source, virtualKey: returnKeyCode, keyDown: true)
        let keyUp = CGEvent(keyboardEventSource: source, virtualKey: returnKeyCode, keyDown: false)

        keyDown?.post(tap: .cghidEventTap)
        keyUp?.post(tap: .cghidEventTap)
    }
}

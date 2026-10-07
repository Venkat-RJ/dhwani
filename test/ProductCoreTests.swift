import Foundation
import Darwin
import CoreGraphics

@main
struct ProductCoreTests {
    static var count = 0

    static func check(_ name: String, _ test: () throws -> Void) throws {
        try test(); count += 1; print("PASS: " + name)
    }
    static func expect(_ value: Bool, _ message: String = "Assertion failed") throws {
        if !value { throw NSError(domain: "TalkyTests", code: 1, userInfo: [NSLocalizedDescriptionKey: message]) }
    }
    static func mode(_ url: URL) throws -> Int {
        let attrs = try FileManager.default.attributesOfItem(atPath: url.path)
        return (attrs[.posixPermissions] as! NSNumber).intValue
    }
    static func expectFailure(_ test: () throws -> Void) throws {
        do { try test() } catch { return }
        throw NSError(domain: "TalkyTests", code: 2, userInfo: [NSLocalizedDescriptionKey: "Expected a failure"])
    }
    static func main() throws {
        let manager = FileManager.default
        let temp = manager.temporaryDirectory.appendingPathComponent("talky-product-tests-" + UUID().uuidString)
        try manager.createDirectory(at: temp, withIntermediateDirectories: false)
        defer { try? manager.removeItem(at: temp) }
        let originalMask = umask(0o022)
        defer { umask(originalMask) }
        let store = TalkyStore(root: temp.appendingPathComponent(".talky"))

        try check("expanded controls stay on the selected display at every screen edge") {
            let screen = CGRect(x: 100, y: 50, width: 1440, height: 800)
            for point in [CGPoint(x: 100, y: 50), CGPoint(x: 1540, y: 50), CGPoint(x: 100, y: 850), CGPoint(x: 1540, y: 850)] {
                let expanded = CGRect(x: point.x - 190, y: point.y - 320, width: 380, height: 640)
                let placed = PanelPlacement.constrained(expanded, to: screen)
                try expect(screen.contains(placed))
                try expect(placed.size == expanded.size)
            }
            let centered = CGRect(x: 630, y: 130, width: 380, height: 640)
            try expect(PanelPlacement.constrained(centered, to: screen) == centered)
            let smallScreen = CGRect(x: 0, y: 0, width: 1280, height: 600)
            let fitted = PanelPlacement.constrained(centered, to: smallScreen)
            try expect(smallScreen.contains(fitted))
            try expect(fitted.height == 600 && fitted.width == 380)
        }

        try check("storage is owner-only under umask 022") {
            try store.prepare()
            try store.writeLatest("Private test text")
            let record = TalkyHistoryRecord(text: "One entry", language: "en-US")
            try store.appendHistory(record)
            try expect(try mode(store.root) == 0o700)
            try expect(try mode(store.root.appendingPathComponent("voice_input.txt")) == 0o600)
            let history = store.root.appendingPathComponent("voice_history")
            try expect(try mode(history) == 0o700)
            for file in try store.historyFiles() { try expect(try mode(file) == 0o600) }
        }
        try check("atomic replacement keeps private file permissions") {
            try store.writeLatest("Second text")
            try expect(try mode(store.root.appendingPathComponent("voice_input.txt")) == 0o600)
            try expect(try String(contentsOf: store.root.appendingPathComponent("voice_input.txt"), encoding: .utf8) == "Second text")
        }
        try check("history retains newlines and markdown-like dictation without splitting entries") {
            let text = "First line\n## 10:20:30\n# another heading\nLast line"
            let record = TalkyHistoryRecord(text: text, language: "en-IN")
            try store.appendHistory(record)
            let records = try store.loadRecords()
            try expect(records.contains { $0.id == record.id && $0.text == text && $0.language == "en-IN" })
        }
        try check("legacy history preserves ordinary markdown headings") {
            let records = TalkyHistoryRecord.parseLegacy("# Voice history\n## 12:30:00\nHello\n# heading\n## ordinary subheading\n", day: "2026-01-01")
            try expect(records.count == 1)
            try expect(records[0].text.contains("# heading\n## ordinary subheading"))
        }
        try check("preparation repairs legacy permissive permissions") {
            try manager.setAttributes([.posixPermissions: 0o755], ofItemAtPath: store.root.path)
            try manager.setAttributes([.posixPermissions: 0o644], ofItemAtPath: store.root.appendingPathComponent("voice_input.txt").path)
            try store.prepare()
            try expect(try mode(store.root) == 0o700)
            try expect(try mode(store.root.appendingPathComponent("voice_input.txt")) == 0o600)
        }
        try check("preparation removes extended ACL access on private files") {
            let file = store.root.appendingPathComponent("voice_input.txt")
            let command = Process()
            command.executableURL = URL(fileURLWithPath: "/bin/chmod")
            command.arguments = ["+a", "everyone allow read", file.path]
            try command.run(); command.waitUntilExit()
            try expect(command.terminationStatus == 0)
            func hasEntry(_ url: URL) throws -> Bool {
                guard let acl = acl_get_file(url.path, ACL_TYPE_EXTENDED) else {
                    if errno == ENOENT { return false }
                    throw NSError(domain: NSPOSIXErrorDomain, code: Int(errno))
                }
                defer { acl_free(UnsafeMutableRawPointer(acl)) }
                var entry: acl_entry_t?
                return acl_get_entry(acl, Int32(ACL_FIRST_ENTRY.rawValue), &entry) == 0
            }
            try expect(try hasEntry(file))
            try store.prepare()
            try expect(try !hasEntry(file))
        }
        try check("symlinked storage root is rejected") {
            let linked = temp.appendingPathComponent("linked-root")
            try manager.createSymbolicLink(at: linked, withDestinationURL: store.root)
            try expectFailure { try TalkyStore(root: linked).prepare() }
        }
        try check("symlinked transcript is rejected without touching its target") {
            let root = temp.appendingPathComponent("other-store")
            let other = TalkyStore(root: root); try other.prepare()
            let victim = temp.appendingPathComponent("victim.txt")
            try "Keep this".write(to: victim, atomically: true, encoding: .utf8)
            try manager.createSymbolicLink(at: root.appendingPathComponent("voice_input.txt"), withDestinationURL: victim)
            try expectFailure { try other.writeLatest("Overwrite") }
            try expect(try String(contentsOf: victim, encoding: .utf8) == "Keep this")
        }
        try check("command consumption is bounded and one-shot") {
            let file = store.root.appendingPathComponent("talky_cmd")
            try store.write(Data("  test-start:example\n".utf8), to: file)
            try expect(try store.consumeCommand() == "test-start:example")
            try expect(try store.consumeCommand() == nil)
            try store.write(Data(repeating: 65, count: 1025), to: file)
            try expectFailure { _ = try store.consumeCommand() }
            try store.write(Data(), to: file)
        }
        try check("retention removes expired dated files and preserves current files") {
            let old = ISO8601DateFormatter().date(from: "2020-01-01T10:00:00Z")!
            let now = ISO8601DateFormatter().date(from: "2026-10-07T10:00:00Z")!
            try store.appendHistory(TalkyHistoryRecord(text: "Expired", language: "en-US", now: old))
            try store.appendHistory(TalkyHistoryRecord(text: "Keep", language: "en-US", now: now))
            let cutoff = ISO8601DateFormatter().date(from: "2026-10-01T00:00:00Z")!
            try store.pruneHistory(olderThan: cutoff)
            let records = try store.loadRecords()
            try expect(!records.contains { $0.text == "Expired" })
            try expect(records.contains { $0.text == "Keep" })
        }
        try check("retention applies the exact cutoff within a single day") {
            let cutoff = ISO8601DateFormatter().date(from: "2026-10-07T12:00:00Z")!
            try store.appendHistory(TalkyHistoryRecord(text: "Before cutoff", language: "en-US", now: cutoff.addingTimeInterval(-1)))
            try store.appendHistory(TalkyHistoryRecord(text: "At cutoff", language: "en-US", now: cutoff))
            try store.appendHistory(TalkyHistoryRecord(text: "After cutoff", language: "en-US", now: cutoff.addingTimeInterval(1)))
            try store.pruneHistory(olderThan: cutoff)
            let records = try store.loadRecords()
            try expect(!records.contains { $0.text == "Before cutoff" })
            try expect(records.contains { $0.text == "At cutoff" })
            try expect(records.contains { $0.text == "After cutoff" })
        }
        try check("clear history does not delete the command or latest transcript") {
            try store.clearHistory()
            try expect(try store.loadRecords().isEmpty)
            try expect(manager.fileExists(atPath: store.root.appendingPathComponent("voice_input.txt").path))
            try expect(manager.fileExists(atPath: store.root.appendingPathComponent("talky_cmd").path))
        }
        try check("disabling automation can remove the latest transcript") {
            try store.removeLatest()
            try expect(!manager.fileExists(atPath: store.root.appendingPathComponent("voice_input.txt").path))
        }
        try check("test result is private and bound to its UUID without a normal transcript file") {
            let id = UUID().uuidString
            let result = TalkyTestResult(runID: id, phase: "completed", transcript: "Test only", error: nil,
                startedAt: "2026-10-07T10:00:00Z", finishedAt: "2026-10-07T10:00:02Z", microphone: "BlackHole 2ch")
            try store.writeTestResult(result)
            let file = store.root.appendingPathComponent("test-results/" + id + ".json")
            let decoded = try JSONDecoder().decode(TalkyTestResult.self, from: Data(contentsOf: file))
            try expect(decoded.runID == id && decoded.transcript == "Test only")
            try expect(try mode(file) == 0o600)
            try expect(!manager.fileExists(atPath: store.root.appendingPathComponent("voice_input.txt").path))
        }
        try check("export strips inherited access before writing private history") {
            let dir = temp.appendingPathComponent("export")
            try manager.createDirectory(at: dir, withIntermediateDirectories: false)
            let command = Process()
            command.executableURL = URL(fileURLWithPath: "/bin/chmod")
            command.arguments = ["+a", "everyone allow read,file_inherit,directory_inherit", dir.path]
            try command.run(); command.waitUntilExit()
            try expect(command.terminationStatus == 0)
            let file = dir.appendingPathComponent("history.txt")
            try store.export(Data("Private exported text".utf8), to: file)
            try expect(try mode(file) == 0o600)
            try expect(try String(contentsOf: file, encoding: .utf8) == "Private exported text")
            if let acl = acl_get_file(file.path, ACL_TYPE_EXTENDED) {
                defer { acl_free(UnsafeMutableRawPointer(acl)) }
                var entry: acl_entry_t?
                try expect(acl_get_entry(acl, Int32(ACL_FIRST_ENTRY.rawValue), &entry) != 0)
            } else { try expect(errno == ENOENT) }
            try expect(try manager.contentsOfDirectory(atPath: dir.path) == ["history.txt"])
        }
        try check("delivery is allowed only when every safety check passes") {
            try expect(DeliverySafety(trusted: true, targetAlive: true, sameApplication: true, sameElement: true,
                clipboardUnchanged: true, secureField: false).blockedReason == nil)
        }
        try check("each lost delivery precondition blocks paste and submit") {
            let blocked = [
                DeliverySafety(trusted: false, targetAlive: true, sameApplication: true, sameElement: true, clipboardUnchanged: true, secureField: false),
                DeliverySafety(trusted: true, targetAlive: false, sameApplication: true, sameElement: true, clipboardUnchanged: true, secureField: false),
                DeliverySafety(trusted: true, targetAlive: true, sameApplication: false, sameElement: true, clipboardUnchanged: true, secureField: false),
                DeliverySafety(trusted: true, targetAlive: true, sameApplication: true, sameElement: false, clipboardUnchanged: true, secureField: false),
                DeliverySafety(trusted: true, targetAlive: true, sameApplication: true, sameElement: true, clipboardUnchanged: false, secureField: false),
                DeliverySafety(trusted: true, targetAlive: true, sameApplication: true, sameElement: true, clipboardUnchanged: true, secureField: true)
            ]
            try expect(blocked.allSatisfy { $0.blockedReason != nil })
        }
        print("Passed \(count) product core tests")
    }
}

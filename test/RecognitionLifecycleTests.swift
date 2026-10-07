import Foundation

private struct TestFailure: Error, CustomStringConvertible {
    let description: String
}

private func expect(_ condition: @autoclosure () -> Bool, _ message: String,
                    line: Int = #line) throws {
    if !condition() { throw TestFailure(description: "line \(line): \(message)") }
}

@main
private enum RecognitionLifecycleTests {
    static func main() throws {
        let tests: [(String, () throws -> Void)] = [
            ("previous capture timeout cannot finish the next capture", staleCapture),
            ("stop waits for the final tail of every draining session", drainingTail),
            ("partial corrections replace snapshots in audio order", orderedCorrections),
            ("duplicate completion and late partial callbacks are ignored", duplicateCompletion),
            ("cancellation produces no deliverable transcript", cancellation),
            ("forced deadline preserves partial text and delivers once", forcedDeadline),
            ("stopped and inactive captures cannot start another segment", segmentGuards),
            ("failed draining session preserves its last partial", failedSession),
            ("new capture discards all prior segment state", captureReset),
            ("empty final correction removes a mistaken partial", emptyCorrection),
        ]
        for (name, test) in tests {
            do {
                try test()
                print("PASS: \(name)")
            } catch {
                fputs("FAIL: \(name): \(error)\n", stderr)
                throw error
            }
        }
        print("Passed \(tests.count) recognition lifecycle tests")
    }

    private static func staleCapture() throws {
        var state = RecognitionLifecycle()
        let first = state.beginCapture()
        let a = state.beginSegment()!
        state.receive("first capture", isFinal: true, failed: false, token: a)
        try expect(state.stop(capture: first), "first stop rejected")
        try expect(state.finish(capture: first) == "first capture", "first capture did not finish")

        let second = state.beginCapture()
        let b = state.beginSegment()!
        state.receive("second capture", isFinal: false, failed: false, token: b)
        try expect(state.finish(capture: first) == nil, "old fallback finished listening capture")
        try expect(!state.stop(capture: first), "old stop sealed the next capture")
        try expect(!state.cancel(capture: first), "old cancellation canceled the next capture")
        try expect(!state.receive("stale result", isFinal: true, failed: false, token: a),
                   "old recognition callback was accepted")
        try expect(state.transcript == "second capture", "old callback changed transcript")

        state.stop(capture: second)
        try expect(state.finish(capture: first) == nil, "old fallback finished processing capture")
        try expect(state.finish(capture: second) == "second capture", "current deadline rejected")
    }

    private static func drainingTail() throws {
        var state = RecognitionLifecycle()
        let capture = state.beginCapture()
        let first = state.beginSegment()!
        state.receive("the beginning", isFinal: false, failed: false, token: first)
        let second = state.beginSegment()!
        state.receive("the ending", isFinal: true, failed: false, token: second)
        state.stop(capture: capture)
        try expect(!state.canFinalize, "stop ignored an older unfinished session")
        try expect(state.receive("the beginning and its final tail", isFinal: true,
                                 failed: false, token: first), "older final result was discarded")
        try expect(state.canFinalize, "completed draining session did not release stop")
        try expect(state.finish(capture: capture) == "the beginning and its final tail the ending",
                   "late final tail was lost or reordered")
    }

    private static func orderedCorrections() throws {
        var state = RecognitionLifecycle()
        let capture = state.beginCapture()
        let a = state.beginSegment()!
        state.receive("a wrong phrase", isFinal: false, failed: false, token: a)
        let b = state.beginSegment()!
        state.receive("third", isFinal: false, failed: false, token: b)
        state.receive("first second", isFinal: true, failed: false, token: a)
        state.receive("third fourth", isFinal: true, failed: false, token: b)
        try expect(state.transcript == "first second third fourth", "snapshots accumulated duplicates")
        state.stop(capture: capture)
        try expect(state.canFinalize, "final segments remained pending")
    }

    private static func duplicateCompletion() throws {
        var state = RecognitionLifecycle()
        let capture = state.beginCapture()
        let token = state.beginSegment()!
        state.receive("only once", isFinal: true, failed: false, token: token)
        try expect(!state.receive("only once", isFinal: true, failed: false, token: token),
                   "duplicate final result accepted")
        try expect(!state.receive("corrupt late partial", isFinal: false, failed: false, token: token),
                   "late partial replaced a final result")
        try expect(!state.receive(nil, isFinal: false, failed: true, token: token),
                   "duplicate error accepted")
        state.stop(capture: capture)
        try expect(state.finish(capture: capture) == "only once", "completion duplicated text")
        try expect(state.finish(capture: capture) == nil, "capture delivered twice")
    }

    private static func cancellation() throws {
        var state = RecognitionLifecycle()
        let capture = state.beginCapture()
        let token = state.beginSegment()!
        state.receive("do not send", isFinal: false, failed: false, token: token)
        try expect(state.cancel(capture: capture), "cancel rejected active capture")
        try expect(state.transcript.isEmpty, "canceled text retained")
        try expect(state.finish(capture: capture) == nil, "canceled text deliverable")
        try expect(!state.receive("late final", isFinal: true, failed: false, token: token),
                   "canceled callback accepted")
        try expect(!state.canFinalize, "canceled capture still waiting for delivery")
    }

    private static func forcedDeadline() throws {
        var state = RecognitionLifecycle()
        let capture = state.beginCapture()
        let token = state.beginSegment()!
        state.receive("best available partial", isFinal: false, failed: false, token: token)
        try expect(state.finish(capture: capture) == nil, "listening capture was delivered")
        state.stop(capture: capture)
        try expect(!state.canFinalize, "partial segment marked final")
        try expect(state.finish(capture: capture) == "best available partial", "deadline lost partial text")
        try expect(!state.receive("too late", isFinal: true, failed: false, token: token),
                   "post-deadline callback accepted")
        try expect(state.finish(capture: capture) == nil, "deadline delivered twice")
    }

    private static func segmentGuards() throws {
        var state = RecognitionLifecycle()
        try expect(state.beginSegment() == nil, "inactive state opened a segment")
        let capture = state.beginCapture()
        try expect(state.beginSegment() != nil, "active capture rejected its first segment")
        state.stop(capture: capture)
        try expect(state.beginSegment() == nil, "stop opened a new segment")
        try expect(!state.stop(capture: capture), "duplicate stop accepted")
        _ = state.finish(capture: capture)
        try expect(state.beginSegment() == nil, "finished capture opened a segment")
    }

    private static func failedSession() throws {
        var state = RecognitionLifecycle()
        let capture = state.beginCapture()
        let a = state.beginSegment()!
        state.receive("heard before error", isFinal: false, failed: false, token: a)
        let b = state.beginSegment()!
        state.receive("heard after renewal", isFinal: true, failed: false, token: b)
        state.stop(capture: capture)
        try expect(!state.canFinalize, "unfinished first segment ignored")
        state.receive(nil, isFinal: false, failed: true, token: a)
        try expect(state.canFinalize, "failed session prevented finishing")
        try expect(state.finish(capture: capture) == "heard before error heard after renewal",
                   "failure lost previously heard text")
    }

    private static func captureReset() throws {
        var state = RecognitionLifecycle()
        let oldCapture = state.beginCapture()
        let oldToken = state.beginSegment()!
        state.receive("old text", isFinal: false, failed: false, token: oldToken)
        state.stop(capture: oldCapture)
        let newCapture = state.beginCapture()
        try expect(newCapture > oldCapture, "capture identifier reused")
        try expect(state.transcript.isEmpty && !state.isStopping, "capture retained old state")
        try expect(state.activeToken == nil, "capture retained old active token")
        let newToken = state.beginSegment()!
        try expect(newToken.capture == newCapture, "new segment has wrong capture")
        try expect(!state.receive("late old final", isFinal: true, failed: false, token: oldToken),
                   "previous capture segment accepted after reset")
        let unknown = RecognitionLifecycle.Token(capture: newCapture, segment: 999)
        try expect(!state.receive("unknown", isFinal: true, failed: false, token: unknown),
                   "unregistered segment accepted")
    }

    private static func emptyCorrection() throws {
        var state = RecognitionLifecycle()
        let capture = state.beginCapture()
        let token = state.beginSegment()!
        state.receive("mistaken words", isFinal: false, failed: false, token: token)
        state.receive("", isFinal: true, failed: false, token: token)
        state.stop(capture: capture)
        try expect(state.canFinalize, "empty final still pending")
        try expect(state.finish(capture: capture) == "", "empty final kept mistaken partial")
    }
}

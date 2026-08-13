import Foundation

/// Anything a clip can record. A protocol rather than `SKNode` so the recorder
/// and player are testable without a running scene — the parts that decide
/// whether her fling *looks right* on your phone shouldn't need a simulator to
/// exercise.
@MainActor
protocol RecordableBody: AnyObject {
    /// Stable for the life of one fling. Bodies are matched back by position in
    /// `FlingClip.bodyIDs`, so this only has to be unique within a clip.
    var recordingID: String { get }
    var recordedPose: BodyPose { get }
    /// False once destroyed. Recorded per frame so a shattered piece vanishes
    /// on the watching phone instead of freezing in place.
    var isRecordingAlive: Bool { get }
}

/// Samples a fling as it happens.
///
/// **Time-driven, not call-driven.** `update(_:)` fires at the display's rate,
/// which is 60 or 120Hz depending on the phone — recording every call would
/// make the clip's length depend on which handset took the turn, and double its
/// size on a ProMotion screen for no visible gain.
@MainActor
final class FlingRecorder {
    private let bodies: [any RecordableBody]
    private let frameRate: Int
    private let interval: TimeInterval
    private var nextSampleAt: TimeInterval?
    private var frames: [FlingClip.Frame] = []

    init(bodies: [any RecordableBody], frameRate: Int = 30) {
        self.bodies = bodies
        self.frameRate = max(1, frameRate)
        self.interval = 1.0 / Double(max(1, frameRate))
    }

    /// - Returns: whether this call produced a frame, so a caller can tell
    ///   "recording" from "recording and actually capturing".
    @discardableResult
    func sample(at time: TimeInterval) -> Bool {
        if let next = nextSampleAt, time < next { return false }
        nextSampleAt = (nextSampleAt ?? time) + interval
        // Catch up rather than drift if a frame ran long.
        if let next = nextSampleAt, next < time { nextSampleAt = time + interval }

        frames.append(FlingClip.Frame(poses: bodies.map(\.recordedPose),
                                      present: bodies.map(\.isRecordingAlive)))
        return true
    }

    func finish() -> FlingClip {
        FlingClip(frameRate: frameRate, bodyIDs: bodies.map(\.recordingID), frames: frames)
    }
}

/// Reads a clip back at whatever rate the watching phone draws at.
enum FlingPlayer {
    struct Sample: Equatable {
        var poses: [BodyPose]
        var present: [Bool]
    }

    /// The state at `time` seconds into the clip, interpolated between frames.
    ///
    /// Interpolation matters: a 30Hz clip played on a 60 or 120Hz screen would
    /// otherwise visibly step. Before the start and after the end it clamps, so
    /// a watcher who joins late sees the final rubble rather than nothing.
    static func sample(_ clip: FlingClip, at time: TimeInterval) -> Sample? {
        guard !clip.frames.isEmpty else { return nil }
        guard clip.frameRate > 0 else {
            return Sample(poses: clip.frames[0].poses, present: clip.frames[0].present)
        }

        let exact = max(0, time) * Double(clip.frameRate)
        let lower = min(Int(exact), clip.frames.count - 1)
        let upper = min(lower + 1, clip.frames.count - 1)
        let t = lower == upper ? 0 : exact - Double(lower)

        let a = clip.frames[lower], b = clip.frames[upper]
        let poses = zip(a.poses, b.poses).map { from, to in
            BodyPose(x: from.x + (to.x - from.x) * t,
                     y: from.y + (to.y - from.y) * t,
                     angle: interpolate(angle: from.angle, to: to.angle, t: t))
        }
        // Presence never interpolates: a body is alive or it isn't, and the
        // frame it dies in is the frame it should disappear.
        return Sample(poses: poses, present: a.present)
    }

    /// Shortest way round the circle.
    ///
    /// A piece spinning past 2π wraps from ~6.28 to ~0. Interpolating those
    /// linearly spins it almost a full turn backwards in one frame — a visible
    /// glitch, and only ever on the watching phone.
    static func interpolate(angle from: Double, to: Double, t: Double) -> Double {
        let turn = 2 * Double.pi
        var delta = (to - from).truncatingRemainder(dividingBy: turn)
        if delta > .pi { delta -= turn }
        if delta < -.pi { delta += turn }
        let result = (from + delta * t).truncatingRemainder(dividingBy: turn)
        return result < 0 ? result + turn : result
    }
}

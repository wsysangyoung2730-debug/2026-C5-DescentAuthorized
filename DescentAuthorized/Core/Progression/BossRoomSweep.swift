import Foundation
import simd

/// Authored in Blender meters/Z-up. The scene controller applies its imported room transform.
struct BossRoomSweepPose: Sendable {
    let position: SIMD3<Float>
    let orientation: simd_quatf
    let lensMillimeters: Float
    let shift: SIMD2<Float>
}

struct BossRoomSweepTrack: Sendable {
    let floor: Int
    let framesPerSecond: Double
    let duration: TimeInterval
    let sensorWidthMillimeters: Float
    let sensorHeightMillimeters: Float
    let sensorFit: String
    let authoredAspectRatio: Float
    let nearClip: Float
    let farClip: Float
    let samples: [BossRoomSweepPose]

    /// Sampling the verified baked path preserves Blender's easing and level horizon.
    /// Interpolation between adjacent samples also supports displays above 30 Hz.
    func pose(at seconds: TimeInterval) -> BossRoomSweepPose {
        let time = seconds.isNaN ? 0 : min(duration, max(0, seconds))
        let fractionalIndex = min(Double(samples.count - 1), time * framesPerSecond)
        let lower = Int(fractionalIndex)
        let upper = min(lower + 1, samples.count - 1)
        let fraction = Float(fractionalIndex - Double(lower))
        let start = samples[lower]
        let end = samples[upper]
        return BossRoomSweepPose(
            position: simd_mix(start.position, end.position, SIMD3(repeating: fraction)),
            orientation: simd_normalize(simd_slerp(start.orientation, end.orientation, fraction)),
            lensMillimeters: start.lensMillimeters + (end.lensMillimeters - start.lensMillimeters) * fraction,
            shift: simd_mix(start.shift, end.shift, SIMD2(repeating: fraction))
        )
    }

    /// RealityKit's camera uses a vertical field of view. Blender's authored landscape
    /// cameras fit the horizontal 36 mm sensor, so its vertical extent follows aspect.
    func verticalFieldOfView(lensMillimeters: Float, aspectRatio: Float) -> Float {
        let aspect = aspectRatio.isFinite && aspectRatio > 0 ? aspectRatio : authoredAspectRatio
        let sensorHeight: Float = sensorFit == "VERTICAL"
            ? sensorHeightMillimeters
            : sensorWidthMillimeters / aspect
        let lens = lensMillimeters.isFinite && lensMillimeters > 0 ? lensMillimeters : samples[0].lensMillimeters
        return 2 * atan(sensorHeight / (2 * lens)) * 180 / .pi
    }
}

enum BossRoomSweepCatalog {
    private struct Document: Decodable {
        let version: Int
        let fps: Double
        let duration: Double
        let rooms: [Room]
    }

    private struct Room: Decodable {
        let floor: Int
        let sensorWidth: Float
        let sensorHeight: Float
        let sensorFit: String
        let aspectRatio: Float
        let nearClip: Float
        let farClip: Float
        // Position XYZ, quaternion WXYZ, lens mm, horizontal shift, vertical shift.
        let samples: [[Float]]
    }

    enum CatalogError: Error {
        case unsupportedVersion
        case invalidTimeline
        case invalidRoom(Int)
    }

    private static let tracks: [Int: BossRoomSweepTrack] = {
        #if SWIFT_PACKAGE
        let bundle = Bundle.module
        #else
        let bundle = Bundle.main
        #endif
        guard let url = bundle.url(forResource: "BossRoomSweepTracks", withExtension: "json"),
              let data = try? Data(contentsOf: url),
              let tracks = try? decode(data) else { return [:] }
        return tracks
    }()

    /// Missing assets safely bypass the cosmetic sweep; they never block combat.
    static func track(for floor: Int) -> BossRoomSweepTrack? {
        tracks[floor]
    }

    static func decode(_ data: Data) throws -> [Int: BossRoomSweepTrack] {
        let document = try JSONDecoder().decode(Document.self, from: data)
        guard document.version == 1 else { throw CatalogError.unsupportedVersion }
        guard document.fps.isFinite, document.fps > 0, document.fps <= 120,
              document.duration.isFinite, document.duration > 0, document.duration <= 60 else {
            throw CatalogError.invalidTimeline
        }
        let sampleIntervals = document.duration * document.fps
        guard abs(sampleIntervals.rounded() - sampleIntervals) < 0.000_001 else {
            throw CatalogError.invalidTimeline
        }
        let sampleCount = Int(sampleIntervals.rounded()) + 1
        var result: [Int: BossRoomSweepTrack] = [:]
        for room in document.rooms {
            guard (1...9).contains(room.floor), result[room.floor] == nil,
                  room.sensorWidth.isFinite, room.sensorWidth > 0,
                  room.sensorHeight.isFinite, room.sensorHeight > 0,
                  ["AUTO", "HORIZONTAL", "VERTICAL"].contains(room.sensorFit),
                  room.aspectRatio.isFinite, room.aspectRatio > 0,
                  room.nearClip.isFinite, room.nearClip > 0,
                  room.farClip.isFinite, room.farClip > room.nearClip,
                  room.samples.count == sampleCount else {
                throw CatalogError.invalidRoom(room.floor)
            }
            let samples = try room.samples.map { row -> BossRoomSweepPose in
                guard row.count == 10, row.allSatisfy(\.isFinite), row[7] > 0 else {
                    throw CatalogError.invalidRoom(room.floor)
                }
                let quaternion = simd_quatf(ix: row[4], iy: row[5], iz: row[6], r: row[3])
                guard abs(simd_length(quaternion.vector) - 1) < 0.01 else {
                    throw CatalogError.invalidRoom(room.floor)
                }
                return BossRoomSweepPose(
                    position: SIMD3(row[0], row[1], row[2]),
                    orientation: simd_normalize(quaternion),
                    lensMillimeters: row[7],
                    shift: SIMD2(row[8], row[9])
                )
            }
            result[room.floor] = BossRoomSweepTrack(
                floor: room.floor,
                framesPerSecond: document.fps,
                duration: document.duration,
                sensorWidthMillimeters: room.sensorWidth,
                sensorHeightMillimeters: room.sensorHeight,
                sensorFit: room.sensorFit,
                authoredAspectRatio: room.aspectRatio,
                nearClip: room.nearClip,
                farClip: room.farClip,
                samples: samples
            )
        }
        return result
    }
}

/// Feed elapsed time only after a room is ready; overlays/backgrounding suspend it.
/// A delayed render frame cannot skip a room, and completion is emitted exactly once.
struct BossRoomSweepPlayback: Equatable, Sendable {
    let duration: TimeInterval
    private(set) var elapsedTime: TimeInterval = 0
    private(set) var isFinished = false

    init(duration: TimeInterval = 12) {
        self.duration = duration.isFinite ? max(0, duration) : 0
    }

    @discardableResult
    mutating func advance(elapsed: TimeInterval, isSuspended: Bool) -> Bool {
        guard !isFinished, !isSuspended, elapsed.isFinite, elapsed > 0 else { return false }
        elapsedTime = min(duration, elapsedTime + min(elapsed, 0.1))
        guard duration - elapsedTime <= 0.000_000_1 else { return false }
        elapsedTime = duration
        isFinished = true
        return true
    }

    /// Also used for Reduce Motion, which immediately restores the battle camera.
    @discardableResult
    mutating func skip() -> Bool {
        guard !isFinished else { return false }
        elapsedTime = duration
        isFinished = true
        return true
    }
}

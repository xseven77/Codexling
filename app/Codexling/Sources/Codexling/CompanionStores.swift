import AppKit
import Foundation
import Observation

@MainActor
@Observable
final class PetFrameStore {
    private let player = PetAnimationPlayer()
    private(set) var currentFrame: NSImage?
    private(set) var selectedPet: CodexPet?
    private(set) var activityState: CodexActivityState = .unavailable
    var onFrameChanged: (() -> Void)?

    init() {
        player.onFrame = { [weak self] image in
            guard let self else { return }
            currentFrame = image
            onFrameChanged?()
        }
    }

    func update(pet: CodexPet?, activityState: CodexActivityState) {
        selectedPet = pet
        self.activityState = activityState
        player.setPet(pet)
        guard !player.isPlayingOneShot else { return }
        player.setState(activityState.petAnimationState)
    }

    var canPlayIdleInteraction: Bool {
        switch activityState {
        case .idle, .unavailable:
            true
        default:
            false
        }
    }

    func playRandomIdleAction() {
        guard canPlayIdleInteraction else { return }
        guard let action = PetAnimationState.idleInteractionCandidates.randomElement() else { return }
        player.playOneShot(action) { [weak self] in
            guard let self else { return }
            player.setState(activityState.petAnimationState)
        }
    }

    func stop() {
        player.stop()
    }
}

@MainActor
@Observable
final class CompanionStatsStore {
    private struct Record: Codable {
        var localDay: String
        var accumulatedSeconds: TimeInterval
        var activeSince: Date?
        var lastPersistedAt: Date
    }

    private let fileURL: URL
    private let calendar: Calendar
    private var record: Record
    private var timer: Timer?

    private(set) var todaySeconds: TimeInterval = 0

    var todayMinutes: Int {
        Int(todaySeconds / 60)
    }

    init(fileURL: URL? = nil, now: Date = Date(), calendar: Calendar = .current) {
        self.calendar = calendar
        self.fileURL = fileURL ?? FileManager.default.urls(
            for: .applicationSupportDirectory,
            in: .userDomainMask
        )[0]
            .appendingPathComponent("Codexling", isDirectory: true)
            .appendingPathComponent("companion_stats.json")

        let day = Self.dayKey(for: now, calendar: calendar)
        if let data = try? Data(contentsOf: self.fileURL),
           let decoded = try? JSONDecoder.codexling.decode(Record.self, from: data),
           decoded.localDay == day {
            record = decoded
        } else {
            record = Record(
                localDay: day,
                accumulatedSeconds: 0,
                activeSince: nil,
                lastPersistedAt: now
            )
        }
        todaySeconds = record.accumulatedSeconds
    }

    func start() {
        stop(settle: false)
        timer = Timer.scheduledTimer(withTimeInterval: 30, repeats: true) { [weak self] _ in
            Task { @MainActor [weak self] in
                self?.tick()
            }
        }
    }

    func setActivityState(_ state: CodexActivityState, now: Date = Date()) {
        settle(now: now)
        if state.isCompanionActive {
            record.activeSince = now
        } else {
            record.activeSince = nil
        }
        persist(now: now)
    }

    func tick(now: Date = Date()) {
        settle(now: now)
        persist(now: now)
    }

    func stop(now: Date = Date(), settle: Bool = true) {
        timer?.invalidate()
        timer = nil
        if settle {
            self.settle(now: now)
            record.activeSince = nil
            persist(now: now)
        }
    }

    private func settle(now: Date) {
        let day = Self.dayKey(for: now, calendar: calendar)
        if record.localDay != day {
            record = Record(
                localDay: day,
                accumulatedSeconds: 0,
                activeSince: record.activeSince == nil ? nil : now,
                lastPersistedAt: now
            )
        } else if let activeSince = record.activeSince {
            // A regular heartbeat is 30 seconds. Cap a single interval so a
            // sleeping Mac cannot inflate the daily companion total.
            let increment = min(max(now.timeIntervalSince(activeSince), 0), 90)
            record.accumulatedSeconds += increment
            record.activeSince = now
        }
        todaySeconds = record.accumulatedSeconds
    }

    private func persist(now: Date) {
        record.lastPersistedAt = now
        do {
            try FileManager.default.createDirectory(
                at: fileURL.deletingLastPathComponent(),
                withIntermediateDirectories: true
            )
            let data = try JSONEncoder.codexling.encode(record)
            try data.write(to: fileURL, options: .atomic)
        } catch {
            // Companion stats are optional and must not affect core usage UI.
        }
    }

    private static func dayKey(for date: Date, calendar: Calendar) -> String {
        let components = calendar.dateComponents([.year, .month, .day], from: date)
        return String(format: "%04d-%02d-%02d", components.year ?? 0, components.month ?? 0, components.day ?? 0)
    }
}

private extension CodexActivityState {
    var isCompanionActive: Bool {
        switch self {
        case .thinking, .executing, .reviewing, .waitingForUser:
            true
        default:
            false
        }
    }
}

private extension JSONEncoder {
    static var codexling: JSONEncoder {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        return encoder
    }
}

private extension JSONDecoder {
    static var codexling: JSONDecoder {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return decoder
    }
}

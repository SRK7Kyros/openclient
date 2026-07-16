import Combine
import Foundation

#if canImport(WidgetKit)
import WidgetKit
#endif

protocol WidgetSnapshotWriting {
    func update(_ publication: WidgetServerPublication)
    func removeSession(serverID: String, sessionID: String)
}

protocol WidgetTimelineReloading {
    func reloadContentTimelines()
    func reloadShortcutTimelines()
    func reloadAllTimelines()
}

extension OpenCodeWidgetStore: WidgetSnapshotWriting {
    func update(_ publication: WidgetServerPublication) {
        updatingServer(
            publication.server,
            projects: publication.projects,
            sessions: publication.sessions,
            replacingSessionIDs: publication.replacingSessionIDs,
            commands: publication.commands,
            replacingCommandProjectIDs: publication.replacingCommandProjectIDs,
            models: publication.models
        )
    }
}

struct SystemWidgetTimelineReloader: WidgetTimelineReloading {
    func reloadContentTimelines() {
        #if canImport(WidgetKit)
        WidgetCenter.shared.reloadTimelines(ofKind: OpenCodeWidgetKind.recentSessions)
        WidgetCenter.shared.reloadTimelines(ofKind: OpenCodeWidgetKind.pinnedSessions)
        #endif
    }

    func reloadShortcutTimelines() {
        #if canImport(WidgetKit)
        WidgetCenter.shared.reloadTimelines(ofKind: OpenCodeWidgetKind.actionShortcut)
        WidgetCenter.shared.reloadTimelines(ofKind: OpenCodeWidgetKind.newSessionShortcut)
        #endif
    }

    func reloadAllTimelines() {
        reloadContentTimelines()
        reloadShortcutTimelines()
    }
}

@MainActor
final class WidgetSnapshotPublisher {
    private let inputProvider: (Bool) -> WidgetSnapshotInput?
    private let writer: WidgetSnapshotWriterQueue
    private let timelineReloader: WidgetTimelineReloading
    private var publishTask: Task<Void, Never>?
    private var pendingIncludesModelOptions = false
    private var observations: Set<AnyCancellable> = []

    init(
        inputProvider: @escaping (Bool) -> WidgetSnapshotInput?,
        writer: WidgetSnapshotWriting = OpenCodeWidgetStore(),
        timelineReloader: WidgetTimelineReloading = SystemWidgetTimelineReloader()
    ) {
        self.inputProvider = inputProvider
        self.writer = WidgetSnapshotWriterQueue(writer: writer)
        self.timelineReloader = timelineReloader
    }

    func observe(
        contentChanges: [AnyPublisher<Void, Never>],
        modelChanges: AnyPublisher<Void, Never>
    ) {
        Publishers.MergeMany(contentChanges)
            .sink { [weak self] _ in self?.invalidate() }
            .store(in: &observations)
        modelChanges
            .sink { [weak self] _ in self?.invalidate(includeModelOptions: true) }
            .store(in: &observations)
    }

    func invalidate(includeModelOptions: Bool = false) {
        pendingIncludesModelOptions = pendingIncludesModelOptions || includeModelOptions
        publishTask?.cancel()
        publishTask = Task { @MainActor [weak self] in
            try? await Task.sleep(for: .milliseconds(350))
            guard let self, !Task.isCancelled else { return }
            let includeModelOptions = pendingIncludesModelOptions
            pendingIncludesModelOptions = false
            await publishNow(includeModelOptions: includeModelOptions)
            publishTask = nil
        }
    }

    func publishNow(includeModelOptions: Bool = false) async {
        guard let input = inputProvider(includeModelOptions) else { return }
        guard let publication = WidgetSnapshotBuilder.build(
            from: input,
            includeModelOptions: includeModelOptions
        ) else { return }
        await writer.update(publication)
        guard !Task.isCancelled else { return }
        timelineReloader.reloadContentTimelines()
        if includeModelOptions {
            timelineReloader.reloadShortcutTimelines()
        }
    }

    func removeSession(serverID: String, sessionID: String) {
        Task { @MainActor [weak self] in
            guard let self else { return }
            await writer.removeSession(serverID: serverID, sessionID: sessionID)
            guard !Task.isCancelled else { return }
            timelineReloader.reloadAllTimelines()
        }
    }

    func stop() {
        publishTask?.cancel()
        publishTask = nil
        observations.removeAll()
    }
}

private final class WidgetSnapshotWriterQueue: @unchecked Sendable {
    private let writer: WidgetSnapshotWriting
    private let queue = DispatchQueue(label: "com.ntoporcov.openclient.widget-snapshots", qos: .utility)

    init(writer: WidgetSnapshotWriting) {
        self.writer = writer
    }

    func update(_ publication: WidgetServerPublication) async {
        await withCheckedContinuation { continuation in
            queue.async { [self] in
                writer.update(publication)
                continuation.resume()
            }
        }
    }

    func removeSession(serverID: String, sessionID: String) async {
        await withCheckedContinuation { continuation in
            queue.async { [self] in
                writer.removeSession(serverID: serverID, sessionID: sessionID)
                continuation.resume()
            }
        }
    }
}

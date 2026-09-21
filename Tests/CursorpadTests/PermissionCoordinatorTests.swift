import AppKit
import Foundation
import Testing

@testable import Cursorpad

// MARK: - PHASE-06 focused checks for CON-PERMISSION-FILESYSTEM
//
// The coordinator is exercised through real seams: the real `Seams.live` defaults (explicit
// NSOpenPanel construction, real security-scoped bookmark creation/resolution) with only the
// presentation step and the scope open/close calls replaced by deterministic recorders, so no UI
// is shown and every scope start/stop is observable.

@Suite("PermissionCoordinatorTests")
@MainActor
struct PermissionCoordinatorTests {
    // MARK: - Deterministic seams

    /// Records what the coordinator asked the panel to do and answers with a fixed outcome.
    @MainActor
    private final class PanelResponder {
        var response: NSApplication.ModalResponse = .OK
        var urls: [URL] = []
        private(set) var presentCount = 0
        private(set) var lastPanel: NSOpenPanel?
        private(set) var lastPurpose: ExternalLocationPurpose?

        func seam() -> (@MainActor (NSOpenPanel) -> PermissionCoordinator.PanelOutcome) {
            { [self] panel in
                presentCount += 1
                lastPanel = panel
                return PermissionCoordinator.PanelOutcome(response: response, urls: urls)
            }
        }
    }

    /// Records every security scope open/close; `startResults` scripts denials.
    @MainActor
    private final class ScopeRecorder {
        var startResults: [Bool] = []
        private(set) var started: [URL] = []
        private(set) var stopped: [URL] = []

        func startSeam() -> (@MainActor (URL) -> Bool) {
            { [self] url in
                started.append(url)
                if startResults.isEmpty { return true }
                return startResults.removeFirst()
            }
        }

        func stopSeam() -> (@MainActor (URL) -> Void) {
            { [self] url in self.stopped.append(url) }
        }
    }

    /// Records every real security-scoped bookmark creation, so a staleness refresh is observable.
    @MainActor
    private final class BookmarkRecorder {
        private(set) var urls: [URL] = []

        func seam() -> (@MainActor (URL) throws -> Data) {
            { [self] url in
                urls.append(url)
                return try PermissionCoordinator.Seams.live.makeBookmark(url)
            }
        }
    }

    /// Reuses one explicitly configured `NSOpenPanel` per purpose across the focused suite.
    ///
    /// Every simulated selection used to build a brand-new panel. Panel construction is AppKit
    /// work on the main actor, and this suite runs in parallel with the bounded-termination checks
    /// of `LifecycleCoordinatorTests`, so that construction was pure main-actor contention for
    /// tests that never look at the panel. The production panel factory itself is still exercised,
    /// unchanged and with fresh panels, by `explicitOpenPanelConfiguration`.
    @MainActor
    private final class PanelCache {
        private var panels: [Bool: NSOpenPanel] = [:]

        func seam() -> (@MainActor (ExternalLocationPurpose) -> NSOpenPanel) {
            { [self] purpose in
                if let cached = panels[purpose.isDirectory] {
                    return cached
                }
                let panel = PermissionCoordinator.Seams.live.makePanel(purpose)
                panels[purpose.isDirectory] = panel
                return panel
            }
        }
    }

    private static let panelCache = PanelCache()

    private func makeTemporaryLocation(_ label: String) throws -> URL {
        try TestEnvironment.makeTempDirectory(label)
    }

    private func makeSeams(
        responder: PanelResponder,
        scope: ScopeRecorder,
        makeBookmark: (@MainActor (URL) throws -> Data)? = nil,
        resolveBookmark: (@MainActor (Data) throws -> PermissionCoordinator.BookmarkResolution)? = nil
    ) -> PermissionCoordinator.Seams {
        var seams = PermissionCoordinator.Seams.live
        seams.makePanel = Self.panelCache.seam()
        seams.present = responder.seam()
        seams.startScope = scope.startSeam()
        seams.stopScope = scope.stopSeam()
        if let makeBookmark { seams.makeBookmark = makeBookmark }
        if let resolveBookmark { seams.resolveBookmark = resolveBookmark }
        return seams
    }

    @MainActor
    private final class Harness {
        let responder = PanelResponder()
        let scope = ScopeRecorder()
        let coordinator: PermissionCoordinator

        init(
            makeBookmark: (@MainActor (URL) throws -> Data)? = nil,
            resolveBookmark: (@MainActor (Data) throws -> PermissionCoordinator.BookmarkResolution)? = nil
        ) {
            var seams = PermissionCoordinator.Seams.live
            seams.makePanel = PermissionCoordinatorTests.panelCache.seam()
            seams.present = responder.seam()
            seams.startScope = scope.startSeam()
            seams.stopScope = scope.stopSeam()
            if let makeBookmark { seams.makeBookmark = makeBookmark }
            if let resolveBookmark { seams.resolveBookmark = resolveBookmark }
            coordinator = PermissionCoordinator(seams: seams)
        }
    }

    private func makeHarness(
        makeBookmark: (@MainActor (URL) throws -> Data)? = nil,
        resolveBookmark: (@MainActor (Data) throws -> PermissionCoordinator.BookmarkResolution)? = nil
    ) -> Harness {
        Harness(makeBookmark: makeBookmark, resolveBookmark: resolveBookmark)
    }

    private func panel(for purpose: ExternalLocationPurpose) -> NSOpenPanel {
        PermissionCoordinator.Seams.live.makePanel(purpose)
    }

    // MARK: - Explicit NSOpenPanel

    @Test("the production seam builds a real, explicitly configured NSOpenPanel")
    func explicitOpenPanelConfiguration() throws {
        let folder = panel(for: .folder)
        #expect(String(describing: type(of: folder)) == "NSOpenPanel", "the live panel must be an AppKit NSOpenPanel")
        #expect(folder.canChooseDirectories)
        #expect(!folder.canChooseFiles)
        #expect(!folder.allowsMultipleSelection, "one explicit location per selection")
        #expect(folder.resolvesAliases)
        #expect(!folder.canCreateDirectories, "the coordinator never creates external directories")
        #expect(!folder.showsHiddenFiles)
        #expect(folder.title == "CursorPad")
        #expect(folder.message == ExternalLocationCopy.folderMessage)
        #expect(folder.prompt == ExternalLocationCopy.prompt)
        #expect(folder.directoryURL == nil)

        let file = panel(for: .file)
        #expect(file.canChooseFiles)
        #expect(!file.canChooseDirectories)
        #expect(!file.allowsMultipleSelection)
        #expect(file.message == ExternalLocationCopy.fileMessage)
        #expect(file.prompt == ExternalLocationCopy.prompt)
    }

    @Test("the production presenter runs the panel as an explicit modal, never implicitly")
    func productionPresenterIsModal() throws {
        let source = try readPackageFile("Sources/Cursorpad/Platform/PermissionCoordinator.swift")
        #expect(source.contains("runModal()"))
        #expect(source.contains("NSOpenPanel"))
        #expect(!source.contains("Task.detached"))
        #expect(!source.contains("@unchecked Sendable"))
        #expect(source.contains("@MainActor"))
    }

    // MARK: - Grant lifecycle

    @Test("a successful selection stores a resolvable security-scoped bookmark and opens exactly one scope")
    func successfulSelectionOpensOneScope() async throws {
        let harness = makeHarness()
        let location = try makeTemporaryLocation("permission-grant")
        harness.responder.urls = [location]

        let state = harness.coordinator.requestAccess(.folder)
        #expect(state == .succeeded)
        #expect(harness.responder.presentCount == 1)

        let grant = try #require(harness.coordinator.grant)
        #expect(grant.url.standardizedFileURL == location.standardizedFileURL)
        #expect(grant.isDirectory)
        #expect(!grant.bookmark.isEmpty)

        // The stored bookmark must resolve back to the selected location with the real API.
        var isStale = false
        let resolved = try URL(
            resolvingBookmarkData: grant.bookmark,
            options: [.withSecurityScope],
            relativeTo: nil,
            bookmarkDataIsStale: &isStale
        )
        #expect(resolved.standardizedFileURL == location.standardizedFileURL)
        #expect(!isStale)

        #expect(harness.scope.started.count == 1)
        #expect(harness.coordinator.startedScopeCount == 1)
        #expect(harness.coordinator.activeScopeCount == 1)
        #expect(harness.coordinator.selectionRequestCount == 1)
    }

    @Test("cancel keeps the last valid grant, opens nothing and allows another explicit selection")
    func cancelPreservesLastValidGrant() async throws {
        let harness = makeHarness()
        let first = try makeTemporaryLocation("permission-first")
        let second = try makeTemporaryLocation("permission-second")

        harness.responder.urls = [first]
        #expect(harness.coordinator.requestAccess(.folder) == .succeeded)
        let firstGrant = try #require(harness.coordinator.grant)

        harness.responder.response = .cancel
        harness.responder.urls = [second]
        #expect(harness.coordinator.requestAccess(.folder) == .cancelled)
        #expect(harness.coordinator.grant == firstGrant, "the last valid grant must survive a cancel")
        #expect(harness.coordinator.activeScopeCount == 1)
        #expect(harness.scope.started.count == 1, "a cancelled selection opens no scope")
        #expect(harness.coordinator.denialMessage == nil)
        #expect(harness.coordinator.cancelledMessage != nil)

        // Recovery: the user can simply choose again.
        harness.responder.response = .OK
        #expect(harness.coordinator.requestAccess(.folder) == .succeeded)
        #expect(harness.coordinator.grant?.url.standardizedFileURL == second.standardizedFileURL)
        #expect(harness.coordinator.selectionRequestCount == 3)
    }

    @Test("a denied scope keeps the last valid state and reports the documented denial")
    func deniedScopePreservesLastValidState() async throws {
        let harness = makeHarness()
        let first = try makeTemporaryLocation("permission-denied-first")
        let second = try makeTemporaryLocation("permission-denied-second")

        harness.responder.urls = [first]
        #expect(harness.coordinator.requestAccess(.folder) == .succeeded)
        let firstGrant = try #require(harness.coordinator.grant)

        harness.scope.startResults = [false]
        harness.responder.urls = [second]
        let state = harness.coordinator.requestAccess(.folder)

        guard case .failed(let description) = state else {
            Issue.record("expected the denied path to report failed, got \(state)")
            return
        }
        #expect(description.contains("denied"))
        #expect(harness.coordinator.grant == firstGrant, "denial must leave the existing state unchanged")
        #expect(harness.coordinator.activeScopeCount == 1)
        #expect(harness.coordinator.denialMessage?.contains("choose") == true, "the denial path must invite another explicit selection")

        // Recovery: another explicit selection succeeds and releases the previous scope.
        harness.responder.urls = [second]
        #expect(harness.coordinator.requestAccess(.folder) == .succeeded)
        #expect(harness.coordinator.grant?.url.standardizedFileURL == second.standardizedFileURL)
        #expect(harness.coordinator.activeScopeCount == 1)
        #expect(harness.scope.stopped.count == 1, "replacing the grant releases the previous scope")
    }

    @Test("a bookmark failure preserves the last valid grant and exposes an explicit retry")
    func bookmarkFailurePreservesLastValidGrant() async throws {
        let harness = makeHarness()
        let valid = try makeTemporaryLocation("permission-valid")
        harness.responder.urls = [valid]
        #expect(harness.coordinator.requestAccess(.folder) == .succeeded)
        let validGrant = try #require(harness.coordinator.grant)

        // A real failure: the selected path does not exist any more.
        let vanished = try makeTemporaryLocation("permission-vanished")
        try FileManager.default.removeItem(at: vanished)
        harness.responder.urls = [vanished]

        let state = harness.coordinator.requestAccess(.folder)
        guard case .failed(let description) = state else {
            Issue.record("expected a failed state for an unusable selection, got \(state)")
            return
        }
        #expect(!description.isEmpty)
        #expect(harness.coordinator.grant == validGrant, "a failed selection must not replace the last valid state")
        #expect(harness.coordinator.activeScopeCount == 1)
        #expect(harness.coordinator.lastFailureDescription != nil)

        // Explicit retry after the failure.
        let replacement = try makeTemporaryLocation("permission-replacement")
        harness.responder.urls = [replacement]
        #expect(harness.coordinator.requestAccess(.folder) == .succeeded)
        #expect(harness.coordinator.grant?.url.standardizedFileURL == replacement.standardizedFileURL)
        #expect(harness.coordinator.activeScopeCount == 1)
        #expect(harness.coordinator.lastFailureDescription == nil)
    }

    @Test("a selection that reports no URLs is a failure, not a silent success")
    func emptySelectionIsAFailure() async throws {
        let harness = makeHarness()
        harness.responder.urls = []
        let state = harness.coordinator.requestAccess(.file)
        guard case .failed = state else {
            Issue.record("expected an empty selection to fail honestly, got \(state)")
            return
        }
        #expect(harness.coordinator.grant == nil)
        #expect(harness.coordinator.activeScopeCount == 0)
    }

    // MARK: - Scope release

    @Test("every started scope is released exactly once, including repeated releases")
    func releaseAllScopesIsBalancedAndIdempotent() async throws {
        let harness = makeHarness()
        let first = try makeTemporaryLocation("permission-release-1")
        let second = try makeTemporaryLocation("permission-release-2")

        harness.responder.urls = [first]
        #expect(harness.coordinator.requestAccess(.folder) == .succeeded)
        harness.responder.urls = [second]
        #expect(harness.coordinator.requestAccess(.folder) == .succeeded)

        #expect(harness.coordinator.startedScopeCount == 2)
        #expect(harness.coordinator.releasedScopeCount == 1)
        #expect(harness.coordinator.activeScopeCount == 1)

        harness.coordinator.releaseAllScopes()
        #expect(harness.coordinator.releasedScopeCount == 2)
        #expect(harness.coordinator.activeScopeCount == 0)
        #expect(harness.scope.stopped.count == 2)
        #expect(harness.scope.stopped.map(\.standardizedFileURL) == [
            first.standardizedFileURL,
            second.standardizedFileURL
        ])

        // Releasing again must not double-stop or claim a negative scope count.
        harness.coordinator.releaseAllScopes()
        #expect(harness.coordinator.releasedScopeCount == 2)
        #expect(harness.coordinator.activeScopeCount == 0)
        #expect(harness.scope.stopped.count == 2)
        #expect(harness.coordinator.state == .idle, "an explicit release returns the coordinator to idle")
    }

    // MARK: - Restore path

    @Test("a stored grant restores through bookmark resolution and opens exactly one scope")
    func restoreOpensOneScope() async throws {
        let first = try makeTemporaryLocation("permission-restore")
        let responder = PanelResponder()
        responder.urls = [first]
        let scope = ScopeRecorder()
        let seams = makeSeams(responder: responder, scope: scope)

        let original = PermissionCoordinator(seams: seams)
        #expect(original.requestAccess(.folder) == .succeeded)
        let stored = try #require(original.grant)
        original.releaseAllScopes()

        // A fresh coordinator (the relaunch path) restores the stored grant with the real resolver.
        let freshScope = ScopeRecorder()
        let relaunched = PermissionCoordinator(seams: makeSeams(responder: PanelResponder(), scope: freshScope))
        #expect(relaunched.restore(stored) == .succeeded)
        #expect(relaunched.grant?.url.standardizedFileURL == first.standardizedFileURL)
        #expect(relaunched.startedScopeCount == 1)
        #expect(relaunched.activeScopeCount == 1)
        #expect(freshScope.started.map(\.standardizedFileURL) == [first.standardizedFileURL])
        #expect(relaunched.didRefreshStaleBookmark == false)
    }

    @Test("a stale bookmark is refreshed for the same location and reported")
    func staleBookmarkIsRefreshed() async throws {
        let location = try makeTemporaryLocation("permission-stale")
        let bookmarkCalls = BookmarkRecorder()
        let staleResolver: @MainActor (Data) throws -> PermissionCoordinator.BookmarkResolution = { data in
            var isStale = false
            let url = try URL(
                resolvingBookmarkData: data,
                options: [.withSecurityScope],
                relativeTo: nil,
                bookmarkDataIsStale: &isStale
            )
            return PermissionCoordinator.BookmarkResolution(url: url, isStale: true)
        }

        let responder = PanelResponder()
        responder.urls = [location]
        let coordinator = PermissionCoordinator(seams: makeSeams(
            responder: responder,
            scope: ScopeRecorder(),
            makeBookmark: bookmarkCalls.seam(),
            resolveBookmark: staleResolver
        ))
        #expect(coordinator.requestAccess(.folder) == .succeeded)
        let stored = try #require(coordinator.grant)
        coordinator.releaseAllScopes()
        #expect(bookmarkCalls.urls.count == 1, "the original grant created one bookmark")

        let freshScope = ScopeRecorder()
        let relaunched = PermissionCoordinator(seams: makeSeams(
            responder: PanelResponder(),
            scope: freshScope,
            makeBookmark: bookmarkCalls.seam(),
            resolveBookmark: staleResolver
        ))
        #expect(relaunched.restore(stored) == .succeeded)
        #expect(relaunched.didRefreshStaleBookmark, "a stale bookmark must be replaced through a fresh creation")
        #expect(bookmarkCalls.urls.count == 2, "the stale refresh must create exactly one replacement bookmark")
        #expect(bookmarkCalls.urls.last?.standardizedFileURL == location.standardizedFileURL)
        #expect(relaunched.grant?.url.standardizedFileURL == location.standardizedFileURL)

        // The replacement bookmark must be a real, resolvable security-scoped bookmark.
        let refreshed = try #require(relaunched.grant?.bookmark)
        var refreshedIsStale = false
        let resolved = try URL(
            resolvingBookmarkData: refreshed,
            options: [.withSecurityScope],
            relativeTo: nil,
            bookmarkDataIsStale: &refreshedIsStale
        )
        #expect(resolved.standardizedFileURL == location.standardizedFileURL)
        #expect(relaunched.activeScopeCount == 1)
    }

    @Test("a failed restore preserves the last valid grant instead of dropping it")
    func failedRestorePreservesLastValidGrant() async throws {
        let harness = makeHarness()
        let valid = try makeTemporaryLocation("permission-restore-valid")
        harness.responder.urls = [valid]
        #expect(harness.coordinator.requestAccess(.folder) == .succeeded)
        let validGrant = try #require(harness.coordinator.grant)

        let broken = ExternalLocationGrant(
            id: "stored-location",
            url: valid,
            displayName: "Stored",
            isDirectory: true,
            bookmark: Data("not a bookmark".utf8)
        )
        let state = harness.coordinator.restore(broken)
        guard case .failed = state else {
            Issue.record("expected a failed restore for invalid bookmark data, got \(state)")
            return
        }
        #expect(harness.coordinator.grant == validGrant)
        #expect(harness.coordinator.activeScopeCount == 1)
        #expect(harness.coordinator.lastFailureDescription != nil)
    }

    @Test("authorization is rechecked only after an explicit user action")
    func recheckOnlyAfterExplicitUserAction() async throws {
        let harness = makeHarness()
        harness.responder.urls = [try makeTemporaryLocation("permission-explicit")]
        _ = harness.coordinator.requestAccess(.folder)
        let requestsAfterFirstCall = harness.coordinator.selectionRequestCount
        let presentsAfterFirstCall = harness.responder.presentCount

        // Nothing may retry by itself: waiting changes neither the panel count nor the request count.
        try await Task.sleep(for: .milliseconds(300))
        #expect(harness.coordinator.selectionRequestCount == requestsAfterFirstCall)
        #expect(harness.responder.presentCount == presentsAfterFirstCall)

        // An explicit retry is the only thing that re-checks authorization.
        harness.coordinator.retryLastPurpose()
        #expect(harness.coordinator.selectionRequestCount == requestsAfterFirstCall + 1)
    }

    // MARK: - Composition root integration

    @Test("AppState mirrors the grant and releases every scope on termination")
    func appStateIntegrationReleasesScopesOnTermination() async throws {
        let root = try TestEnvironment.makeTempDirectory("permission-appstate")
        let state = AppState(services: TestEnvironment.makeServices(root: root))

        let responder = PanelResponder()
        let location = try makeTemporaryLocation("permission-appstate-location")
        responder.urls = [location]
        let scope = ScopeRecorder()
        state.permissions.seams = makeSeams(responder: responder, scope: scope)

        state.requestExternalFolderAccess()
        #expect(state.permissions.state == .succeeded)
        #expect(state.externalLocationSummary?.contains(location.lastPathComponent) == true)
        #expect(state.permissions.activeScopeCount == 1)

        await state.flushForTermination()
        #expect(state.permissions.activeScopeCount == 0, "termination must release every access scope")
        #expect(scope.stopped.map(\.standardizedFileURL) == [location.standardizedFileURL])
    }

    @Test("AppState reports cancellation and denial honestly and keeps the previous grant")
    func appStateReportsDenialHonestly() async throws {
        let root = try TestEnvironment.makeTempDirectory("permission-appstate-denied")
        let state = AppState(services: TestEnvironment.makeServices(root: root))

        let responder = PanelResponder()
        let first = try makeTemporaryLocation("permission-appstate-first")
        responder.urls = [first]
        state.permissions.seams = makeSeams(responder: responder, scope: ScopeRecorder())

        state.requestExternalFolderAccess()
        let grant = try #require(state.permissions.grant)

        responder.response = .cancel
        state.requestExternalFileAccess()
        #expect(state.permissions.grant == grant)
        #expect(state.statusMessage?.contains("previous location is unchanged") == true)

        responder.response = .OK
        responder.urls = []
        state.requestExternalFileAccess()
        guard case .failed = state.permissions.state else {
            Issue.record("expected the empty selection to fail, got \(state.permissions.state)")
            return
        }
        #expect(state.permissions.grant == grant)
        #expect(state.externalLocationSummary?.contains(first.lastPathComponent) == true)
    }

    @Test("the coordinator stays on the main actor")
    func mainActorConfinement() {
        #expect(Thread.isMainThread, "the focused suite runs on the main actor")
        let coordinator = PermissionCoordinator()
        #expect(coordinator.activeScopeCount == 0)
        #expect(coordinator.state == .idle)
    }
}

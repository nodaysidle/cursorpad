import AppKit
import Foundation

// MARK: - CON-PERMISSION-FILESYSTEM
//
// Access to external locations is always an explicit, user-selected transaction: the coordinator
// presents an `NSOpenPanel`, turns the chosen URL into a security-scoped bookmark, opens exactly
// one access scope for it and releases every scope it ever opened. Denial, cancellation and errors
// leave the last valid selection in place and let the user choose again — authorization is never
// rechecked without a fresh explicit user action.
//
// The whole surface is `@MainActor`: `NSOpenPanel` and every AppKit touch live here.

/// Locked panel copy (CON-PERMISSION-FILESYSTEM interface surface).
enum ExternalLocationCopy {
    static let title = "CursorPad"
    static let prompt = "Grant Access"
    static let folderMessage = "Choose a folder CursorPad may read and write."
    static let fileMessage = "Choose a file CursorPad may read."
    static let deniedMessage = "Access was denied. The previous location is unchanged — choose the location again to retry."
    static let cancelledMessage = "Selection was cancelled. The previous location is unchanged."
    static let emptySelectionMessage = "No location was selected. The previous location is unchanged."
}

/// What the user is choosing. Only user-selected files and folders are ever requested.
enum ExternalLocationPurpose: Equatable, Sendable {
    case folder
    case file

    var message: String {
        switch self {
        case .folder: ExternalLocationCopy.folderMessage
        case .file: ExternalLocationCopy.fileMessage
        }
    }

    var isDirectory: Bool { self == .folder }
}

/// One user-selected external location: its identity, URL and security-scoped bookmark.
struct ExternalLocationGrant: Equatable, Sendable {
    let id: String
    let url: URL
    let displayName: String
    let isDirectory: Bool
    let bookmark: Data
}

/// Owns the filesystem permission surface: explicit selection, security-scoped bookmark lifecycle,
/// balanced scope release and the documented denied/failure/recovery paths.
@MainActor
final class PermissionCoordinator {
    /// Contract vocabulary: idle, active, succeeded, failed, cancelled.
    enum State: Equatable, Sendable {
        case idle
        case active
        case succeeded
        case failed(String)
        case cancelled
    }

    enum PermissionError: Error, Equatable, CustomStringConvertible {
        case bookmarkCreationFailed(String)
        case bookmarkResolutionFailed(String)
        case denied(String)
        case noSelection

        var description: String {
            switch self {
            case .bookmarkCreationFailed(let message):
                "the security-scoped bookmark could not be created — \(message)"
            case .bookmarkResolutionFailed(let message):
                "the stored bookmark could not be resolved — \(message)"
            case .denied(let message):
                "access was denied — \(message)"
            case .noSelection:
                "no location was selected — \(ExternalLocationCopy.emptySelectionMessage)"
            }
        }
    }

    /// Result of resolving a stored bookmark.
    struct BookmarkResolution: Sendable {
        let url: URL
        let isStale: Bool
    }

    /// Result of one explicit panel presentation.
    struct PanelOutcome: Sendable {
        let response: NSApplication.ModalResponse
        let urls: [URL]
    }

    /// The AppKit + Foundation boundary.
    ///
    /// `live` is the production implementation: an explicitly configured `NSOpenPanel`, the real
    /// security-scoped access calls and the real bookmark API. Focused tests replace only the
    /// presentation step and the scope calls so the state machine can be verified without UI.
    struct Seams {
        var makePanel: @MainActor (ExternalLocationPurpose) -> NSOpenPanel
        var present: @MainActor (NSOpenPanel) -> PanelOutcome
        var startScope: @MainActor (URL) -> Bool
        var stopScope: @MainActor (URL) -> Void
        var makeBookmark: @MainActor (URL) throws -> Data
        var resolveBookmark: @MainActor (Data) throws -> BookmarkResolution

        static var live: Seams {
            Seams(
                makePanel: { purpose in
                    let panel = NSOpenPanel()
                    panel.title = ExternalLocationCopy.title
                    panel.message = purpose.message
                    panel.prompt = ExternalLocationCopy.prompt
                    panel.canChooseDirectories = purpose.isDirectory
                    panel.canChooseFiles = !purpose.isDirectory
                    panel.allowsMultipleSelection = false
                    panel.resolvesAliases = true
                    panel.canCreateDirectories = false
                    panel.showsHiddenFiles = false
                    panel.treatsFilePackagesAsDirectories = false
                    panel.directoryURL = nil
                    return panel
                },
                present: { panel in
                    let response = panel.runModal()
                    return PanelOutcome(response: response, urls: panel.urls)
                },
                startScope: { url in url.startAccessingSecurityScopedResource() },
                stopScope: { url in url.stopAccessingSecurityScopedResource() },
                makeBookmark: { url in
                    do {
                        return try url.bookmarkData(
                            options: [.withSecurityScope],
                            includingResourceValuesForKeys: nil,
                            relativeTo: nil
                        )
                    } catch {
                        throw PermissionError.bookmarkCreationFailed(error.localizedDescription)
                    }
                },
                resolveBookmark: { data in
                    var isStale = false
                    do {
                        let url = try URL(
                            resolvingBookmarkData: data,
                            options: [.withSecurityScope],
                            relativeTo: nil,
                            bookmarkDataIsStale: &isStale
                        )
                        return BookmarkResolution(url: url, isStale: isStale)
                    } catch {
                        throw PermissionError.bookmarkResolutionFailed(error.localizedDescription)
                    }
                }
            )
        }
    }

    // MARK: State

    private(set) var state: State = .idle
    /// The last valid user selection. Preserved across denial, cancellation and failure.
    private(set) var grant: ExternalLocationGrant?
    /// Honest scope bookkeeping: every started scope must be released exactly once.
    private(set) var startedScopeCount = 0
    private(set) var releasedScopeCount = 0
    /// Counts explicit user actions only; nothing here retries on its own.
    private(set) var selectionRequestCount = 0
    private(set) var lastPurpose: ExternalLocationPurpose?
    private(set) var denialMessage: String?
    private(set) var cancelledMessage: String?
    private(set) var lastFailureDescription: String?
    private(set) var didRefreshStaleBookmark = false

    /// Test seam. Production always runs `Seams.live`.
    var seams: Seams

    private var openScopeURLs: [URL] = []

    init(seams: Seams = .live) {
        self.seams = seams
    }

    var activeScopeCount: Int { startedScopeCount - releasedScopeCount }

    // MARK: - Explicit user actions

    /// Presents the explicit panel and adopts the chosen location. User-initiated by definition.
    @discardableResult
    func requestAccess(_ purpose: ExternalLocationPurpose) -> State {
        state = .active
        selectionRequestCount += 1
        lastPurpose = purpose
        denialMessage = nil
        cancelledMessage = nil

        let panel = seams.makePanel(purpose)
        let outcome = seams.present(panel)

        guard outcome.response == .OK else {
            // Documented denied behavior: leave the existing state unchanged, allow another
            // explicit selection.
            state = .cancelled
            cancelledMessage = ExternalLocationCopy.cancelledMessage
            lastFailureDescription = nil
            return state
        }
        guard let selected = outcome.urls.first else {
            return fail(with: PermissionError.noSelection)
        }
        return adopt(url: selected, purpose: purpose)
    }

    /// Explicit recovery action: re-checks authorization for the same purpose, only because the
    /// user asked again (CON-PERMISSION-FILESYSTEM recovery).
    @discardableResult
    func retryLastPurpose() -> State {
        guard let lastPurpose else { return state }
        return requestAccess(lastPurpose)
    }

    /// Explicit user action on the relaunch path: re-opens a stored location through its bookmark.
    @discardableResult
    func restore(_ stored: ExternalLocationGrant) -> State {
        state = .active
        selectionRequestCount += 1
        lastPurpose = stored.isDirectory ? .folder : .file
        denialMessage = nil
        cancelledMessage = nil

        do {
            let resolution = try seams.resolveBookmark(stored.bookmark)
            var bookmark = stored.bookmark
            var didRefresh = false
            if resolution.isStale {
                bookmark = try seams.makeBookmark(resolution.url)
                didRefresh = true
            }
            guard startScope(resolution.url) else {
                return fail(with: PermissionError.denied(ExternalLocationCopy.deniedMessage))
            }
            releaseScopes(except: resolution.url)
            grant = ExternalLocationGrant(
                id: stored.id,
                url: resolution.url,
                displayName: stored.displayName,
                isDirectory: stored.isDirectory,
                bookmark: bookmark
            )
            didRefreshStaleBookmark = didRefresh
            lastFailureDescription = nil
            state = .succeeded
            return state
        } catch {
            return fail(with: error)
        }
    }

    /// Releases every access scope this coordinator opened (termination, explicit release, or an
    /// explicit selection change). Safe to call repeatedly.
    func releaseAllScopes() {
        releaseScopes(except: nil)
        state = .idle
    }

    // MARK: - Internals

    private func adopt(url: URL, purpose: ExternalLocationPurpose) -> State {
        do {
            let bookmark = try seams.makeBookmark(url)
            guard startScope(url) else {
                return fail(with: PermissionError.denied(ExternalLocationCopy.deniedMessage))
            }
            releaseScopes(except: url)
            grant = ExternalLocationGrant(
                id: UUID().uuidString.lowercased(),
                url: url,
                displayName: url.lastPathComponent,
                isDirectory: purpose.isDirectory,
                bookmark: bookmark
            )
            didRefreshStaleBookmark = false
            lastFailureDescription = nil
            state = .succeeded
            return state
        } catch {
            return fail(with: error)
        }
    }

    /// Opens one scope and records it, so it can be released exactly once.
    private func startScope(_ url: URL) -> Bool {
        guard seams.startScope(url) else { return false }
        openScopeURLs.append(url)
        startedScopeCount += 1
        return true
    }

    /// Stops every open scope except `excluded`, newest first.
    private func releaseScopes(except excluded: URL?) {
        var stillOpen: [URL] = []
        for url in openScopeURLs.reversed() {
            if let excluded, url.standardizedFileURL == excluded.standardizedFileURL {
                stillOpen.append(url)
                continue
            }
            seams.stopScope(url)
            releasedScopeCount += 1
        }
        openScopeURLs = stillOpen.reversed()
    }

    /// Records a failure without touching the last valid grant or any open scope.
    @discardableResult
    private func fail(with error: Error) -> State {
        let description = (error as? PermissionError)?.description ?? error.localizedDescription
        lastFailureDescription = description
        if let permissionError = error as? PermissionError, case .denied = permissionError {
            denialMessage = ExternalLocationCopy.deniedMessage
        } else {
            denialMessage = nil
        }
        state = .failed(description)
        return state
    }
}

import AppKit
import SwiftUI

// CursorPad — application entry point.
//
// PHASE-01 invariant: this file is created here and intentionally never modified by later
// phases. Every command below dispatches into `AppState`, whose behavior evolves only inside
// AppState.swift, so this frozen surface stays stable through PHASE-09.
@main
struct CursorpadApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate
    @State private var state = AppState()

    var body: some Scene {
        WindowGroup {
            AppRootView(state: state)
        }
        .commands {
            // New Note — Command + N.
            CommandGroup(replacing: .newItem) {
                Button("New Note") { state.newNote() }
                    .keyboardShortcut("n", modifiers: .command)
            }
            CommandGroup(replacing: .saveItem) {
                Button("Save") { state.saveNow() }
                    .keyboardShortcut("s", modifiers: .command)
                    .disabled(!state.canSaveNow)
            }
            // Remove the default Print item so Command + P is free for the command palette.
            CommandGroup(replacing: .printItem) { }
            // Command Palette — Command + P and Command + K.
            CommandGroup(after: .newItem) {
                Button("Command Palette") { state.presentCommandPalette() }
                    .keyboardShortcut("p", modifiers: .command)
                Button("Command Palette (Quick Open)") { state.presentCommandPalette() }
                    .keyboardShortcut("k", modifiers: .command)
            }
            // Toggle Sidebar — Command + B.
            CommandGroup(replacing: .sidebar) {
                Button("Toggle Sidebar") { state.toggleSidebar() }
                    .keyboardShortcut("b", modifiers: .command)
            }
            CommandGroup(after: .textEditing) {
                Button("Retry Editor Font") { state.retryEditorTypography() }
            }
            CommandMenu("View") {
                Button("Zoom In") { state.increaseFontSize() }
                    .keyboardShortcut("+", modifiers: .command)
                Button("Zoom Out") { state.decreaseFontSize() }
                    .keyboardShortcut("-", modifiers: .command)
                Button("Actual Size") { state.resetFontSize() }
                    .keyboardShortcut("0", modifiers: .command)
                Divider()
                Button(state.editorConfiguration.wrapsLines ? "Disable Line Wrapping" : "Enable Line Wrapping") {
                    state.toggleWordWrap()
                }
                .keyboardShortcut("z", modifiers: .option)
            }
        }

        Settings {
            EditorSettingsView(state: state)
        }
    }
}

/// Hosts the async termination flush.
///
/// `applicationShouldTerminate` replies `.terminateLater` and hands control to the handler that
/// `AppState` installs after launch. The handler always returns — `AppState.flushForTermination()`
/// bounds its own work to a 2 second fallback — so the reply is guaranteed and the process can
/// never hang on termination.
@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    var terminationFlushHandler: (@MainActor () async -> Void)?

    func applicationShouldTerminate(_ sender: NSApplication) -> NSApplication.TerminateReply {
        guard let handler = terminationFlushHandler else { return .terminateNow }
        Task { @MainActor in
            await handler()
            sender.reply(toApplicationShouldTerminate: true)
        }
        return .terminateLater
    }
}

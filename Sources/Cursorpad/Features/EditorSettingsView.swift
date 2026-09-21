import SwiftUI

/// Preferences window for CursorPad (Command + ,).
/// Lets the user adjust font size, tab width, and line wrapping, persisted to UserDefaults.
struct EditorSettingsView: View {
    @Bindable var state: AppState

    var body: some View {
        Form {
            Section("Typography & Spacing") {
                Stepper(value: Binding(
                    get: { state.editorConfiguration.fontSize },
                    set: { newSize in
                        var updated = state.editorConfiguration
                        updated.fontSize = newSize
                        state.updateEditorConfiguration(updated)
                    }
                ), in: 9...32, step: 1) {
                    HStack {
                        Text("Font Size")
                        Spacer()
                        Text("\(Int(state.editorConfiguration.fontSize)) pt")
                            .foregroundStyle(.secondary)
                    }
                }

                Picker("Tab Width", selection: Binding(
                    get: { state.editorConfiguration.tabWidth },
                    set: { newWidth in
                        var updated = state.editorConfiguration
                        updated.tabWidth = newWidth
                        state.updateEditorConfiguration(updated)
                    }
                )) {
                    Text("2 spaces").tag(2)
                    Text("4 spaces").tag(4)
                    Text("8 spaces").tag(8)
                }

                Toggle("Wrap Lines", isOn: Binding(
                    get: { state.editorConfiguration.wrapsLines },
                    set: { wraps in
                        var updated = state.editorConfiguration
                        updated.wrapsLines = wraps
                        state.updateEditorConfiguration(updated)
                    }
                ))
            }

            Section {
                Button("Reset to Defaults") {
                    state.resetEditorConfiguration()
                }
                .controlSize(.small)
            }
        }
        .formStyle(.grouped)
        .frame(width: 360, height: 220)
    }
}

import Common
import Foundation
import Sparkle
import SwiftUI

@MainActor
public func menuBar(viewModel: TrayMenuModel, updater: SPUUpdater) -> some Scene { // todo should it be converted to "SwiftUI struct"?
    MenuBarExtra {
        let shortIdentification = "\(aeroSpaceAppName) v\(aeroSpaceAppVersion) \(gitShortHash)"
        let identification      = "\(aeroSpaceAppName) v\(aeroSpaceAppVersion) \(gitHash)"
        Text(shortIdentification)
        Button("Copy to clipboard") { identification.copyToClipboard() }
            .keyboardShortcut("C", modifiers: .command)
        CheckForUpdatesView(updater: updater)
        Divider()

        if viewModel.axPermissionStatus == .granted {
            if let token: RunSessionGuard = .isServerEnabled, viewModel.lastReloadConfigContainedWarnings {
                Button {
                    Task.startUnstructured {
                        try await runLightSession(.menuBarButton, token) {
                            let args: ReloadConfigCmdArgs = ReloadConfigCmdArgs(rawArgs: []).copy(\.warningsAsErrors, true)
                            _ = await reloadConfig_nonCancellable(args: args)
                        }
                    }
                } label: {
                    Label("Config contains warnings...", systemImage: "exclamationmark.triangle.fill")
                }
                Divider()
            }
            if let token: RunSessionGuard = .isServerEnabled {
                Text("Workspaces:")
                ForEach(viewModel.workspaces, id: \.name) { workspace in
                    workspaceMenu(workspace, token)
                }
                Divider()
            }
            Button {
                NSWorkspace.shared.open(URL(string: "https://github.com/sponsors/nikitabobko").orDie())
                viewModel.sponsorshipMessage = sponsorshipPrompts.randomElement().orDie()
            } label: {
                Text("Sponsor AeroSpace on GitHub")
                Text(viewModel.sponsorshipMessage)
            }
            Divider()
            Button(viewModel.isEnabled ? "Disable" : "Enable") {
                Task.startUnstructured {
                    try await runLightSession(.menuBarButton, .forceRun) {
                        _ = await EnableCommand(args: EnableCmdArgs(rawArgs: [], targetState: .toggle))
                            .run(.defaultEnv, .emptyStdin)
                    }
                }
            }.keyboardShortcut("E", modifiers: .command)
            getExperimentalUISettingsMenu(viewModel: viewModel)
            openConfigButton()
            reloadConfigButton(warningsAsErrors: false)
        } else {
            Button("AeroSpace requires accessibility permission to move windows") {
                viewModel.axPermissionStatus = .waitingWithPrompt
            }
        }
        Button("Quit \(aeroSpaceAppName)") {
            Task.startUnstructured {
                terminationHandler?.beforeTermination()
                terminateApp()
            }
        }.keyboardShortcut("Q", modifiers: .command)
    } label: {
        switch (viewModel.axPermissionStatus, viewModel.isEnabled) {
            case (.granted, true):
                MenuBarLabel().environmentObject(viewModel)
            case (.granted, false):
                Image(systemName: "pause.circle.fill")
                    .resizable()
                    .aspectRatio(contentMode: .fit)
            case (_, _):
                Image(systemName: "exclamationmark.triangle.fill")
                    .resizable()
                    .aspectRatio(contentMode: .fit)
        }
    }
}

@MainActor @ViewBuilder
private func workspaceMenu(_ workspace: WorkspaceViewModel, _ token: RunSessionGuard) -> some View {
    Menu {
        Button {
            Task.startUnstructured {
                try await runLightSession(.menuBarButton, token) { _ = Workspace.get(byName: workspace.name).focusWorkspace() }
            }
        } label: {
            Toggle(isOn: .constant(workspace.isFocused)) {
                Text("Focus")
            }
        }
        Divider()
        Text("Root Layout")
        workspaceLayoutButton(workspace, layout: .tiles, title: "Tiles", token)
        workspaceLayoutButton(workspace, layout: .accordion, title: "Accordion", token)
        workspaceLayoutButton(workspace, layout: .dwindle, title: "Dwindle", token)
    } label: {
        Text(workspace.name + workspace.suffix).font(.system(.body, design: .monospaced))
    }
}

@MainActor
private func workspaceLayoutButton(
    _ workspace: WorkspaceViewModel,
    layout: LayoutCmdArgs.LayoutDescription,
    title: String,
    _ token: RunSessionGuard,
) -> some View {
    Button {
        Task.startUnstructured {
            try await runLightSession(.menuBarButton, token) {
                var args = LayoutCmdArgs(rawArgs: [], toggleBetween: [layout])
                args.root = true
                let command: any Command = LayoutCommand(args: args)
                _ = await Shell<any Command>.cmd(command).run(.defaultEnv.withWorkspaceName(workspace.name), .emptyStdin)
            }
        }
    } label: {
        Toggle(isOn: .constant(workspace.rootLayout.matches(layout))) {
            Text(title)
        }
    }
}

extension Layout {
    fileprivate func matches(_ description: LayoutCmdArgs.LayoutDescription) -> Bool {
        return switch description {
            case .accordion: self == .accordion
            case .tiles: self == .tiles
            case .dwindle: self == .dwindle
            case .horizontal, .vertical, .h_accordion, .v_accordion, .h_tiles, .v_tiles, .tiling, .floating: false
        }
    }
}

@MainActor @ViewBuilder
func openConfigButton(showShortcutGroup: Bool = false) -> some View {
    let editor = getTextEditorToOpenConfig()
    let button = Button("Open config in '\(editor.lastPathComponent)'") {
        let fallbackConfig: URL = FileManager.default.homeDirectoryForCurrentUser.appending(path: configDotfileName)
        switch findCustomConfigUrl() {
            case .file(let url):
                url.open(with: editor)
            case .noCustomConfigExists:
                _ = try? FileManager.default.copyItem(atPath: defaultConfigUrl.path, toPath: fallbackConfig.path)
                fallbackConfig.open(with: editor)
            case .ambiguousConfigError:
                fallbackConfig.open(with: editor)
        }
    }.keyboardShortcut(",", modifiers: .command)
    switch showShortcutGroup {
        case true: shortcutGroup(label: Text("⌘ ,"), content: button)
        case false: button
    }
}

@MainActor @ViewBuilder
func reloadConfigButton(showShortcutGroup: Bool = false, warningsAsErrors: Bool) -> some View {
    if let token: RunSessionGuard = .isServerEnabled {
        let button = Button("Reload config") {
            Task.startUnstructured {
                try await runLightSession(.menuBarButton, token) {
                    let args: ReloadConfigCmdArgs = ReloadConfigCmdArgs(rawArgs: []).copy(\.warningsAsErrors, warningsAsErrors)
                    _ = await reloadConfig_nonCancellable(args: args)
                }
            }
        }.keyboardShortcut("R", modifiers: .command)
        switch showShortcutGroup {
            case true: shortcutGroup(label: Text("⌘ R"), content: button)
            case false: button
        }
    }
}

func shortcutGroup(label: some View, content: some View) -> some View {
    GroupBox {
        VStack(alignment: .trailing, spacing: 6) {
            label
                .foregroundStyle(Color.secondary)
            content
        }
    }
}

func getTextEditorToOpenConfig() -> URL {
    NSWorkspace.shared.urlForApplication(toOpen: findCustomConfigUrl().urlOrNil ?? defaultConfigUrl)?
        .takeIf { $0.lastPathComponent != "Xcode.app" } // Blacklist Xcode. It is too heavy to open plain text files
        ?? URL(filePath: "/System/Applications/TextEdit.app")
}

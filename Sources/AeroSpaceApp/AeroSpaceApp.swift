import AppBundle
import Sparkle
import SwiftUI

// This file is shared between SPM and xcode project

@main
struct AeroSpaceApp: App {
    private let updaterController: SPUStandardUpdaterController
    @StateObject var viewModel = TrayMenuModel.shared
    @StateObject var messageModel = MessageModel.shared
    @Environment(\.openWindow) var openWindow: OpenWindowAction

    init() {
        #if DEBUG
            let startingUpdater = false
        #else
            let startingUpdater = true
        #endif
        updaterController = SPUStandardUpdaterController(
            startingUpdater: startingUpdater,
            updaterDelegate: nil,
            userDriverDelegate: nil,
        )
        initAppBundle()
    }

    var body: some Scene {
        menuBar(viewModel: viewModel, updater: updaterController.updater)
        getMessageWindow(messageModel: messageModel)
            .onChange(of: messageModel.message) { message in
                if message != nil {
                    openWindow(id: messageWindowId)
                }
            }
    }
}

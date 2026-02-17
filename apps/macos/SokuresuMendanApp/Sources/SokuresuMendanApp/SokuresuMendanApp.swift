import AppKit
import SwiftUI

@main
struct SokuresuMendanApp: App {
    @StateObject private var viewModel = InterviewSessionViewModel()

    var body: some Scene {
        MenuBarExtra("速レス面談", systemImage: "bolt.badge.clock") {
            MenuBarContentView(viewModel: viewModel)
        }

        Window("ダッシュボード", id: "dashboard") {
            DashboardView(viewModel: viewModel)
                .onAppear {
                    viewModel.bootstrap()
                }
        }

        Window("テストモード", id: "test-mode") {
            TestModeView(viewModel: viewModel)
        }

        Window("設定", id: "settings-window") {
            SettingsView(viewModel: viewModel)
        }
    }
}

private struct MenuBarContentView: View {
    @ObservedObject var viewModel: InterviewSessionViewModel
    @Environment(\.openWindow) private var openWindow

    var body: some View {
        Button(viewModel.isListening ? "停止" : "聞き取り開始") {
            if viewModel.isListening {
                viewModel.stopListening()
            } else {
                viewModel.startListening()
            }
        }

        Divider()

        Button("テストモード") {
            viewModel.openTestMode()
            openWindowAtFront(id: "test-mode")
        }

        Button("設定") {
            openWindowAtFront(id: "settings-window")
        }

        Button("ダッシュボードを開く") {
            openWindowAtFront(id: "dashboard")
        }

        Divider()

        Button("終了") {
            NSApp.terminate(nil)
        }
    }

    private func openWindowAtFront(id: String) {
        NSApp.activate(ignoringOtherApps: true)
        openWindow(id: id)
    }
}

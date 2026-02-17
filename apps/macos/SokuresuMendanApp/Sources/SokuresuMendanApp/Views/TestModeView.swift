import SwiftUI

struct TestModeView: View {
    @ObservedObject var viewModel: InterviewSessionViewModel

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text("テストモード")
                .font(.title2)
                .bold()

            GroupBox("入力ソース") {
                Picker("入力", selection: $viewModel.selectedInputSource) {
                    ForEach(InputSource.allCases) { source in
                        Text(source.rawValue).tag(source)
                    }
                }
                .pickerStyle(.segmented)
                .onChange(of: viewModel.selectedInputSource, initial: false) { _, _ in
                    viewModel.userChangedInputSource()
                }
                .padding(.top, 6)

                HStack {
                    Text("選択デバイス: \(viewModel.inputDeviceName)")
                    Spacer()
                    Button("再取得") {
                        viewModel.refreshInputDevices()
                    }
                }
                .padding(.top, 6)

                if !viewModel.inputDevices.isEmpty {
                    Picker("入力デバイス選択", selection: $viewModel.inputDeviceName) {
                        ForEach(viewModel.inputDevices, id: \.self) { device in
                            Text(device).tag(device)
                        }
                    }
                    .padding(.top, 6)
                    .onChange(of: viewModel.inputDeviceName, initial: false) { _, _ in
                        viewModel.userChangedInputDevice()
                    }
                }
            }

            GroupBox("Push-to-talk") {
                HStack(spacing: 10) {
                    Button("押している間だけ録音") {}
                        .buttonStyle(.borderedProminent)
                        .simultaneousGesture(
                            DragGesture(minimumDistance: 0)
                                .onChanged { _ in viewModel.beginPushToTalk() }
                                .onEnded { _ in viewModel.endPushToTalk() }
                        )
                    Text("マイク検証用。離すと停止します。")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                .padding(.top, 6)

                Text("出力デバイス: \(viewModel.outputDeviceName)")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Text(viewModel.captureStatusSummary)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            GroupBox("テキスト入力テスト") {
                VStack(alignment: .leading, spacing: 8) {
                    TextField("質問を入力（例: 設計判断の理由を教えてください）", text: $viewModel.testInputText)
                        .textFieldStyle(.roundedBorder)

                    HStack {
                        Button("Stage1/2生成") {
                            viewModel.generateFromTextInput()
                        }
                        Button("セッションクリア") {
                            viewModel.clearSession()
                        }
                    }
                }
                .padding(.top, 6)
            }

            GroupBox("デバッグ") {
                VStack(alignment: .leading, spacing: 6) {
                    Text("カテゴリ推定: \(viewModel.debugCategory.rawValue)")
                    Text("ルール理由: \(viewModel.debugReason)")
                    Text("一致キーワード: \(viewModel.debugKeywords.joined(separator: ", ").ifEmpty("なし"))")
                    Text("質問検出まで: \(metricText(viewModel.metrics.detectionMs))")
                    Text("Stage1 初回表示まで: \(metricText(viewModel.metrics.stage1FirstTokenMs))")
                }
                .padding(.top, 6)
            }

            Spacer()
        }
        .padding(18)
        .frame(minWidth: 640, minHeight: 560)
        .onDisappear {
            viewModel.closeTestMode()
        }
    }

    private func metricText(_ value: Int?) -> String {
        guard let value else { return "--" }
        return "\(value) ms"
    }
}

private extension String {
    func ifEmpty(_ fallback: String) -> String {
        isEmpty ? fallback : self
    }
}

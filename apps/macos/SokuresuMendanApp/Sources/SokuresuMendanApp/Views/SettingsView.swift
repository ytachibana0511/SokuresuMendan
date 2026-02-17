import SwiftUI

struct SettingsView: View {
    @ObservedObject var viewModel: InterviewSessionViewModel

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text("設定")
                .font(.title2)
                .bold()

            GroupBox("プロキシ設定") {
                VStack(alignment: .leading, spacing: 8) {
                    Text("ローカルプロキシURL: http://127.0.0.1:39871")
                    Text("OpenAI APIキーはアプリに保存せず、プロキシの `.env` で管理してください。")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                .padding(.top, 6)
            }

            GroupBox("プロフィール") {
                VStack(alignment: .leading, spacing: 10) {
                    Picker("利用プロファイル", selection: $viewModel.selectedProfileID) {
                        Text("未選択").tag(UUID?.none)
                        ForEach(viewModel.profiles) { profile in
                            Text(profile.name).tag(UUID?.some(profile.id))
                        }
                    }

                    HStack {
                        Button("ファイルからimport (.txt/.md/.json)") {
                            viewModel.importProfileFromFile()
                        }
                        Spacer()
                    }

                    TextField("プロファイル名", text: $viewModel.profileNameInput)
                        .textFieldStyle(.roundedBorder)
                    TextEditor(text: $viewModel.profileTextInput)
                        .font(.system(size: 12, design: .monospaced))
                        .frame(height: 150)
                        .overlay(
                            RoundedRectangle(cornerRadius: 8)
                                .stroke(.quaternary)
                        )

                    Button("貼り付け内容を保存") {
                        viewModel.addProfileFromPaste()
                    }
                }
                .padding(.top, 6)
            }

            Spacer()
        }
        .padding(18)
        .frame(minWidth: 680, minHeight: 540)
    }
}

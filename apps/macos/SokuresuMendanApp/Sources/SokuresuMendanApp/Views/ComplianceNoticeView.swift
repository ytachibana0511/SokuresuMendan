import SwiftUI

struct ComplianceNoticeView: View {
    let onAccept: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text("ご利用前の注意事項")
                .font(.title2)
                .bold()

            ScrollView {
                VStack(alignment: .leading, spacing: 10) {
                    Text("本アプリは面談中の回答支援ツールです。録音・文字起こし・生成機能の利用は、必ず各国法令、相手方の同意、会議ツールの利用規約に従ってください。")
                    Text("音声・文字起こし・質問・回答生成入力は外部サーバーへ保存しない構成です（本MVPはサーバーを持ちません）。")
                    Text("OpenAI APIキーはローカルプロキシの環境変数として端末内で管理し、リポジトリに含めないでください。")
                    Text("画面共有時はオーバーレイを隠し、機密情報が映り込まないことを確認してください。")
                    Text("この注意事項に同意した場合のみ利用を継続してください。")
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }

            HStack {
                Spacer()
                Button("同意して開始") {
                    onAccept()
                }
                .keyboardShortcut(.defaultAction)
            }
        }
        .padding(20)
    }
}

import SwiftUI

struct DashboardView: View {
    @ObservedObject var viewModel: InterviewSessionViewModel

    @State private var answerAreaHeight: CGFloat = 400
    @State private var historyAreaHeight: CGFloat = 220
    @State private var answerDragStartHeight: CGFloat?
    @State private var historyDragStartHeight: CGFloat?

    private let answerHeightRange: ClosedRange<CGFloat> = 260...640
    private let historyHeightRange: ClosedRange<CGFloat> = 140...460
    private let answerReadableWidth: CGFloat = 640
    private let answerSoftWrapChars = 24
    private let questionOutputFont: Font = .system(size: 21, weight: .semibold, design: .rounded)
    private let answerOutputFont: Font = .system(size: 21, weight: .medium, design: .rounded)

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            headerRow
            connectionSection
            unifiedMainSection
            historySection
            debugSection
            Spacer(minLength: 0)
        }
        .padding(16)
        .frame(minWidth: 960, minHeight: 760)
        .sheet(isPresented: $viewModel.showComplianceNotice) {
            ComplianceNoticeView {
                viewModel.acceptComplianceNotice()
            }
            .frame(width: 600, height: 500)
        }
        .alert("エラー", isPresented: .constant(viewModel.errorMessage != nil), actions: {
            Button("閉じる") {
                viewModel.errorMessage = nil
            }
        }, message: {
            Text(viewModel.errorMessage ?? "")
        })
    }

    private var headerRow: some View {
        HStack(alignment: .top, spacing: 12) {
            VStack(alignment: .leading, spacing: 2) {
                Text("SokuresuMendan")
                    .font(.system(size: 24, weight: .semibold))
                Text("ダッシュボード（統合画面）")
                    .foregroundStyle(.secondary)
                    .font(.subheadline)
            }
            Spacer()
            HStack(spacing: 8) {
                Button(viewModel.isListening ? "停止" : "聞き取り開始") {
                    if viewModel.isListening {
                        viewModel.stopListening()
                    } else {
                        viewModel.startListening()
                    }
                }
                .keyboardShortcut("l", modifiers: [.command])

                Button("生成") {
                    viewModel.generateFromCurrentQuestion()
                }
                .keyboardShortcut("g", modifiers: [.command])

                Button("コピー") {
                    viewModel.copyCurrentAnswer()
                }
                Button("クリア") {
                    viewModel.clearSession()
                }
            }
        }
    }

    private var connectionSection: some View {
        GroupBox("接続 / 入力 / レイテンシ") {
            VStack(alignment: .leading, spacing: 8) {
                HStack(spacing: 8) {
                    statusPill(title: "プロキシ", value: viewModel.proxyStatus.rawValue)
                    statusPill(title: "文字起こし", value: viewModel.transcriptionStatus.rawValue)
                    statusPill(title: "生成", value: viewModel.generationStatus.rawValue)
                }

                Picker("入力ソース", selection: $viewModel.selectedInputSource) {
                    ForEach(InputSource.allCases) { source in
                        Text(source.rawValue).tag(source)
                    }
                }
                .pickerStyle(.segmented)
                .onChange(of: viewModel.selectedInputSource, initial: false) { _, _ in
                    viewModel.userChangedInputSource()
                }

                HStack {
                    Text("入力デバイス: \(viewModel.inputDeviceName)")
                    Spacer()
                    Button("入力デバイス再取得") {
                        viewModel.refreshInputDevices()
                    }
                }

                if !viewModel.inputDevices.isEmpty {
                    Picker("入力デバイス", selection: $viewModel.inputDeviceName) {
                        ForEach(viewModel.inputDevices, id: \.self) { device in
                            Text(device).tag(device)
                        }
                    }
                    .frame(maxWidth: 440)
                    .onChange(of: viewModel.inputDeviceName, initial: false) { _, _ in
                        viewModel.userChangedInputDevice()
                    }
                }

                HStack {
                    Text("出力デバイス: \(viewModel.outputDeviceName)")
                    Spacer()
                    Text("最終フレーム: \(viewModel.lastAudioFrameAgeText)")
                }
                .font(.caption)
                .foregroundStyle(.secondary)

                Text(viewModel.captureStatusSummary)
                    .font(.caption)
                    .foregroundStyle(.secondary)

                HStack {
                    Text("質問検出: \(metricText(viewModel.metrics.detectionMs))")
                    Spacer()
                    Text("Stage1初回: \(metricText(viewModel.metrics.stage1FirstTokenMs))")
                }
                .font(.caption)
                .foregroundStyle(.secondary)
            }
            .padding(.top, 4)
        }
    }

    private var unifiedMainSection: some View {
        GroupBox("面談アシスト（短文→追記）") {
            VStack(alignment: .leading, spacing: 10) {
                compactTranscriptSection
                manualGenerateSection

                HStack {
                    Text("Stage1: \(viewModel.stage1Status.label)")
                    Spacer()
                    Text("Stage2: \(viewModel.stage2Status.label)")
                }
                .font(.caption)
                .foregroundStyle(.secondary)

                Text("回答案")
                    .font(.headline)

                ScrollView {
                    VStack(alignment: .leading, spacing: 12) {
                        VStack(alignment: .leading, spacing: 6) {
                            Text("即答版")
                                .font(.subheadline)
                                .bold()
                            Text(viewModel.quickAnswerText.stealthWrapped(maxCharactersPerLine: answerSoftWrapChars))
                                .font(answerOutputFont)
                                .lineSpacing(4)
                                .fixedSize(horizontal: false, vertical: true)
                                .frame(maxWidth: .infinity, alignment: .leading)
                        }
                        .frame(maxWidth: answerReadableWidth, alignment: .leading)
                        .padding(12)
                        .background(.blue.opacity(0.08), in: RoundedRectangle(cornerRadius: 10))

                        if viewModel.stage2Appending {
                            Text("追記中…")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }

                        if let extended = viewModel.extendedAnswerText {
                            VStack(alignment: .leading, spacing: 6) {
                                Text("追記版（即答版の続き）")
                                    .font(.subheadline)
                                    .bold()
                                Text(viewModel.appendMarkerText)
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                                Text(extended.stealthWrapped(maxCharactersPerLine: answerSoftWrapChars))
                                    .font(answerOutputFont)
                                    .lineSpacing(4)
                                    .fixedSize(horizontal: false, vertical: true)
                                    .frame(maxWidth: .infinity, alignment: .leading)
                            }
                            .frame(maxWidth: answerReadableWidth, alignment: .leading)
                            .padding(12)
                            .background(.green.opacity(0.08), in: RoundedRectangle(cornerRadius: 10))
                        }
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                }
                .frame(height: answerAreaHeight)

                answerResizeHandle

                HStack(spacing: 10) {
                    Button("履歴クリア") {
                        viewModel.clearAnswerHistory()
                    }
                }
            }
            .padding(.top, 4)
        }
    }

    private var manualGenerateSection: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Text("手動生成")
                    .font(.subheadline)
                    .bold()
                Spacer()
                Text("入力元: \(viewModel.manualGenerationSourceDescription)")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Button {
                viewModel.generateFromCurrentQuestion()
            } label: {
                HStack {
                    Image(systemName: "bolt.fill")
                    Text("この内容で回答案を生成（⌘G）")
                        .fontWeight(.semibold)
                    Spacer()
                }
                .padding(.vertical, 4)
            }
            .buttonStyle(.borderedProminent)
        }
        .padding(10)
        .background(.quaternary.opacity(0.12), in: RoundedRectangle(cornerRadius: 10))
    }

    private var compactTranscriptSection: some View {
        VStack(alignment: .leading, spacing: 6) {
            compactTranscriptCard(
                title: "文字起こしライブ",
                text: viewModel.transcript.liveTranscript,
                textFont: .system(size: 17, weight: .regular, design: .rounded),
                maxLines: 2
            )
            compactTranscriptCard(
                title: "質問（暫定/確定）",
                text: viewModel.transcript.finalizedQuestion.ifEmpty(viewModel.transcript.provisionalQuestion.ifEmpty("-")),
                textFont: questionOutputFont,
                maxLines: 3
            )
        }
    }

    private var historySection: some View {
        GroupBox("過去の回答案（パッと確認）") {
            VStack(alignment: .leading, spacing: 8) {
                historyResizeHandle

                ScrollView {
                    if previousHistoryItems.isEmpty {
                        Text("まだ履歴はありません")
                            .foregroundStyle(.secondary)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .padding(.vertical, 8)
                    } else {
                        VStack(alignment: .leading, spacing: 8) {
                            ForEach(Array(previousHistoryItems.enumerated()), id: \.element.id) { index, item in
                                VStack(alignment: .leading, spacing: 6) {
                                    HStack {
                                        Text("\(historyLabel(index))  |  \(timestampText(item.timestamp))  |  \(item.category.rawValue)")
                                            .font(.caption)
                                            .foregroundStyle(.secondary)
                                        Spacer()
                                    }
                                    Text("Q: \(item.question)")
                                        .bold()
                                    Text("回答: \(item.answer10s.ifEmpty(item.stage0Template).stealthWrapped(maxCharactersPerLine: answerSoftWrapChars))")
                                        .lineSpacing(3)
                                    if let longText = item.answer30s.nonEmpty {
                                        let continuation = viewModel.continuationText(
                                            quick: item.answer10s.ifEmpty(item.stage0Template),
                                            extended: longText
                                        )
                                        if !continuation.isEmpty {
                                            Text("\(viewModel.appendMarkerText) \(continuation.stealthWrapped(maxCharactersPerLine: answerSoftWrapChars))")
                                                .lineSpacing(3)
                                        }
                                    }
                                }
                                .frame(maxWidth: .infinity, alignment: .leading)
                                .padding(10)
                                .background(.quaternary.opacity(0.16), in: RoundedRectangle(cornerRadius: 8))
                            }
                        }
                    }
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        }
        .frame(height: historyAreaHeight)
    }

    private var debugSection: some View {
        GroupBox("判定デバッグ") {
            VStack(alignment: .leading, spacing: 4) {
                Text("カテゴリ: \(viewModel.debugCategory.rawValue)")
                Text("理由: \(viewModel.debugReason)")
                Text("一致キーワード: \(viewModel.debugKeywords.joined(separator: ", ").ifEmpty("なし"))")
                Text("音声監視: \(viewModel.captureStatusSummary)")
                Text("ログ: \(viewModel.runtimeLogPath)")
                    .lineLimit(1)
                    .truncationMode(.middle)
                HStack(spacing: 8) {
                    Button("ログパスをコピー") {
                        viewModel.copyRuntimeLogPath()
                    }
                    Button("ログをFinderで開く") {
                        viewModel.openRuntimeLogFolder()
                    }
                    Button("ログをクリア") {
                        viewModel.clearRuntimeLog()
                    }
                }
            }
            .font(.caption)
            .foregroundStyle(.secondary)
            .padding(.top, 4)
        }
    }

    private var answerResizeHandle: some View {
        resizeHandle(label: "回答エリア: 上下ドラッグで高さ調整")
            .gesture(
                DragGesture(minimumDistance: 0)
                    .onChanged { value in
                        if answerDragStartHeight == nil {
                            answerDragStartHeight = answerAreaHeight
                        }
                        let base = answerDragStartHeight ?? answerAreaHeight
                        answerAreaHeight = clamped(base - value.translation.height, within: answerHeightRange)
                    }
                    .onEnded { _ in
                        answerDragStartHeight = nil
                    }
            )
    }

    private var historyResizeHandle: some View {
        resizeHandle(label: "過去回答エリア: 上下ドラッグで高さ調整")
            .gesture(
                DragGesture(minimumDistance: 0)
                    .onChanged { value in
                        if historyDragStartHeight == nil {
                            historyDragStartHeight = historyAreaHeight
                        }
                        let base = historyDragStartHeight ?? historyAreaHeight
                        historyAreaHeight = clamped(base - value.translation.height, within: historyHeightRange)
                    }
                    .onEnded { _ in
                        historyDragStartHeight = nil
                    }
            )
    }

    private var previousHistoryItems: [AnswerHistoryEntry] {
        Array(viewModel.answerHistory.dropFirst().prefix(3))
    }

    private func resizeHandle(label: String) -> some View {
        HStack(spacing: 8) {
            Image(systemName: "line.3.horizontal")
                .foregroundStyle(.secondary)
            Text(label)
                .font(.caption)
                .foregroundStyle(.secondary)
            Spacer()
        }
        .padding(.vertical, 4)
        .contentShape(Rectangle())
        .background(.quaternary.opacity(0.12), in: RoundedRectangle(cornerRadius: 6))
    }

    private func statusPill(title: String, value: String) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(title)
                .font(.caption2)
                .foregroundStyle(.secondary)
            Text(value)
                .font(.subheadline)
                .bold()
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(8)
        .background(.quaternary.opacity(0.2), in: RoundedRectangle(cornerRadius: 8))
    }

    private func compactTranscriptCard(title: String, text: String, textFont: Font, maxLines: Int) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(title)
                .font(.caption2)
                .foregroundStyle(.secondary)
            Text(text.ifEmpty("-"))
                .font(textFont)
                .lineLimit(maxLines)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
        .padding(8)
        .background(.quaternary.opacity(0.16), in: RoundedRectangle(cornerRadius: 8))
    }

    private func metricText(_ value: Int?) -> String {
        guard let value else { return "--" }
        return "\(value) ms"
    }

    private func timestampText(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "ja_JP")
        formatter.dateFormat = "HH:mm:ss"
        return formatter.string(from: date)
    }

    private func historyLabel(_ index: Int) -> String {
        switch index {
        case 0: return "1つ前"
        case 1: return "2つ前"
        default: return "3つ前"
        }
    }

    private func clamped(_ value: CGFloat, within range: ClosedRange<CGFloat>) -> CGFloat {
        min(max(value, range.lowerBound), range.upperBound)
    }
}

private extension String {
    func ifEmpty(_ fallback: String) -> String {
        isEmpty ? fallback : self
    }

    var nonEmpty: String? {
        isEmpty ? nil : self
    }

    func stealthWrapped(maxCharactersPerLine: Int) -> String {
        guard maxCharactersPerLine > 0, !isEmpty else { return self }

        let normalized = replacingOccurrences(of: "\r\n", with: "\n")
        let paragraphs = normalized.split(separator: "\n", omittingEmptySubsequences: false).map(String.init)
        let wrappedParagraphs = paragraphs.map { paragraph in
            Self.wrapParagraphForReadability(paragraph, preferredWidth: maxCharactersPerLine)
        }
        return wrappedParagraphs.joined(separator: "\n")
    }

    private static func wrapParagraphForReadability(_ paragraph: String, preferredWidth: Int) -> String {
        guard !paragraph.isEmpty else { return "" }

        let sentences = splitAtSentenceBoundaries(paragraph)
        var lines: [String] = []
        lines.reserveCapacity(sentences.count)
        for sentence in sentences {
            lines.append(contentsOf: wrapChunk(sentence, preferredWidth: preferredWidth))
        }
        return lines.joined(separator: "\n")
    }

    private static func splitAtSentenceBoundaries(_ text: String) -> [String] {
        var sections: [String] = []
        var current = ""
        let sentenceEnders = Set<Character>(["。", "！", "？", "!", "?"])

        for character in text {
            current.append(character)
            if sentenceEnders.contains(character) {
                let trimmed = current.trimmingCharacters(in: .whitespaces)
                if !trimmed.isEmpty {
                    sections.append(trimmed)
                }
                current = ""
            }
        }

        let tail = current.trimmingCharacters(in: .whitespaces)
        if !tail.isEmpty {
            sections.append(tail)
        }

        return sections.isEmpty ? [text] : sections
    }

    private static func wrapChunk(_ text: String, preferredWidth: Int) -> [String] {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return [] }

        var chars = Array(trimmed)
        guard chars.count > preferredWidth else { return [trimmed] }

        var result: [String] = []
        while chars.count > preferredWidth {
            let offset = bestBreakOffset(in: chars, preferredWidth: preferredWidth)
            let head = String(chars[..<offset]).trimmingCharacters(in: .whitespaces)
            if !head.isEmpty {
                result.append(head)
            }
            chars = Array(chars[offset...])
            while let first = chars.first, first == " " || first == "　" {
                chars.removeFirst()
            }
        }

        let tail = String(chars).trimmingCharacters(in: .whitespaces)
        if !tail.isEmpty {
            result.append(tail)
        }

        return result
    }

    private static func bestBreakOffset(in chars: [Character], preferredWidth: Int) -> Int {
        let count = chars.count
        if count <= 1 {
            return count
        }

        let minOffset = Swift.max(8, Int(Double(preferredWidth) * 0.62))
        let maxOffset = Swift.min(count - 1, Int(Double(preferredWidth) * 1.22))
        let lower = Swift.min(minOffset, maxOffset)
        let upper = Swift.max(minOffset, maxOffset)
        let target = Swift.min(preferredWidth, count - 1)

        func chooseClosest(_ offsets: [Int]) -> Int? {
            offsets.min { abs($0 - target) < abs($1 - target) }
        }

        let delimiters = Set<Character>(["。", "、", "！", "？", "!", "?", ";", "；", ",", "，", " ", "　", "：", ":"])
        var delimiterOffsets: [Int] = []
        if lower <= upper {
            for i in lower...upper where delimiters.contains(chars[i]) {
                delimiterOffsets.append(i + 1)
            }
        }
        if let chosen = chooseClosest(delimiterOffsets) {
            return Swift.max(1, Swift.min(chosen, count - 1))
        }

        let particleCandidates = Set<Character>(["は", "が", "を", "に", "で", "と", "へ", "も", "の", "ね", "よ", "か"])
        var particleOffsets: [Int] = []
        if lower <= upper {
            for i in lower...upper where particleCandidates.contains(chars[i]) {
                particleOffsets.append(i + 1)
            }
        }
        if let chosen = chooseClosest(particleOffsets) {
            return Swift.max(1, Swift.min(chosen, count - 1))
        }

        return Swift.max(1, Swift.min(target, count - 1))
    }
}

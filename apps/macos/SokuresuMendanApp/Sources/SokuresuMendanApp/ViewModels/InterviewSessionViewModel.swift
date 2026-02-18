import AppKit
import Foundation
import UniformTypeIdentifiers

@MainActor
final class InterviewSessionViewModel: ObservableObject {
    @Published var proxyStatus: ProxyStatus = .ng
    @Published var transcriptionStatus: StreamStatus = .disconnected
    @Published var generationStatus: StreamStatus = .idle

    @Published var stage1Status: GenerationStatus = .idle
    @Published var stage2Status: GenerationStatus = .idle
    @Published var stage2Appending = false

    @Published var selectedInputSource: InputSource = .microphone
    @Published var inputDeviceName: String = "未選択"
    @Published var inputDevices: [String] = []
    @Published var outputDeviceName: String = "未取得"
    @Published var audioTapBufferCount: Int = 0
    @Published var audioFramesSent: Int = 0
    @Published var audioSignalDetected = false
    @Published var lastAudioFrameAt: Date?

    @Published var transcript = TranscriptSnapshot(
        liveTranscript: "候補者の音声がここにリアルタイム表示されます",
        provisionalQuestion: "",
        finalizedQuestion: ""
    )
    @Published var stageOutput = StageOutput(
        stage0Template: "- 質問を検出するとここに即時テンプレが表示されます\n- Stage1は即答向けの短い回答を最速で生成します\n- Stage2は後追いで詳細版を追記します"
    )
    @Published var stage1StreamingPreview = ""
    @Published var stage2StreamingPreview = ""
    @Published var answerHistory: [AnswerHistoryEntry] = []

    @Published var metrics = LatencyMetrics()
    @Published var debugCategory: QuestionCategory = .unknown
    @Published var debugReason: String = "未検出"
    @Published var debugKeywords: [String] = []

    @Published var isListening = false
    @Published var isTestModeVisible = false
    @Published var showComplianceNotice = false

    @Published var testInputText = ""
    @Published var errorMessage: String?

    @Published var profiles: [CandidateProfile] = []
    @Published var selectedProfileID: UUID?
    @Published var profileNameInput = ""
    @Published var profileTextInput = ""
    @Published var runtimeLogPath: String = AppRuntimeLogger.shared.logFilePath

    private let proxyClient: ProxyClient
    private let audioService: AudioCaptureService
    private let detector = QuestionDetector()
    private let templateEngine = StageTemplateEngine()
    private let panicHotkeyManager = PanicHotkeyManager()
    private let profileStore: ProfileStore?
    private let logger = AppRuntimeLogger.shared

    private var healthTask: Task<Void, Never>?
    private var captureHealthTask: Task<Void, Never>?
    private var systemAudioRoutingGuardTask: Task<Void, Never>?
    private var streamBuffer = ""
    private var detectionStartedAt: Date?
    private var stage1StartedAt: Date?
    private var stage1TriggeredForCurrentBuffer = false
    private var latestDetectedQuestion: DetectedQuestion?
    private var ignoreNextInputSourceChangeCount = 0
    private var ignoreNextInputDeviceChangeCount = 0
    private var isRestartingInputPipeline = false
    private var restartTask: Task<Void, Never>?
    private var startCaptureTask: Task<Void, Never>?
    private var captureStartSequence = 0
    private var didBootstrap = false
    private var activeHistoryID: UUID?
    private var expectedSystemAudioInputDeviceName: String?
    private var routeMismatchStreak = 0
    private var routeRecoveryInFlight = false
    private var lastRouteAlertAt: Date = .distantPast

    init(
        proxyClient: ProxyClient = ProxyClient(),
        audioService: AudioCaptureService = AudioCaptureService()
    ) {
        self.proxyClient = proxyClient
        self.audioService = audioService
        self.profileStore = try? ProfileStore()
        logger.log("ViewModel", "init")

        proxyClient.onTranscribeEvent = { [weak self] event in
            Task { @MainActor in
                self?.handleTranscribe(event)
            }
        }

        audioService.onAudioFrame = { [weak self] frame in
            self?.proxyClient.sendAudioFrame(frame)
            Task { @MainActor in
                guard let self else { return }
                self.audioFramesSent += 1
                if self.audioFramesSent == 1 || self.audioFramesSent == 30 || self.audioFramesSent % 500 == 0 {
                    self.logger.log("ViewModel", "audio frame sent count=\(self.audioFramesSent) bytes=\(frame.count)")
                }
                self.lastAudioFrameAt = .now
                if !self.audioSignalDetected, Self.containsAudibleSamples(frame) {
                    self.audioSignalDetected = true
                    self.logger.log("ViewModel", "audio signal detected")
                }
            }
        }
        audioService.onTapBuffer = { [weak self] in
            Task { @MainActor in
                guard let self else { return }
                self.audioTapBufferCount += 1
                if self.audioTapBufferCount == 1 || self.audioTapBufferCount == 30 || self.audioTapBufferCount % 500 == 0 {
                    self.logger.log("ViewModel", "tap buffer count=\(self.audioTapBufferCount)")
                }
            }
        }

        inputDevices = audioService.availableInputDeviceNames()
        setSelectedInputSourceProgrammatically(
            recommendedInputDeviceName(for: .systemAudio) == nil ? .microphone : .systemAudio
        )
        alignInputDeviceToSelectedSource()
        outputDeviceName = audioService.currentDefaultOutputDeviceName() ?? "不明"
        ignoreNextInputSourceChangeCount = 0
        ignoreNextInputDeviceChangeCount = 0

        if let store = profileStore {
            profiles = store.loadProfiles()
            selectedProfileID = profiles.first?.id
        }
        logger.log("ViewModel", "init complete selectedInputSource=\(selectedInputSource.rawValue) inputDevice=\(inputDeviceName)")
    }

    func bootstrap() {
        guard !didBootstrap else { return }
        didBootstrap = true
        logger.log("ViewModel", "bootstrap")

        let hasAccepted = UserDefaults.standard.bool(forKey: "legal.notice.accepted")
        showComplianceNotice = !hasAccepted

        panicHotkeyManager.startListening {
            Task { @MainActor in
                NSApp.hide(nil)
            }
        }

        healthTask = Task { [weak self] in
            while !Task.isCancelled {
                guard let self else { return }
                let isHealthy = await self.proxyClient.checkHealth()
                self.proxyStatus = isHealthy ? .ok : .ng
                try? await Task.sleep(nanoseconds: 1_500_000_000)
            }
        }
    }

    func acceptComplianceNotice() {
        showComplianceNotice = false
        UserDefaults.standard.set(true, forKey: "legal.notice.accepted")
    }

    func refreshInputDevices() {
        inputDevices = audioService.availableInputDeviceNames()
        logger.log("ViewModel", "refreshInputDevices count=\(inputDevices.count) current=\(inputDeviceName)")
        if !inputDevices.contains(inputDeviceName) {
            setInputDeviceNameProgrammatically(
                recommendedInputDeviceName(for: selectedInputSource) ?? inputDevices.first ?? "既定の入力デバイス"
            )
        }
        alignInputDeviceToSelectedSource()
        outputDeviceName = audioService.currentDefaultOutputDeviceName() ?? "不明"
    }

    func userChangedInputSource() {
        if consumeIgnoredInputSourceChange() {
            return
        }
        logger.log("ViewModel", "userChangedInputSource source=\(selectedInputSource.rawValue)")
        alignInputDeviceToSelectedSource()
        restartListeningIfNeeded()
    }

    func userChangedInputDevice() {
        if consumeIgnoredInputDeviceChange() {
            return
        }
        logger.log("ViewModel", "userChangedInputDevice device=\(inputDeviceName)")
        restartListeningIfNeeded()
    }

    func startListening() {
        if isListening {
            logger.log("ViewModel", "startListening skipped (already listening)")
            return
        }
        logger.log("ViewModel", "startListening begin source=\(selectedInputSource.rawValue) device=\(inputDeviceName)")

        if selectedInputSource == .text {
            // 「聞き取り開始」は音声入力前提。text選択時は自動で音声入力へ寄せる。
            setSelectedInputSourceProgrammatically(
                recommendedInputDeviceName(for: .systemAudio) == nil ? .microphone : .systemAudio
            )
            alignInputDeviceToSelectedSource()
        }

        isListening = true
        transcriptionStatus = .connecting
        generationStatus = .idle
        stage1TriggeredForCurrentBuffer = false
        audioTapBufferCount = 0
        audioFramesSent = 0
        audioSignalDetected = false
        lastAudioFrameAt = nil
        outputDeviceName = audioService.currentDefaultOutputDeviceName() ?? "不明"
        captureHealthTask?.cancel()
        captureHealthTask = nil
        systemAudioRoutingGuardTask?.cancel()
        systemAudioRoutingGuardTask = nil
        routeMismatchStreak = 0
        routeRecoveryInFlight = false

        refreshInputDevices()
        if selectedInputSource != .text {
            guard let selectedName = prepareInputDeviceSelection() else {
                transcriptionStatus = .error
                isListening = false
                logger.log("ViewModel", "startListening failed: no selectable input device")
                return
            }
            setInputDeviceNameProgrammatically(selectedName)
        }
        let shouldEnsureSystemAudioRouting =
            selectedInputSource == .systemAudio || Self.isLikelySystemAudioInputDeviceName(inputDeviceName)
        expectedSystemAudioInputDeviceName = shouldEnsureSystemAudioRouting ? inputDeviceName : nil

        proxyClient.connectTranscription(vadSilenceMs: 300)

        guard selectedInputSource != .text else {
            transcriptionStatus = .listening
            logger.log("ViewModel", "startListening text mode active")
            return
        }

        startCaptureTask?.cancel()
        captureStartSequence += 1
        let currentSequence = captureStartSequence
        startCaptureTask = Task {
            do {
                try await audioService.startCapturing(
                    preferredInputDeviceName: inputDeviceName,
                    ensureSystemAudioRouting: shouldEnsureSystemAudioRouting
                )
                guard !Task.isCancelled,
                      currentSequence == self.captureStartSequence,
                      self.isListening
                else {
                    self.logger.log("ViewModel", "startListening aborted by cancellation/stale sequence")
                    self.audioService.stopCapturing()
                    return
                }
                if shouldEnsureSystemAudioRouting {
                    let route = audioService.currentSystemAudioRouting(expectedInputName: self.expectedSystemAudioInputDeviceName)
                    outputDeviceName = route.currentOutput
                    startSystemAudioRoutingGuard()
                } else {
                    outputDeviceName = audioService.currentDefaultOutputDeviceName() ?? "不明"
                }
                transcriptionStatus = .listening
                logger.log(
                    "ViewModel",
                    "startListening success input=\(audioService.currentDefaultInputDeviceName() ?? inputDeviceName) output=\(outputDeviceName) routeGuard=\(shouldEnsureSystemAudioRouting)"
                )
                startCaptureHealthCheck()
            } catch {
                if error is CancellationError || Task.isCancelled {
                    logger.log("ViewModel", "startListening capture task cancelled")
                } else {
                    transcriptionStatus = .error
                    errorMessage = "音声取得を開始できませんでした: \(audioErrorDescription(error))"
                    isListening = false
                    proxyClient.disconnectTranscription()
                    logger.log("ViewModel", "startListening capture error: \(audioErrorDescription(error))")
                }
            }
            if currentSequence == self.captureStartSequence {
                self.startCaptureTask = nil
            }
        }
    }

    func stopListening() {
        stopListening(resetRestartState: true)
    }

    private func stopListening(resetRestartState: Bool) {
        logger.log("ViewModel", "stopListening resetRestartState=\(resetRestartState)")
        isListening = false
        startCaptureTask?.cancel()
        startCaptureTask = nil
        captureStartSequence += 1
        if resetRestartState {
            restartTask?.cancel()
            restartTask = nil
            isRestartingInputPipeline = false
        }
        captureHealthTask?.cancel()
        captureHealthTask = nil
        systemAudioRoutingGuardTask?.cancel()
        systemAudioRoutingGuardTask = nil
        expectedSystemAudioInputDeviceName = nil
        routeMismatchStreak = 0
        routeRecoveryInFlight = false
        audioService.stopCapturing()
        proxyClient.disconnectTranscription()
        transcriptionStatus = .disconnected
        generationStatus = .idle
        stage1TriggeredForCurrentBuffer = false
        streamBuffer = ""
        latestDetectedQuestion = nil
        outputDeviceName = audioService.currentDefaultOutputDeviceName() ?? "不明"
    }

    func openTestMode() {
        isTestModeVisible = true
    }

    func closeTestMode() {
        isTestModeVisible = false
    }

    func generateFromTextInput() {
        let input = testInputText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !input.isEmpty else {
            errorMessage = "テキスト質問を入力してください。"
            return
        }

        detectionStartedAt = .now
        transcript.liveTranscript = input
        transcript.provisionalQuestion = input
        transcript.finalizedQuestion = input

        let detection = detectionForManualGeneration(from: input, reason: "テキスト入力: 手動生成")

        applyDetection(detection, provisional: false)
        triggerStage1(question: detection.text, category: detection.category)
    }

    func generateFromCurrentQuestion() {
        let question = manualGenerationInputText

        guard !question.isEmpty else {
            errorMessage = "文字起こしがまだありません。"
            return
        }

        detectionStartedAt = detectionStartedAt ?? .now
        let detection = detectionForManualGeneration(from: question, reason: "手動生成: 非質問も許可")

        applyDetection(detection, provisional: false)
        triggerStage1(question: detection.text, category: detection.category)
    }

    func beginPushToTalk() {
        setSelectedInputSourceProgrammatically(.microphone)
        if let microphoneDevice = recommendedInputDeviceName(for: .microphone) {
            setInputDeviceNameProgrammatically(microphoneDevice)
        }
        startListening()
    }

    func endPushToTalk() {
        stopListening()
    }

    func copyCurrentAnswer() {
        let text = mergedAnswerText

        let pasteboard = NSPasteboard.general
        pasteboard.clearContents()
        pasteboard.setString(text, forType: .string)
    }

    func clearSession() {
        logger.log("ViewModel", "clearSession")
        transcript = TranscriptSnapshot()
        stageOutput = StageOutput()
        stage1StreamingPreview = ""
        stage2StreamingPreview = ""
        stage1Status = .idle
        stage2Status = .idle
        stage2Appending = false
        metrics = LatencyMetrics()
        audioTapBufferCount = 0
        audioFramesSent = 0
        audioSignalDetected = false
        lastAudioFrameAt = nil
        debugCategory = .unknown
        debugReason = "未検出"
        debugKeywords = []
        detectionStartedAt = nil
        stage1StartedAt = nil
        streamBuffer = ""
        latestDetectedQuestion = nil
        activeHistoryID = nil
    }

    func clearAnswerHistory() {
        logger.log("ViewModel", "clearAnswerHistory")
        answerHistory.removeAll()
    }

    func alignInputDeviceToSelectedSource() {
        outputDeviceName = audioService.currentDefaultOutputDeviceName() ?? "不明"

        guard !inputDevices.isEmpty else {
            setInputDeviceNameProgrammatically("既定の入力デバイス")
            return
        }

        switch selectedInputSource {
        case .systemAudio:
            if let recommended = recommendedInputDeviceName(for: .systemAudio) {
                setInputDeviceNameProgrammatically(recommended)
            } else if !inputDevices.contains(inputDeviceName) {
                setInputDeviceNameProgrammatically(inputDevices.first ?? "既定の入力デバイス")
            }
        case .microphone:
            if let recommended = recommendedInputDeviceName(for: .microphone),
               !inputDevices.contains(inputDeviceName) || inputDeviceName.lowercased().contains("blackhole") {
                setInputDeviceNameProgrammatically(recommended)
            } else if !inputDevices.contains(inputDeviceName) {
                setInputDeviceNameProgrammatically(inputDevices.first ?? "既定の入力デバイス")
            }
        case .text:
            break
        }
    }

    private func restartListeningIfNeeded() {
        guard isListening, !isRestartingInputPipeline else { return }
        logger.log("ViewModel", "restartListeningIfNeeded source=\(selectedInputSource.rawValue) device=\(inputDeviceName)")
        isRestartingInputPipeline = true
        stopListening(resetRestartState: false)
        restartTask?.cancel()
        restartTask = Task { @MainActor in
            try? await Task.sleep(nanoseconds: 120_000_000)
            guard !Task.isCancelled else { return }
            startListening()
            isRestartingInputPipeline = false
            restartTask = nil
            self.logger.log("ViewModel", "restartListeningIfNeeded completed")
        }
    }

    private func setSelectedInputSourceProgrammatically(_ source: InputSource) {
        guard selectedInputSource != source else { return }
        ignoreNextInputSourceChangeCount += 1
        selectedInputSource = source
    }

    private func setInputDeviceNameProgrammatically(_ deviceName: String) {
        guard inputDeviceName != deviceName else { return }
        ignoreNextInputDeviceChangeCount += 1
        inputDeviceName = deviceName
    }

    private func consumeIgnoredInputSourceChange() -> Bool {
        guard ignoreNextInputSourceChangeCount > 0 else { return false }
        ignoreNextInputSourceChangeCount -= 1
        return true
    }

    private func consumeIgnoredInputDeviceChange() -> Bool {
        guard ignoreNextInputDeviceChangeCount > 0 else { return false }
        ignoreNextInputDeviceChangeCount -= 1
        return true
    }

    var captureStatusSummary: String {
        let signal = audioSignalDetected ? "あり" : "未検出"
        return "Tap: \(audioTapBufferCount) / 送信: \(audioFramesSent) / 信号: \(signal) / 出力: \(outputDeviceName)"
    }

    var manualGenerationInputText: String {
        let candidate = transcript.finalizedQuestion.trimmingCharacters(in: .whitespacesAndNewlines)
        if !candidate.isEmpty {
            return candidate
        }
        let fallback = transcript.provisionalQuestion.trimmingCharacters(in: .whitespacesAndNewlines)
        if !fallback.isEmpty {
            return fallback
        }
        let live = transcript.liveTranscript.trimmingCharacters(in: .whitespacesAndNewlines)
        if live == "候補者の音声がここにリアルタイム表示されます" {
            return ""
        }
        return live
    }

    var manualGenerationSourceDescription: String {
        let finalized = transcript.finalizedQuestion.trimmingCharacters(in: .whitespacesAndNewlines)
        if !finalized.isEmpty {
            return "確定質問"
        }
        let provisional = transcript.provisionalQuestion.trimmingCharacters(in: .whitespacesAndNewlines)
        if !provisional.isEmpty {
            return "暫定質問"
        }
        return "文字起こしライブ"
    }

    var lastAudioFrameAgeText: String {
        guard let lastAudioFrameAt else { return "--" }
        let ageMs = Int(Date().timeIntervalSince(lastAudioFrameAt) * 1_000)
        return "\(max(ageMs, 0)) ms前"
    }

    var quickAnswerText: String {
        stageOutput.stage1?.answer_10s
            ?? stage1StreamingPreview.nonEmpty
            ?? stageOutput.stage0Template
    }

    var extendedAnswerText: String? {
        if let finalized = stageOutput.stage2?.answer_30s, !finalized.isEmpty {
            let continuation = continuationText(quick: quickAnswerText, extended: finalized)
            return continuation.nonEmpty
        }
        if let streaming = stage2StreamingPreview.nonEmpty {
            let continuation = continuationText(quick: quickAnswerText, extended: streaming)
            return continuation.nonEmpty
        }
        return nil
    }

    var appendMarkerText: String {
        "▼ ここから追記"
    }

    var mergedAnswerText: String {
        let quick = quickAnswerText
        guard let extended = extendedAnswerText else {
            return quick
        }
        return "\(quick)\n\n\(appendMarkerText)\n\(extended)"
    }

    var currentFollowups: [FollowupQA] {
        stageOutput.stage2?.followups ?? []
    }

    func continuationText(quick: String, extended: String) -> String {
        let quickTrimmed = quick.trimmingCharacters(in: .whitespacesAndNewlines)
        var extendedTrimmed = extended.trimmingCharacters(in: .whitespacesAndNewlines)

        guard !extendedTrimmed.isEmpty else { return "" }
        guard !quickTrimmed.isEmpty else { return extendedTrimmed }

        if extendedTrimmed.hasPrefix(quickTrimmed) {
            let start = extendedTrimmed.index(extendedTrimmed.startIndex, offsetBy: quickTrimmed.count)
            let tail = String(extendedTrimmed[start...])
            return trimLeadingContinuationConnector(tail)
        }

        let maxOverlap = min(quickTrimmed.count, extendedTrimmed.count)
        if maxOverlap >= 8 {
            for overlap in stride(from: maxOverlap, through: 8, by: -1) {
                let quickStart = quickTrimmed.index(quickTrimmed.endIndex, offsetBy: -overlap)
                let extendedEnd = extendedTrimmed.index(extendedTrimmed.startIndex, offsetBy: overlap)
                if quickTrimmed[quickStart...] == extendedTrimmed[..<extendedEnd] {
                    extendedTrimmed = String(extendedTrimmed[extendedEnd...])
                    break
                }
            }
        }

        return trimLeadingContinuationConnector(extendedTrimmed)
    }

    private func trimLeadingContinuationConnector(_ text: String) -> String {
        var result = text.trimmingCharacters(in: .whitespacesAndNewlines)
        let leadingConnectors = CharacterSet(charactersIn: "、。,:：;；-ー ")
        while let first = result.unicodeScalars.first, leadingConnectors.contains(first) {
            result.removeFirst()
            result = result.trimmingCharacters(in: .whitespacesAndNewlines)
        }
        return result
    }

    func addProfileFromPaste() {
        let raw = profileTextInput.trimmingCharacters(in: .whitespacesAndNewlines)
        let name = profileNameInput.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !raw.isEmpty, !name.isEmpty else {
            errorMessage = "プロファイル名と本文を入力してください。"
            return
        }

        addProfile(name: name, rawText: raw)
        profileNameInput = ""
        profileTextInput = ""
    }

    func importProfileFromFile() {
        let panel = NSOpenPanel()
        var allowedTypes: [UTType] = [.plainText, .json]
        if let markdown = UTType(filenameExtension: "md") {
            allowedTypes.append(markdown)
        }
        panel.allowedContentTypes = allowedTypes
        panel.canChooseDirectories = false
        panel.allowsMultipleSelection = false

        guard panel.runModal() == .OK, let url = panel.url else {
            return
        }

        do {
            let data = try Data(contentsOf: url)
            let text = String(data: data, encoding: .utf8) ?? ""
            let name = url.deletingPathExtension().lastPathComponent

            if url.pathExtension.lowercased() == "json",
               let jsonProfile = try? JSONDecoder().decode(CandidateProfile.self, from: data)
            {
                profiles.append(jsonProfile)
                selectedProfileID = jsonProfile.id
            } else {
                addProfile(name: name, rawText: text)
            }
            saveProfiles()
        } catch {
            errorMessage = "プロファイル読み込みに失敗しました: \(error.localizedDescription)"
        }
    }

    private func addProfile(name: String, rawText: String) {
        guard let store = profileStore else { return }
        let profile = store.importProfile(name: name, rawText: rawText)
        profiles.removeAll { $0.name == profile.name }
        profiles.append(profile)
        profiles.sort { $0.updatedAt > $1.updatedAt }
        selectedProfileID = profile.id
        saveProfiles()
    }

    private func saveProfiles() {
        do {
            try profileStore?.saveProfiles(profiles)
        } catch {
            errorMessage = "プロファイル保存に失敗しました: \(error.localizedDescription)"
        }
    }

    private func handleTranscribe(_ event: TranscribeEvent) {
        switch event {
        case .status(let status):
            logger.log("Transcribe", "status=\(status)")
            if status == "connected" {
                transcriptionStatus = .listening
            } else if status == "disconnected" {
                transcriptionStatus = .disconnected
            }
        case .delta(let delta):
            if detectionStartedAt == nil {
                detectionStartedAt = .now
            }
            streamBuffer += delta
            transcript.liveTranscript = streamBuffer

            guard let detection = detector.evaluateDelta(buffer: streamBuffer, latestDelta: delta) else {
                return
            }

            applyDetection(detection, provisional: true)
            latestDetectedQuestion = detection
            if detector.shouldEarlyCommit(detection), !stage1TriggeredForCurrentBuffer {
                stage1TriggeredForCurrentBuffer = true
                proxyClient.commitTranscription(reason: "high-confidence-delta")
                triggerStage1(question: detection.text, category: detection.category)
            }
        case .completed(let fullText):
            transcript.liveTranscript = fullText
            streamBuffer = fullText

            if let finalized = detector.finalizeQuestion(fullText) {
                applyDetection(finalized, provisional: false)
                latestDetectedQuestion = finalized
                if !stage1TriggeredForCurrentBuffer {
                    stage1TriggeredForCurrentBuffer = true
                    triggerStage1(question: finalized.text, category: finalized.category)
                }
            } else if !stage1TriggeredForCurrentBuffer,
                      let latestDetectedQuestion,
                      Date().timeIntervalSince(latestDetectedQuestion.timestamp) <= 2.0
            {
                applyDetection(latestDetectedQuestion, provisional: false)
                stage1TriggeredForCurrentBuffer = true
                debugReason = "completedが短い相槌のため、直前の質問を採用して生成"
                triggerStage1(question: latestDetectedQuestion.text, category: latestDetectedQuestion.category)
            } else {
                markSkippedNonQuestion(reason: "completed: 質問判定なしのためスキップ")
            }

            streamBuffer = ""
            detectionStartedAt = nil
            stage1TriggeredForCurrentBuffer = false
        case .committed(let text):
            transcript.finalizedQuestion = text
        case .error(let message):
            if shouldIgnoreTranscriptionError(message) {
                logger.log("Transcribe", "ignored error=\(message)")
                return
            }
            logger.log("Transcribe", "error=\(message)")
            errorMessage = message
            transcriptionStatus = .error
        }
    }

    private func applyDetection(_ detection: DetectedQuestion, provisional: Bool) {
        if let detectionStartedAt {
            metrics.detectionMs = Int(Date().timeIntervalSince(detectionStartedAt) * 1_000)
        }

        debugCategory = detection.category
        debugReason = detection.reason
        debugKeywords = detection.matchedKeywords

        stageOutput.stage0Template = templateEngine.immediateTemplate(
            for: detection.category,
            profileKeywords: selectedProfile?.keywords ?? []
        )

        if provisional {
            transcript.provisionalQuestion = detection.text
        } else {
            transcript.finalizedQuestion = detection.text
            transcript.provisionalQuestion = detection.text
        }
    }

    private func markSkippedNonQuestion(reason: String) {
        debugCategory = .unknown
        debugReason = reason
        debugKeywords = []
        transcript.provisionalQuestion = ""
    }

    private func detectionForManualGeneration(from text: String, reason: String) -> DetectedQuestion {
        if let detected = detector.finalizeQuestion(text)
            ?? detector.evaluateDelta(buffer: text, latestDelta: text)
        {
            return detected
        }

        return DetectedQuestion(
            text: text,
            category: .unknown,
            confidence: 0.55,
            matchedKeywords: [],
            reason: reason,
            timestamp: .now
        )
    }

    private func triggerStage1(question: String, category: QuestionCategory) {
        logger.log("Generation", "triggerStage1 category=\(category.rawValue) question=\(question)")
        stage1Status = .waiting
        stage2Status = .idle
        stage2Appending = false
        stage1StreamingPreview = ""
        stage2StreamingPreview = ""
        generationStatus = .connecting
        appendHistoryEntry(question: question, category: category)

        stageOutput.stage1 = nil
        stageOutput.stage2 = nil

        stage1StartedAt = .now

        let context = profileContext(for: question)
        let request = Stage1GenerateRequest(
            question: question,
            category: category,
            profile_summary: context.summary,
            profile_bullets: context.bullets,
            language: "ja"
        )

        Task {
            await proxyClient.generateStage1(
                request: request,
                onDelta: { [weak self] delta in
                    Task { @MainActor in
                        guard let self else { return }
                        if self.stage1Status == .waiting {
                            self.stage1Status = .streaming
                            self.generationStatus = .listening
                        }
                        if self.metrics.stage1FirstTokenMs == nil,
                           let startedAt = self.stage1StartedAt
                        {
                            self.metrics.stage1FirstTokenMs = Int(Date().timeIntervalSince(startedAt) * 1_000)
                        }
                        self.stage1StreamingPreview += delta
                        self.updateActiveHistory { entry in
                            entry.answer10s = self.stage1StreamingPreview
                        }
                    }
                },
                onDone: { [weak self] payload in
                    Task { @MainActor in
                        guard let self else { return }
                        self.stageOutput.stage1 = payload
                        self.stage1Status = .done
                        self.generationStatus = .idle
                        self.stage1StreamingPreview = payload.answer_10s
                        self.updateActiveHistory { entry in
                            entry.answer10s = payload.answer_10s
                        }
                        self.logger.log("Generation", "stage1 done len=\(payload.answer_10s.count)")
                        self.triggerStage2(question: question, category: category, stage1Answer: payload.answer_10s)
                    }
                },
                onError: { [weak self] message in
                    Task { @MainActor in
                        guard let self else { return }
                        self.stage1Status = .error(message)
                        self.generationStatus = .error
                        self.errorMessage = "Stage1: \(message)"
                        self.logger.log("Generation", "stage1 error=\(message)")
                    }
                }
            )
        }
    }

    private func triggerStage2(question: String, category: QuestionCategory, stage1Answer: String) {
        logger.log("Generation", "triggerStage2 category=\(category.rawValue) question=\(question)")
        stage2Status = .waiting
        stage2Appending = true
        stage2StreamingPreview = ""

        let context = profileContext(for: question)
        let request = Stage2GenerateRequest(
            question: question,
            category: category,
            stage1_answer: stage1Answer,
            profile_summary: context.summary,
            profile_bullets: context.bullets,
            language: "ja"
        )

        Task {
            await proxyClient.generateStage2(
                request: request,
                onDelta: { [weak self] delta in
                    Task { @MainActor in
                        guard let self else { return }
                        self.stage2Status = .streaming
                        self.stage2StreamingPreview += delta
                        self.updateActiveHistory { entry in
                            entry.answer30s = self.stage2StreamingPreview
                        }
                    }
                },
                onDone: { [weak self] payload in
                    Task { @MainActor in
                        guard let self else { return }
                        self.stageOutput.stage2 = payload
                        self.stage2Status = .done
                        self.stage2Appending = false
                        self.stage2StreamingPreview = payload.answer_30s
                        self.updateActiveHistory { entry in
                            entry.answer30s = payload.answer_30s
                            entry.followups = payload.followups
                        }
                        self.logger.log(
                            "Generation",
                            "stage2 done len=\(payload.answer_30s.count) followups=\(payload.followups.count)"
                        )
                    }
                },
                onError: { [weak self] message in
                    Task { @MainActor in
                        guard let self else { return }
                        self.stage2Status = .error(message)
                        self.stage2Appending = false
                        self.errorMessage = "Stage2: \(message)"
                        self.logger.log("Generation", "stage2 error=\(message)")
                    }
                }
            )
        }
    }

    private var selectedProfile: CandidateProfile? {
        profiles.first(where: { $0.id == selectedProfileID })
    }

    private func appendHistoryEntry(question: String, category: QuestionCategory) {
        let entry = AnswerHistoryEntry(
            id: UUID(),
            timestamp: .now,
            question: question,
            category: category,
            stage0Template: stageOutput.stage0Template,
            answer10s: "",
            answer30s: "",
            followups: []
        )
        answerHistory.insert(entry, at: 0)
        if answerHistory.count > 30 {
            answerHistory.removeLast(answerHistory.count - 30)
        }
        activeHistoryID = entry.id
    }

    private func updateActiveHistory(_ update: (inout AnswerHistoryEntry) -> Void) {
        guard let activeHistoryID,
              let index = answerHistory.firstIndex(where: { $0.id == activeHistoryID })
        else {
            return
        }
        update(&answerHistory[index])
    }

    private func profileContext(for question: String) -> (summary: String, bullets: [String]) {
        guard let profile = selectedProfile else {
            return ("", [])
        }

        let tokens = Set(question.lowercased().components(separatedBy: CharacterSet.whitespacesAndNewlines))
        let matched = profile.keywords.filter { keyword in
            tokens.contains(where: { $0.contains(keyword.lowercased()) || keyword.lowercased().contains($0) })
        }

        if matched.isEmpty {
            return (profile.summary, Array(profile.keywords.prefix(5)))
        }
        return (profile.summary, Array(matched.prefix(5)))
    }

    private func audioErrorDescription(_ error: Error) -> String {
        guard let audioError = error as? AudioCaptureService.AudioError else {
            return error.localizedDescription
        }

        switch audioError {
        case .permissionDenied:
            return "マイク権限が未許可です。システム設定で許可してください。"
        case .engineFailure:
            return "AVAudioEngineの起動に失敗しました。入力デバイス切替後に再試行してください。"
        case .inputDeviceNotFound(let name):
            return "入力デバイス「\(name)」が見つかりません。デバイス再取得を実行してください。"
        case .coreAudio(let status):
            return "CoreAudioのデバイス切替に失敗しました (OSStatus: \(status))"
        case .invalidInputFormat:
            return "入力フォーマットが不正です。BlackHoleのサンプルレートを48kHzに合わせて再試行してください。"
        case .routingMismatch(let currentInput, let currentOutput, let expectedInput):
            let expected = expectedInput ?? "BlackHole 2ch"
            return """
            システム音声のルーティングが安定しませんでした。\
            入力が \(expected) に固定されず、別デバイスへ戻っています。\
            （現在入力: \(currentInput), 現在出力: \(currentOutput)）
            """
        }
    }

    private func prepareInputDeviceSelection() -> String? {
        let recommended = recommendedInputDeviceName(for: selectedInputSource)

        if selectedInputSource == .systemAudio {
            guard let recommended else {
                errorMessage = "BlackHole系の入力デバイスが見つかりません。BlackHoleをインストールし、入力デバイスを再取得してください。"
                return nil
            }
            return recommended
        }

        if inputDevices.contains(inputDeviceName) {
            return inputDeviceName
        }

        return recommended ?? inputDevices.first
    }

    private func recommendedInputDeviceName(for source: InputSource) -> String? {
        guard !inputDevices.isEmpty else { return nil }

        let blackHoleCandidates = inputDevices.filter {
            let normalized = $0.lowercased()
            return normalized.contains("blackhole") || normalized.contains("loopback")
        }

        switch source {
        case .systemAudio:
            return blackHoleCandidates.first
        case .microphone:
            return inputDevices.first { device in
                let normalized = device.lowercased()
                return !normalized.contains("blackhole") && !normalized.contains("loopback")
            } ?? inputDevices.first
        case .text:
            return nil
        }
    }

    private func startCaptureHealthCheck() {
        captureHealthTask?.cancel()
        captureHealthTask = Task { [weak self] in
            try? await Task.sleep(nanoseconds: 2_500_000_000)
            guard let self else { return }
            guard self.isListening, self.selectedInputSource != .text else { return }

            let isSystemAudioInput = Self.isLikelySystemAudioInputDeviceName(self.inputDeviceName)
            let expectedSystemInput = self.expectedSystemAudioInputDeviceName ?? self.inputDeviceName

            if self.audioTapBufferCount == 0 {
                if isSystemAudioInput {
                    let route = self.audioService.currentSystemAudioRouting(expectedInputName: expectedSystemInput)
                    self.outputDeviceName = route.currentOutput
                    if !route.ok {
                        self.logger.log(
                            "CaptureHealth",
                            "system-audio route mismatch on health-check input=\(route.currentInput) output=\(route.currentOutput)"
                        )
                        await self.recoverSystemAudioRouting(reason: "health-check tap=0")
                        let afterRecovery = self.audioService.currentSystemAudioRouting(expectedInputName: expectedSystemInput)
                        self.outputDeviceName = afterRecovery.currentOutput
                        if !afterRecovery.ok, self.shouldPresentRouteAlert() {
                            self.errorMessage = self.systemAudioRouteErrorMessage(currentOutput: afterRecovery.currentOutput)
                        }
                    }
                    self.logger.log(
                        "CaptureHealth",
                        "tap=0 for system-audio input=\(self.inputDeviceName) output=\(self.outputDeviceName)"
                    )
                    return
                }
                self.errorMessage = """
                音声フレームが届いていません。入力デバイスとマイク権限を確認してください。\
                （入力: \(self.inputDeviceName), 出力: \(self.outputDeviceName)）
                """
                self.logger.log(
                    "CaptureHealth",
                    "tap=0 for microphone input=\(self.inputDeviceName) output=\(self.outputDeviceName)"
                )
                return
            }

            if self.audioFramesSent == 0 {
                if isSystemAudioInput {
                    self.logger.log(
                        "CaptureHealth",
                        "framesSent=0 for system-audio input=\(self.inputDeviceName) output=\(self.outputDeviceName)"
                    )
                    return
                }
                self.errorMessage = """
                音声変換に失敗しています。アプリを再起動し、BlackHoleのサンプルレートを48kHzに合わせてください。\
                （入力: \(self.inputDeviceName), 出力: \(self.outputDeviceName)）
                """
                self.logger.log(
                    "CaptureHealth",
                    "framesSent=0 despite tap>0 input=\(self.inputDeviceName) output=\(self.outputDeviceName)"
                )
                return
            }

            if isSystemAudioInput, !self.audioSignalDetected, !Self.isLikelySystemAudioRoute(self.outputDeviceName) {
                await self.recoverSystemAudioRouting(reason: "health-check no-signal")
                let route = self.audioService.currentSystemAudioRouting(expectedInputName: expectedSystemInput)
                self.outputDeviceName = route.currentOutput
                if !route.ok, self.shouldPresentRouteAlert() {
                    self.errorMessage = self.systemAudioRouteErrorMessage(currentOutput: route.currentOutput)
                }
                self.logger.log("CaptureHealth", "signal not detected for system audio output=\(self.outputDeviceName)")
            }
        }
    }

    private func startSystemAudioRoutingGuard() {
        systemAudioRoutingGuardTask?.cancel()
        routeMismatchStreak = 0
        systemAudioRoutingGuardTask = Task { [weak self] in
            while !Task.isCancelled {
                guard let self else { return }
                guard self.isListening else { return }

                let expectedInput = self.expectedSystemAudioInputDeviceName ?? self.inputDeviceName
                guard Self.isLikelySystemAudioInputDeviceName(expectedInput) else {
                    try? await Task.sleep(nanoseconds: 850_000_000)
                    continue
                }

                let route = self.audioService.currentSystemAudioRouting(expectedInputName: expectedInput)
                self.outputDeviceName = route.currentOutput
                if route.ok {
                    if self.routeMismatchStreak > 0 {
                        self.logger.log(
                            "RoutingGuard",
                            "route recovered input=\(route.currentInput) output=\(route.currentOutput)"
                        )
                    }
                    self.routeMismatchStreak = 0
                } else {
                    self.routeMismatchStreak += 1
                    self.logger.log(
                        "RoutingGuard",
                        "route mismatch streak=\(self.routeMismatchStreak) input=\(route.currentInput) output=\(route.currentOutput)"
                    )
                    if self.routeMismatchStreak >= 2 {
                        await self.recoverSystemAudioRouting(reason: "guard-loop")
                    }
                    if self.routeMismatchStreak >= 4, self.audioTapBufferCount == 0, self.shouldPresentRouteAlert() {
                        self.errorMessage = self.systemAudioRouteErrorMessage(currentOutput: route.currentOutput)
                    }
                }
                try? await Task.sleep(nanoseconds: 850_000_000)
            }
        }
    }

    private func recoverSystemAudioRouting(reason: String) async {
        guard !routeRecoveryInFlight else { return }
        let expectedInput = expectedSystemAudioInputDeviceName ?? inputDeviceName
        guard Self.isLikelySystemAudioInputDeviceName(expectedInput) else { return }

        routeRecoveryInFlight = true
        defer { routeRecoveryInFlight = false }
        logger.log(
            "RoutingGuard",
            "recover begin reason=\(reason) expectedInput=\(expectedInput) currentOutput=\(outputDeviceName)"
        )
        do {
            let route = try await audioService.enforceSystemAudioRouting(preferredInputDeviceName: expectedInput)
            outputDeviceName = route.currentOutput
            if route.ok {
                routeMismatchStreak = 0
            }
            logger.log(
                "RoutingGuard",
                "recover end reason=\(reason) ok=\(route.ok) input=\(route.currentInput) output=\(route.currentOutput)"
            )
        } catch {
            logger.log("RoutingGuard", "recover failed reason=\(reason) error=\(audioErrorDescription(error))")
        }
    }

    private func shouldPresentRouteAlert() -> Bool {
        let now = Date()
        let cooldown: TimeInterval = 10
        guard now.timeIntervalSince(lastRouteAlertAt) >= cooldown else {
            return false
        }
        lastRouteAlertAt = now
        return true
    }

    private func systemAudioRouteErrorMessage(currentOutput: String) -> String {
        """
        システム音声の出力先が適切ではありません。\
        出力を複数出力装置/BlackHoleにしてください。\
        （現在の出力: \(currentOutput)）
        """
    }

    private static func containsAudibleSamples(_ data: Data) -> Bool {
        guard data.count >= 2 else { return false }
        var index = data.startIndex
        while index < data.endIndex {
            let next = data.index(after: index)
            if next >= data.endIndex { break }
            let low = Int16(data[index])
            let high = Int16(Int8(bitPattern: data[next])) << 8
            let sample = high | low
            if abs(Int(sample)) > 64 {
                return true
            }
            index = data.index(index, offsetBy: 2)
        }
        return false
    }

    private static func isLikelySystemAudioRoute(_ outputDeviceName: String) -> Bool {
        let normalized = outputDeviceName.lowercased()
        return normalized.contains("複数出力")
            || normalized.contains("multi-output")
            || normalized.contains("blackhole")
            || normalized.contains("loopback")
    }

    private static func isLikelySystemAudioInputDeviceName(_ inputDeviceName: String) -> Bool {
        let normalized = inputDeviceName.lowercased()
        return normalized.contains("blackhole") || normalized.contains("loopback")
    }

    private func shouldIgnoreTranscriptionError(_ message: String) -> Bool {
        let normalized = message.lowercased()
        if !isListening && normalized.contains("socket is not connected") {
            return true
        }
        return normalized.contains("socket is not connected")
            || normalized.contains("cancelled")
            || normalized.contains("canceled")
            || normalized.contains("socket is closed")
    }

    func copyRuntimeLogPath() {
        let pasteboard = NSPasteboard.general
        pasteboard.clearContents()
        pasteboard.setString(runtimeLogPath, forType: .string)
        logger.log("ViewModel", "runtime log path copied")
    }

    func openRuntimeLogFolder() {
        NSWorkspace.shared.selectFile(runtimeLogPath, inFileViewerRootedAtPath: "")
        logger.log("ViewModel", "runtime log folder opened")
    }

    func clearRuntimeLog() {
        logger.clear()
        logger.log("ViewModel", "runtime log cleared")
    }
}

private extension String {
    var nonEmpty: String? {
        isEmpty ? nil : self
    }
}

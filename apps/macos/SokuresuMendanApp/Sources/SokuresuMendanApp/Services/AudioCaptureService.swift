import AVFoundation
import CoreAudio
import Foundation

final class AudioCaptureService {
    enum AudioError: Error {
        case permissionDenied
        case engineFailure
        case inputDeviceNotFound(String)
        case coreAudio(OSStatus)
        case invalidInputFormat
        case routingMismatch(currentInput: String, currentOutput: String, expectedInput: String?)
    }

    struct SystemAudioRoutingState {
        let currentInput: String
        let currentOutput: String
        let inputMatched: Bool
        let outputRoutable: Bool

        var ok: Bool {
            inputMatched && outputRoutable
        }
    }

    private var engine: AVAudioEngine?
    private(set) var isRunning = false
    var onAudioFrame: ((Data) -> Void)?
    var onTapBuffer: (() -> Void)?
    private var previousDefaultInputDeviceID: AudioObjectID?
    private var changedDefaultInputDevice = false
    private var previousDefaultOutputDeviceID: AudioObjectID?
    private var changedDefaultOutputDevice = false
    private var previousDefaultSystemOutputDeviceID: AudioObjectID?
    private var changedDefaultSystemOutputDevice = false
    private var converter: AVAudioConverter?
    private var converterSourceFormatKey = ""
    private let logger = AppRuntimeLogger.shared
    private var tapBufferCount = 0

    func availableInputDeviceNames() -> [String] {
        (try? inputDeviceInfos().map(\.name)) ?? []
    }

    func startCapturing(preferredInputDeviceName: String?, ensureSystemAudioRouting: Bool = false) async throws {
        logger.log(
            "AudioCapture",
            "startCapturing begin preferredInput=\(preferredInputDeviceName ?? "nil") ensureSystemAudioRouting=\(ensureSystemAudioRouting)"
        )
        logCurrentAudioDevices(label: "before-start")
        try Task.checkCancellation()
        guard await requestPermission() else {
            logger.log("AudioCapture", "microphone permission denied")
            throw AudioError.permissionDenied
        }
        try Task.checkCancellation()
        logger.log("AudioCapture", "microphone permission granted")

        stopCapturing()
        tapBufferCount = 0
        try Task.checkCancellation()

        do {
            try await configureDefaultDevices(
                preferredInputDeviceName: preferredInputDeviceName,
                ensureSystemAudioRouting: ensureSystemAudioRouting
            )
            try Task.checkCancellation()
            try startEngine()
            logCurrentAudioDevices(label: "after-start")

            if ensureSystemAudioRouting {
                let firstValidation = validateSystemAudioRouting(expectedInputName: preferredInputDeviceName)
                if !firstValidation.ok {
                    logger.log(
                        "AudioCapture",
                        "routing mismatch after-start input=\(firstValidation.currentInput) output=\(firstValidation.currentOutput), retrying once"
                    )

                    teardownEngineWithoutRestoringDefaults()
                    tapBufferCount = 0

                    try await configureDefaultDevices(
                        preferredInputDeviceName: preferredInputDeviceName,
                        ensureSystemAudioRouting: true
                    )
                    try Task.checkCancellation()
                    try startEngine()
                    logCurrentAudioDevices(label: "after-retry-start")

                    let secondValidation = validateSystemAudioRouting(expectedInputName: preferredInputDeviceName)
                    if !secondValidation.ok {
                        logger.log(
                            "AudioCapture",
                            "routing mismatch retry failed input=\(secondValidation.currentInput) output=\(secondValidation.currentOutput); continue and recover in background"
                        )
                    }
                }
            }
        } catch {
            teardownEngineWithoutRestoringDefaults()
            restoreDefaultInputDeviceIfNeeded()
            restoreDefaultOutputDeviceIfNeeded()
            restoreDefaultSystemOutputDeviceIfNeeded()
            throw error
        }
    }

    func stopCapturing() {
        logger.log(
            "AudioCapture",
            "stopCapturing running=\(isRunning) tapCount=\(tapBufferCount) changedInput=\(changedDefaultInputDevice) changedOutput=\(changedDefaultOutputDevice)"
        )
        engine?.inputNode.removeTap(onBus: 0)
        engine?.stop()
        engine = nil
        converter = nil
        converterSourceFormatKey = ""
        isRunning = false
        tapBufferCount = 0
        restoreDefaultInputDeviceIfNeeded()
        restoreDefaultOutputDeviceIfNeeded()
        restoreDefaultSystemOutputDeviceIfNeeded()
        logCurrentAudioDevices(label: "after-stop")
    }

    func currentDefaultOutputDeviceName() -> String? {
        guard let deviceID = try? defaultOutputDeviceID() else {
            return nil
        }
        return deviceName(deviceID: deviceID)
    }

    func currentDefaultInputDeviceName() -> String? {
        guard let deviceID = try? defaultInputDeviceID() else {
            return nil
        }
        return deviceName(deviceID: deviceID)
    }

    func currentSystemAudioRouting(expectedInputName: String?) -> SystemAudioRoutingState {
        let validation = validateSystemAudioRouting(expectedInputName: expectedInputName)
        return SystemAudioRoutingState(
            currentInput: validation.currentInput,
            currentOutput: validation.currentOutput,
            inputMatched: validation.inputOK,
            outputRoutable: validation.outputOK
        )
    }

    func enforceSystemAudioRouting(preferredInputDeviceName: String?) async throws -> SystemAudioRoutingState {
        try Task.checkCancellation()
        try await configureDefaultDevices(
            preferredInputDeviceName: preferredInputDeviceName,
            ensureSystemAudioRouting: true
        )
        try Task.checkCancellation()
        try? await Task.sleep(nanoseconds: 180_000_000)
        return currentSystemAudioRouting(expectedInputName: preferredInputDeviceName)
    }

    private func requestPermission() async -> Bool {
        await withCheckedContinuation { continuation in
            AVCaptureDevice.requestAccess(for: .audio) { granted in
                continuation.resume(returning: granted)
            }
        }
    }

    private func configureDefaultDevices(
        preferredInputDeviceName: String?,
        ensureSystemAudioRouting: Bool
    ) async throws {
        if ensureSystemAudioRouting {
            logger.log("AudioCapture", "switching default output for system audio")
            try switchDefaultOutputDeviceForSystemAudioIfNeeded()
            logger.log("AudioCapture", "default output routing switched")
        }

        if let preferredInputDeviceName, !preferredInputDeviceName.isEmpty {
            logger.log("AudioCapture", "switching default input to \(preferredInputDeviceName)")
            try switchDefaultInputDeviceIfNeeded(to: preferredInputDeviceName)
            try? await Task.sleep(nanoseconds: 180_000_000)
            logger.log("AudioCapture", "default input switch completed")
        }
    }

    private func startEngine() throws {
        let engine = AVAudioEngine()
        self.engine = engine

        let inputNode = engine.inputNode
        let tapFormat = inputNode.outputFormat(forBus: 0)
        logger.log(
            "AudioCapture",
            "tap format output(sr=\(tapFormat.sampleRate),ch=\(tapFormat.channelCount))"
        )
        guard tapFormat.sampleRate > 0, tapFormat.channelCount > 0 else {
            logger.log("AudioCapture", "invalid input format")
            throw AudioError.invalidInputFormat
        }
        inputNode.removeTap(onBus: 0)
        // formatをnilにしてデバイス確定後の実フォーマットに追従させると、再起動直後のformat不一致クラッシュを避けやすい。
        inputNode.installTap(onBus: 0, bufferSize: 1_024, format: nil) { [weak self] buffer, _ in
            guard let self else { return }
            guard buffer.frameLength > 0 else { return }
            self.tapBufferCount += 1
            if self.tapBufferCount == 1 || self.tapBufferCount == 50 || self.tapBufferCount % 500 == 0 {
                self.logger.log(
                    "AudioCapture",
                    "tap buffer received count=\(self.tapBufferCount) frameLength=\(buffer.frameLength) sampleRate=\(buffer.format.sampleRate)"
                )
            }
            self.onTapBuffer?()
            if let pcm16 = self.toRealtimePCM16(buffer: buffer) {
                self.onAudioFrame?(pcm16)
            }
        }

        engine.prepare()
        do {
            try engine.start()
            isRunning = true
            logger.log("AudioCapture", "engine started running=\(engine.isRunning)")
        } catch {
            inputNode.removeTap(onBus: 0)
            logger.log("AudioCapture", "engine start failed: \(error.localizedDescription)")
            throw AudioError.engineFailure
        }
    }

    private func teardownEngineWithoutRestoringDefaults() {
        engine?.inputNode.removeTap(onBus: 0)
        engine?.stop()
        engine = nil
        converter = nil
        converterSourceFormatKey = ""
        isRunning = false
    }

    private func validateSystemAudioRouting(
        expectedInputName: String?
    ) -> (ok: Bool, currentInput: String, currentOutput: String, inputOK: Bool, outputOK: Bool) {
        let output = currentDefaultOutputDeviceName() ?? "不明"
        let input = currentDefaultInputDeviceName() ?? "不明"
        let outputOK = isSystemAudioRoutableOutput(name: output)

        let inputOK: Bool
        if let expectedInputName, !expectedInputName.isEmpty {
            let expectedLower = expectedInputName.lowercased()
            let inputLower = input.lowercased()
            inputOK = inputLower.contains(expectedLower) || expectedLower.contains(inputLower)
        } else {
            inputOK = true
        }

        return (outputOK && inputOK, input, output, inputOK, outputOK)
    }

    private func toRealtimePCM16(buffer: AVAudioPCMBuffer) -> Data? {
        if let converted = convertToTargetPCM16(buffer: buffer) {
            return converted
        }
        return toPCM16Fallback(buffer: buffer)
    }

    private func convertToTargetPCM16(buffer: AVAudioPCMBuffer) -> Data? {
        guard let targetFormat = AVAudioFormat(
            commonFormat: .pcmFormatFloat32,
            sampleRate: 24_000,
            channels: 1,
            interleaved: false
        ) else {
            return nil
        }

        let sourceFormat = buffer.format
        let sourceKey = formatKey(sourceFormat)
        if converter == nil || converterSourceFormatKey != sourceKey {
            converter = AVAudioConverter(from: sourceFormat, to: targetFormat)
            converterSourceFormatKey = sourceKey
        }
        guard let converter else { return nil }

        let estimatedFrames = max(
            1,
            Int((Double(buffer.frameLength) * targetFormat.sampleRate / sourceFormat.sampleRate).rounded(.up))
        )
        guard let outputBuffer = AVAudioPCMBuffer(
            pcmFormat: targetFormat,
            frameCapacity: AVAudioFrameCount(estimatedFrames)
        ) else {
            return nil
        }

        var conversionError: NSError?
        var didProvideInput = false
        let status = converter.convert(to: outputBuffer, error: &conversionError) { _, outStatus in
            if didProvideInput {
                outStatus.pointee = .noDataNow
                return nil
            }
            didProvideInput = true
            outStatus.pointee = .haveData
            return buffer
        }

        guard conversionError == nil else { return nil }
        guard status == .haveData || status == .inputRanDry || status == .endOfStream else { return nil }

        let frameLength = Int(outputBuffer.frameLength)
        guard frameLength > 0, let channelData = outputBuffer.floatChannelData?[0] else {
            return nil
        }

        var data = Data(capacity: frameLength * MemoryLayout<Int16>.size)
        for frame in 0..<frameLength {
            let sample = channelData[frame]
            let clamped = max(-1.0, min(1.0, sample))
            var intSample = Int16(clamped * Float(Int16.max))
            withUnsafeBytes(of: &intSample) { bytes in
                data.append(contentsOf: bytes)
            }
        }
        return data
    }

    private func toPCM16Fallback(buffer: AVAudioPCMBuffer) -> Data? {
        let channels = Int(buffer.format.channelCount)
        let frameLength = Int(buffer.frameLength)
        guard channels > 0, frameLength > 0 else { return nil }

        var data = Data(capacity: frameLength * MemoryLayout<Int16>.size)
        if let channelData = buffer.floatChannelData {
            for frame in 0..<frameLength {
                let sample = channelData[0][frame]
                let clamped = max(-1.0, min(1.0, sample))
                var intSample = Int16(clamped * Float(Int16.max))
                withUnsafeBytes(of: &intSample) { bytes in
                    data.append(contentsOf: bytes)
                }
            }
            return data
        }

        if let channelData = buffer.int16ChannelData {
            for frame in 0..<frameLength {
                var intSample = channelData[0][frame]
                withUnsafeBytes(of: &intSample) { bytes in
                    data.append(contentsOf: bytes)
                }
            }
            return data
        }

        if let channelData = buffer.int32ChannelData {
            for frame in 0..<frameLength {
                let value = channelData[0][frame] >> 16
                var intSample = Int16(clamping: value)
                withUnsafeBytes(of: &intSample) { bytes in
                    data.append(contentsOf: bytes)
                }
            }
            return data
        }

        return nil
    }

    private struct InputDeviceInfo {
        let id: AudioObjectID
        let name: String
    }

    private func inputDeviceInfos() throws -> [InputDeviceInfo] {
        let deviceIDs = try allDeviceIDs()
        return deviceIDs.compactMap { id in
            guard hasInputChannel(deviceID: id) else { return nil }
            return InputDeviceInfo(id: id, name: deviceName(deviceID: id))
        }
    }

    private func allDeviceIDs() throws -> [AudioObjectID] {
        var propertyAddress = AudioObjectPropertyAddress(
            mSelector: kAudioHardwarePropertyDevices,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain
        )

        var dataSize: UInt32 = 0
        var status = AudioObjectGetPropertyDataSize(
            AudioObjectID(kAudioObjectSystemObject),
            &propertyAddress,
            0,
            nil,
            &dataSize
        )
        guard status == noErr else {
            throw AudioError.coreAudio(status)
        }

        let count = Int(dataSize) / MemoryLayout<AudioObjectID>.size
        var deviceIDs = Array(repeating: AudioObjectID(0), count: count)
        status = AudioObjectGetPropertyData(
            AudioObjectID(kAudioObjectSystemObject),
            &propertyAddress,
            0,
            nil,
            &dataSize,
            &deviceIDs
        )
        guard status == noErr else {
            throw AudioError.coreAudio(status)
        }
        return deviceIDs
    }

    private func hasInputChannel(deviceID: AudioObjectID) -> Bool {
        var propertyAddress = AudioObjectPropertyAddress(
            mSelector: kAudioDevicePropertyStreamConfiguration,
            mScope: kAudioObjectPropertyScopeInput,
            mElement: kAudioObjectPropertyElementMain
        )

        var dataSize: UInt32 = 0
        let sizeStatus = AudioObjectGetPropertyDataSize(deviceID, &propertyAddress, 0, nil, &dataSize)
        guard sizeStatus == noErr else { return false }

        let rawBuffer = UnsafeMutableRawPointer.allocate(
            byteCount: Int(dataSize),
            alignment: MemoryLayout<AudioBufferList>.alignment
        )
        defer { rawBuffer.deallocate() }

        let dataStatus = AudioObjectGetPropertyData(deviceID, &propertyAddress, 0, nil, &dataSize, rawBuffer)
        guard dataStatus == noErr else { return false }

        let audioBufferList = rawBuffer.bindMemory(to: AudioBufferList.self, capacity: 1)
        let buffers = UnsafeMutableAudioBufferListPointer(audioBufferList)
        let channels = buffers.reduce(0) { partial, buffer in
            partial + Int(buffer.mNumberChannels)
        }
        return channels > 0
    }

    private func hasOutputChannel(deviceID: AudioObjectID) -> Bool {
        var propertyAddress = AudioObjectPropertyAddress(
            mSelector: kAudioDevicePropertyStreamConfiguration,
            mScope: kAudioObjectPropertyScopeOutput,
            mElement: kAudioObjectPropertyElementMain
        )

        var dataSize: UInt32 = 0
        let sizeStatus = AudioObjectGetPropertyDataSize(deviceID, &propertyAddress, 0, nil, &dataSize)
        guard sizeStatus == noErr else { return false }

        let rawBuffer = UnsafeMutableRawPointer.allocate(
            byteCount: Int(dataSize),
            alignment: MemoryLayout<AudioBufferList>.alignment
        )
        defer { rawBuffer.deallocate() }

        let dataStatus = AudioObjectGetPropertyData(deviceID, &propertyAddress, 0, nil, &dataSize, rawBuffer)
        guard dataStatus == noErr else { return false }

        let audioBufferList = rawBuffer.bindMemory(to: AudioBufferList.self, capacity: 1)
        let buffers = UnsafeMutableAudioBufferListPointer(audioBufferList)
        let channels = buffers.reduce(0) { partial, buffer in
            partial + Int(buffer.mNumberChannels)
        }
        return channels > 0
    }

    private func deviceName(deviceID: AudioObjectID) -> String {
        var propertyAddress = AudioObjectPropertyAddress(
            mSelector: kAudioObjectPropertyName,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain
        )

        var name: CFString = "" as CFString
        var dataSize = UInt32(MemoryLayout<CFString>.size)
        let status = withUnsafeMutablePointer(to: &name) { pointer in
            AudioObjectGetPropertyData(
                deviceID,
                &propertyAddress,
                0,
                nil,
                &dataSize,
                pointer
            )
        }
        guard status == noErr else {
            return "Unknown Device \(deviceID)"
        }
        return name as String
    }

    private func switchDefaultInputDeviceIfNeeded(to preferredName: String) throws {
        let normalizedPreferred = preferredName.lowercased()
        let devices = try inputDeviceInfos()

        let target = devices.first { $0.name.caseInsensitiveCompare(preferredName) == .orderedSame }
            ?? devices.first { $0.name.lowercased().contains(normalizedPreferred) }

        guard let target else {
            logger.log("AudioCapture", "preferred input not found: \(preferredName)")
            throw AudioError.inputDeviceNotFound(preferredName)
        }

        let current = try defaultInputDeviceID()
        previousDefaultInputDeviceID = current

        guard current != target.id else {
            changedDefaultInputDevice = false
            logger.log("AudioCapture", "default input already target=\(target.name)")
            return
        }

        try setDefaultInputDeviceID(target.id)
        if let applied = try? defaultInputDeviceID() {
            logger.log(
                "AudioCapture",
                "set default input current=\(deviceName(deviceID: current)) target=\(target.name) applied=\(deviceName(deviceID: applied))"
            )
        }
        changedDefaultInputDevice = true
    }

    private func switchDefaultOutputDeviceForSystemAudioIfNeeded() throws {
        let devices = try outputDeviceInfos()
        guard let currentOutputID = try? defaultOutputDeviceID() else {
            return
        }
        let currentSystemOutputID = try? defaultSystemOutputDeviceID()

        let currentName = deviceName(deviceID: currentOutputID)
        if isSystemAudioRoutableOutput(name: currentName) {
            changedDefaultOutputDevice = false
            previousDefaultOutputDeviceID = nil
            changedDefaultSystemOutputDevice = false
            previousDefaultSystemOutputDeviceID = nil
            return
        }

        let target = preferredSystemAudioOutput(from: devices)
        guard let target, target.id != currentOutputID else {
            return
        }

        previousDefaultOutputDeviceID = currentOutputID
        try setDefaultOutputDeviceID(target.id)
        if let applied = try? defaultOutputDeviceID() {
            logger.log(
                "AudioCapture",
                "set default output current=\(currentName) target=\(target.name) applied=\(deviceName(deviceID: applied))"
            )
        }
        changedDefaultOutputDevice = true

        if let currentSystemOutputID, currentSystemOutputID != target.id {
            previousDefaultSystemOutputDeviceID = currentSystemOutputID
            try? setDefaultSystemOutputDeviceID(target.id)
            if let appliedSystem = try? defaultSystemOutputDeviceID() {
                logger.log(
                    "AudioCapture",
                    "set default system output target=\(target.name) applied=\(deviceName(deviceID: appliedSystem))"
                )
            }
            changedDefaultSystemOutputDevice = true
        } else {
            changedDefaultSystemOutputDevice = false
            previousDefaultSystemOutputDeviceID = nil
        }
    }

    private func restoreDefaultInputDeviceIfNeeded() {
        guard changedDefaultInputDevice, let previous = previousDefaultInputDeviceID else {
            return
        }
        logger.log("AudioCapture", "restoring default input device")
        try? setDefaultInputDeviceID(previous)
        changedDefaultInputDevice = false
        previousDefaultInputDeviceID = nil
    }

    private func restoreDefaultOutputDeviceIfNeeded() {
        guard changedDefaultOutputDevice, let previous = previousDefaultOutputDeviceID else {
            return
        }
        logger.log("AudioCapture", "restoring default output device")
        try? setDefaultOutputDeviceID(previous)
        changedDefaultOutputDevice = false
        previousDefaultOutputDeviceID = nil
    }

    private func restoreDefaultSystemOutputDeviceIfNeeded() {
        guard changedDefaultSystemOutputDevice, let previous = previousDefaultSystemOutputDeviceID else {
            return
        }
        logger.log("AudioCapture", "restoring default system output device")
        try? setDefaultSystemOutputDeviceID(previous)
        changedDefaultSystemOutputDevice = false
        previousDefaultSystemOutputDeviceID = nil
    }

    private func defaultInputDeviceID() throws -> AudioObjectID {
        var propertyAddress = AudioObjectPropertyAddress(
            mSelector: kAudioHardwarePropertyDefaultInputDevice,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain
        )

        var deviceID: AudioObjectID = 0
        var dataSize = UInt32(MemoryLayout<AudioObjectID>.size)
        let status = AudioObjectGetPropertyData(
            AudioObjectID(kAudioObjectSystemObject),
            &propertyAddress,
            0,
            nil,
            &dataSize,
            &deviceID
        )
        guard status == noErr else {
            throw AudioError.coreAudio(status)
        }
        return deviceID
    }

    private func setDefaultInputDeviceID(_ deviceID: AudioObjectID) throws {
        var propertyAddress = AudioObjectPropertyAddress(
            mSelector: kAudioHardwarePropertyDefaultInputDevice,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain
        )
        var mutableDeviceID = deviceID
        let dataSize = UInt32(MemoryLayout<AudioObjectID>.size)
        let status = AudioObjectSetPropertyData(
            AudioObjectID(kAudioObjectSystemObject),
            &propertyAddress,
            0,
            nil,
            dataSize,
            &mutableDeviceID
        )
        guard status == noErr else {
            throw AudioError.coreAudio(status)
        }
    }

    private func outputDeviceInfos() throws -> [InputDeviceInfo] {
        let deviceIDs = try allDeviceIDs()
        return deviceIDs.compactMap { id in
            guard hasOutputChannel(deviceID: id) else { return nil }
            return InputDeviceInfo(id: id, name: deviceName(deviceID: id))
        }
    }

    private func defaultOutputDeviceID() throws -> AudioObjectID {
        var propertyAddress = AudioObjectPropertyAddress(
            mSelector: kAudioHardwarePropertyDefaultOutputDevice,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain
        )

        var deviceID: AudioObjectID = 0
        var dataSize = UInt32(MemoryLayout<AudioObjectID>.size)
        let status = AudioObjectGetPropertyData(
            AudioObjectID(kAudioObjectSystemObject),
            &propertyAddress,
            0,
            nil,
            &dataSize,
            &deviceID
        )
        guard status == noErr else {
            throw AudioError.coreAudio(status)
        }
        return deviceID
    }

    private func setDefaultOutputDeviceID(_ deviceID: AudioObjectID) throws {
        var propertyAddress = AudioObjectPropertyAddress(
            mSelector: kAudioHardwarePropertyDefaultOutputDevice,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain
        )
        var mutableDeviceID = deviceID
        let dataSize = UInt32(MemoryLayout<AudioObjectID>.size)
        let status = AudioObjectSetPropertyData(
            AudioObjectID(kAudioObjectSystemObject),
            &propertyAddress,
            0,
            nil,
            dataSize,
            &mutableDeviceID
        )
        guard status == noErr else {
            throw AudioError.coreAudio(status)
        }
    }

    private func defaultSystemOutputDeviceID() throws -> AudioObjectID {
        var propertyAddress = AudioObjectPropertyAddress(
            mSelector: kAudioHardwarePropertyDefaultSystemOutputDevice,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain
        )

        var deviceID: AudioObjectID = 0
        var dataSize = UInt32(MemoryLayout<AudioObjectID>.size)
        let status = AudioObjectGetPropertyData(
            AudioObjectID(kAudioObjectSystemObject),
            &propertyAddress,
            0,
            nil,
            &dataSize,
            &deviceID
        )
        guard status == noErr else {
            throw AudioError.coreAudio(status)
        }
        return deviceID
    }

    private func setDefaultSystemOutputDeviceID(_ deviceID: AudioObjectID) throws {
        var propertyAddress = AudioObjectPropertyAddress(
            mSelector: kAudioHardwarePropertyDefaultSystemOutputDevice,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain
        )
        var mutableDeviceID = deviceID
        let dataSize = UInt32(MemoryLayout<AudioObjectID>.size)
        let status = AudioObjectSetPropertyData(
            AudioObjectID(kAudioObjectSystemObject),
            &propertyAddress,
            0,
            nil,
            dataSize,
            &mutableDeviceID
        )
        guard status == noErr else {
            throw AudioError.coreAudio(status)
        }
    }

    private func preferredSystemAudioOutput(from devices: [InputDeviceInfo]) -> InputDeviceInfo? {
        let prioritizedMulti = devices.first { device in
            let normalized = device.name.lowercased()
            return normalized.contains("複数出力") || normalized.contains("multi-output")
        }
        if let prioritizedMulti {
            return prioritizedMulti
        }
        return devices.first { device in
            let normalized = device.name.lowercased()
            return normalized.contains("blackhole") || normalized.contains("loopback")
        }
    }

    private func isSystemAudioRoutableOutput(name: String) -> Bool {
        let normalized = name.lowercased()
        return normalized.contains("複数出力")
            || normalized.contains("multi-output")
            || normalized.contains("blackhole")
            || normalized.contains("loopback")
    }

    private func formatKey(_ format: AVAudioFormat) -> String {
        "\(format.sampleRate)-\(format.channelCount)-\(format.commonFormat.rawValue)-\(format.isInterleaved)"
    }

    private func logCurrentAudioDevices(label: String) {
        let input = (try? defaultInputDeviceID()).map(deviceName(deviceID:)) ?? "unknown"
        let output = (try? defaultOutputDeviceID()).map(deviceName(deviceID:)) ?? "unknown"
        let systemOutput = (try? defaultSystemOutputDeviceID()).map(deviceName(deviceID:)) ?? "unknown"
        let inputs = availableInputDeviceNames().joined(separator: ", ")
        logger.log(
            "AudioCapture",
            "\(label) defaultInput=\(input) defaultOutput=\(output) defaultSystemOutput=\(systemOutput) availableInputs=[\(inputs)]"
        )
    }
}

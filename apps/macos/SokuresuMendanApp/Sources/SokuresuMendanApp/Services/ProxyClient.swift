import Foundation

final class ProxyClient {
    private let session: URLSession
    private let baseURL: URL

    private var websocketTask: URLSessionWebSocketTask?
    private var receiveTask: Task<Void, Never>?
    private var isDisconnectingTranscription = false
    private let logger = AppRuntimeLogger.shared

    var onTranscribeEvent: ((TranscribeEvent) -> Void)?

    init(baseURL: URL = URL(string: "http://127.0.0.1:39871")!) {
        let configuration = URLSessionConfiguration.default
        configuration.timeoutIntervalForRequest = 30
        configuration.httpShouldUsePipelining = true
        configuration.httpMaximumConnectionsPerHost = 6
        configuration.requestCachePolicy = .reloadIgnoringLocalAndRemoteCacheData
        self.session = URLSession(configuration: configuration)
        self.baseURL = baseURL
    }

    func checkHealth() async -> Bool {
        var request = URLRequest(url: baseURL.appending(path: "health"))
        request.timeoutInterval = 2

        do {
            let (data, response) = try await session.data(for: request)
            guard let http = response as? HTTPURLResponse, http.statusCode == 200 else {
                return false
            }
            let health = try JSONDecoder().decode(ProxyHealth.self, from: data)
            return health.ok
        } catch {
            return false
        }
    }

    func connectTranscription(vadSilenceMs: Int = 350) {
        guard websocketTask == nil else {
            logger.log("ProxyClient", "connectTranscription skipped (already connected)")
            return
        }
        isDisconnectingTranscription = false
        logger.log("ProxyClient", "connectTranscription begin vadSilenceMs=\(vadSilenceMs)")

        var components = URLComponents(url: baseURL, resolvingAgainstBaseURL: false)
        components?.scheme = "ws"
        components?.path = "/ws/transcribe"

        guard let url = components?.url else {
            onTranscribeEvent?(.error("WS URLを作れませんでした。"))
            logger.log("ProxyClient", "WS URL build failed")
            return
        }

        let task = session.webSocketTask(with: url)
        websocketTask = task
        task.resume()
        logger.log("ProxyClient", "websocket resume url=\(url.absoluteString)")

        let config: [String: Any] = [
            "type": "config",
            "server_vad": [
                "silence_duration_ms": vadSilenceMs,
                "prefix_padding_ms": 200
            ]
        ]
        Task { [weak self] in
            // URLSessionWebSocketTaskはresume直後にsendすると失敗しやすいため、短い待機後に送る。
            try? await Task.sleep(nanoseconds: 150_000_000)
            guard let self else { return }
            self.sendWebSocketJSON(config)
        }

        receiveTask = Task { [weak self] in
            await self?.receiveLoop()
        }

        onTranscribeEvent?(.status("connected"))
        logger.log("ProxyClient", "transcription status connected")
    }

    func disconnectTranscription() {
        isDisconnectingTranscription = true
        logger.log("ProxyClient", "disconnectTranscription")
        receiveTask?.cancel()
        receiveTask = nil
        websocketTask?.cancel(with: .goingAway, reason: nil)
        websocketTask = nil
        onTranscribeEvent?(.status("disconnected"))
    }

    func sendAudioFrame(_ data: Data) {
        let payload: [String: Any] = [
            "type": "audio",
            "audio": data.base64EncodedString()
        ]
        sendWebSocketJSON(payload)
    }

    func commitTranscription(reason: String = "early-question") {
        let payload: [String: Any] = [
            "type": "commit",
            "reason": reason
        ]
        sendWebSocketJSON(payload)
    }

    func sendTextProbe(_ text: String) {
        let payload: [String: Any] = [
            "type": "text_probe",
            "text": text
        ]
        sendWebSocketJSON(payload)
    }

    func generateStage1(
        request body: Stage1GenerateRequest,
        onDelta: @escaping (String) -> Void,
        onDone: @escaping (Stage1Payload) -> Void,
        onError: @escaping (String) -> Void
    ) async {
        do {
            var request = URLRequest(url: baseURL.appending(path: "generate-stage1"))
            request.httpMethod = "POST"
            request.setValue("application/json", forHTTPHeaderField: "Content-Type")
            request.httpBody = try JSONEncoder().encode(body)

            let (bytes, response) = try await session.bytes(for: request)
            guard let http = response as? HTTPURLResponse, http.statusCode == 200 else {
                onError("Stage1 APIエラー")
                return
            }

            for try await line in bytes.lines {
                guard !line.isEmpty else { continue }
                guard let data = line.data(using: .utf8) else { continue }
                let event = try JSONDecoder().decode(StageStreamEvent<Stage1Payload>.self, from: data)
                switch event.type {
                case "delta":
                    if let delta = event.delta {
                        onDelta(delta)
                    }
                case "done":
                    if let result = event.result {
                        onDone(result)
                    }
                case "error":
                    onError(event.error ?? "Stage1生成エラー")
                default:
                    break
                }
            }
        } catch {
            onError(error.localizedDescription)
        }
    }

    func generateStage2(
        request body: Stage2GenerateRequest,
        onDelta: @escaping (String) -> Void,
        onDone: @escaping (Stage2Payload) -> Void,
        onError: @escaping (String) -> Void
    ) async {
        do {
            var request = URLRequest(url: baseURL.appending(path: "generate-stage2"))
            request.httpMethod = "POST"
            request.setValue("application/json", forHTTPHeaderField: "Content-Type")
            request.httpBody = try JSONEncoder().encode(body)

            let (bytes, response) = try await session.bytes(for: request)
            guard let http = response as? HTTPURLResponse, http.statusCode == 200 else {
                onError("Stage2 APIエラー")
                return
            }

            for try await line in bytes.lines {
                guard !line.isEmpty else { continue }
                guard let data = line.data(using: .utf8) else { continue }
                let event = try JSONDecoder().decode(StageStreamEvent<Stage2Payload>.self, from: data)
                switch event.type {
                case "delta":
                    if let delta = event.delta {
                        onDelta(delta)
                    }
                case "done":
                    if let result = event.result {
                        onDone(result)
                    }
                case "error":
                    onError(event.error ?? "Stage2生成エラー")
                default:
                    break
                }
            }
        } catch {
            onError(error.localizedDescription)
        }
    }

    private func receiveLoop() async {
        guard let task = websocketTask else { return }

        while !Task.isCancelled {
            do {
                let message = try await task.receive()
                switch message {
                case .string(let text):
                    handleTranscribeMessage(text)
                case .data(let data):
                    if let text = String(data: data, encoding: .utf8) {
                        handleTranscribeMessage(text)
                    }
                @unknown default:
                    break
                }
            } catch {
                if shouldIgnoreSocketError(error) || Task.isCancelled {
                    logger.log("ProxyClient", "receiveLoop ignored socket error: \(error.localizedDescription)")
                    disconnectTranscription()
                    return
                }
                logger.log("ProxyClient", "receiveLoop error: \(error.localizedDescription)")
                onTranscribeEvent?(.error(error.localizedDescription))
                disconnectTranscription()
                return
            }
        }
    }

    private func handleTranscribeMessage(_ text: String) {
        guard let data = text.data(using: .utf8) else {
            return
        }

        guard
            let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
            let type = object["type"] as? String
        else {
            return
        }

        switch type {
        case "transcript.delta":
            if let delta = object["text"] as? String {
                onTranscribeEvent?(.delta(delta))
            }
        case "transcript.completed":
            if let full = object["text"] as? String {
                onTranscribeEvent?(.completed(full))
            }
        case "transcript.committed":
            if let full = object["text"] as? String {
                onTranscribeEvent?(.committed(full))
            }
        case "status":
            if let status = object["value"] as? String {
                onTranscribeEvent?(.status(status))
            }
        case "error":
            if let message = object["message"] as? String {
                onTranscribeEvent?(.error(message))
            }
        default:
            break
        }
    }

    private func sendWebSocketJSON(_ payload: [String: Any]) {
        guard let task = websocketTask else { return }
        guard JSONSerialization.isValidJSONObject(payload) else { return }
        guard let data = try? JSONSerialization.data(withJSONObject: payload),
              let text = String(data: data, encoding: .utf8)
        else {
            return
        }

        task.send(.string(text)) { [weak self] error in
            guard let self else { return }
            if let error, !self.shouldIgnoreSocketError(error) {
                self.logger.log("ProxyClient", "sendWebSocketJSON error: \(error.localizedDescription)")
                self.onTranscribeEvent?(.error(error.localizedDescription))
            }
        }
    }

    private func shouldIgnoreSocketError(_ error: Error) -> Bool {
        if isDisconnectingTranscription {
            return true
        }

        if let urlError = error as? URLError, urlError.code == .cancelled {
            return true
        }

        let normalized = error.localizedDescription.lowercased()
        return normalized.contains("socket is not connected")
            || normalized.contains("not connected")
            || normalized.contains("cancelled")
            || normalized.contains("canceled")
            || normalized.contains("socket is closed")
    }
}

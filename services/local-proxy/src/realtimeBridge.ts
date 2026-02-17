import WebSocket, { type RawData } from "ws";
import { config, hasApiKey, safeLog } from "./config.js";

type ClientEnvelope =
  | { type: "config"; server_vad?: { silence_duration_ms?: number; prefix_padding_ms?: number } }
  | { type: "audio"; audio: string }
  | { type: "commit"; reason?: string }
  | { type: "text_probe"; text: string };

const parseClientMessage = (raw: RawData): ClientEnvelope | null => {
  try {
    const text = typeof raw === "string" ? raw : raw.toString("utf8");
    const parsed = JSON.parse(text) as Partial<ClientEnvelope>;
    if (!parsed || typeof parsed.type !== "string") return null;
    return parsed as ClientEnvelope;
  } catch {
    return null;
  }
};

export class RealtimeBridge {
  private readonly client: WebSocket;
  private realtimeSocket: WebSocket | null = null;
  private transcriptBuffer = "";
  private silenceDurationMs = 300;
  private pendingAudioBytes = 0;
  private readonly minCommitAudioBytes = 4_800;

  constructor(client: WebSocket) {
    this.client = client;
  }

  public start(): void {
    this.sendToClient({ type: "status", value: "connected" });
    if (hasApiKey()) {
      this.connectRealtime();
    } else {
      this.sendToClient({ type: "status", value: "mock-transcribe-mode" });
    }
  }

  public stop(): void {
    if (this.realtimeSocket) {
      this.realtimeSocket.close();
      this.realtimeSocket = null;
    }
  }

  public handleClientMessage(raw: RawData): void {
    const parsed = parseClientMessage(raw);
    if (!parsed) {
      this.sendToClient({ type: "error", message: "invalid client payload" });
      return;
    }

    switch (parsed.type) {
      case "config":
        if (parsed.server_vad?.silence_duration_ms) {
          this.silenceDurationMs = parsed.server_vad.silence_duration_ms;
        }
        this.sendRealtimeEvent(this.sessionUpdateEvent());
        break;
      case "audio":
        this.pendingAudioBytes += this.decodeBase64ByteLength(parsed.audio);
        this.sendRealtimeEvent({ type: "input_audio_buffer.append", audio: parsed.audio });
        break;
      case "commit":
        if (this.pendingAudioBytes < this.minCommitAudioBytes) {
          this.sendToClient({ type: "status", value: "commit-skipped-small-buffer" });
          break;
        }
        this.sendRealtimeEvent({ type: "input_audio_buffer.commit" });
        this.pendingAudioBytes = 0;
        if (this.transcriptBuffer.length > 0) {
          this.sendToClient({ type: "transcript.committed", text: this.transcriptBuffer });
        }
        break;
      case "text_probe":
        this.handleTextProbe(parsed.text);
        break;
      default:
        break;
    }
  }

  private connectRealtime(): void {
    const url = `wss://api.openai.com/v1/realtime?intent=transcription`;

    const socket = new WebSocket(url, {
      headers: {
        Authorization: `Bearer ${config.openaiApiKey}`
      }
    });

    this.realtimeSocket = socket;

    socket.on("open", () => {
      this.sendRealtimeEvent(this.sessionUpdateEvent());
      this.sendToClient({ type: "status", value: "realtime-ready" });
    });

    socket.on("message", (data) => {
      this.handleRealtimeMessage(data);
    });

    socket.on("error", (error) => {
      this.sendToClient({ type: "error", message: error.message });
    });

    socket.on("close", () => {
      this.sendToClient({ type: "status", value: "realtime-closed" });
      this.realtimeSocket = null;
    });
  }

  private sessionUpdateEvent(): Record<string, unknown> {
    return {
      type: "session.update",
      session: {
        type: "transcription",
        audio: {
          input: {
            format: {
              type: "audio/pcm",
              rate: 24000
            },
            noise_reduction: {
              type: "near_field"
            },
            transcription: {
              model: config.transcriptionModel,
              language: "ja"
            },
            turn_detection: {
              type: "server_vad",
              silence_duration_ms: this.silenceDurationMs,
              prefix_padding_ms: 200
            }
          }
        },
        include: ["item.input_audio_transcription.logprobs"]
      }
    };
  }

  private handleRealtimeMessage(raw: RawData): void {
    try {
      const text = typeof raw === "string" ? raw : raw.toString("utf8");
      const payload = JSON.parse(text) as {
        type?: string;
        delta?: string;
        transcript?: string;
        error?: { message?: string };
      };

      const type = payload.type;
      if (!type) {
        return;
      }

      if (type === "conversation.item.input_audio_transcription.delta" && payload.delta) {
        this.transcriptBuffer += payload.delta;
        this.sendToClient({ type: "transcript.delta", text: payload.delta });
        return;
      }

      if (type === "conversation.item.input_audio_transcription.completed") {
        const completed = payload.transcript ?? this.transcriptBuffer;
        if (completed) {
          this.sendToClient({ type: "transcript.completed", text: completed });
        }
        this.pendingAudioBytes = 0;
        this.transcriptBuffer = "";
        return;
      }

      if (type === "error") {
        const message = payload.error?.message ?? "realtime error";
        if (this.isIgnorableCommitError(message)) {
          safeLog(`ignoring non-fatal realtime commit error: ${message}`);
          this.pendingAudioBytes = 0;
          return;
        }
        this.sendToClient({ type: "error", message });
      }
    } catch (error) {
      safeLog(`realtime parse error: ${String(error)}`);
    }
  }

  private sendRealtimeEvent(payload: Record<string, unknown>): void {
    if (!this.realtimeSocket || this.realtimeSocket.readyState !== WebSocket.OPEN) {
      return;
    }
    this.realtimeSocket.send(JSON.stringify(payload));
  }

  private handleTextProbe(text: string): void {
    const trimmed = text.trim();
    if (!trimmed) return;

    const chunks = trimmed.split(/\s+/).slice(0, 6);
    for (const chunk of chunks) {
      this.sendToClient({ type: "transcript.delta", text: `${chunk} ` });
    }
    this.sendToClient({ type: "transcript.completed", text: trimmed });
  }

  private sendToClient(payload: Record<string, unknown>): void {
    if (this.client.readyState !== WebSocket.OPEN) {
      return;
    }
    this.client.send(JSON.stringify(payload));
  }

  private decodeBase64ByteLength(base64: string): number {
    try {
      return Buffer.from(base64, "base64").byteLength;
    } catch {
      return 0;
    }
  }

  private isIgnorableCommitError(message: string): boolean {
    const normalized = message.toLowerCase();
    return (
      normalized.includes("buffer too small") ||
      normalized.includes("0.00ms of audio") ||
      normalized.includes("expected at least 100ms")
    );
  }
}

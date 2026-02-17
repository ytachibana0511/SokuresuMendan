import dotenv from "dotenv";

dotenv.config();

const toInt = (value: string | undefined, fallback: number): number => {
  if (!value) return fallback;
  const parsed = Number.parseInt(value, 10);
  return Number.isFinite(parsed) ? parsed : fallback;
};

export const config = {
  host: process.env.HOST ?? "127.0.0.1",
  port: toInt(process.env.PORT, 39871),
  openaiApiKey: process.env.OPENAI_API_KEY ?? "",
  stage1Model: process.env.OPENAI_STAGE1_MODEL ?? "gpt-4.1-mini",
  stage2Model: process.env.OPENAI_STAGE2_MODEL ?? "gpt-4.1-nano",
  transcriptionModel:
    process.env.OPENAI_TRANSCRIPTION_MODEL ??
    (process.env.OPENAI_REALTIME_MODEL && !process.env.OPENAI_REALTIME_MODEL.includes("realtime")
      ? process.env.OPENAI_REALTIME_MODEL
      : "gpt-4o-mini-transcribe")
} as const;

export const hasApiKey = (): boolean => config.openaiApiKey.trim().length > 0;

export const safeLog = (message: string): void => {
  const key = config.openaiApiKey.trim();
  const cleaned = key.length > 0 ? message.replaceAll(key, "[REDACTED]") : message;
  console.log(`[local-proxy] ${cleaned}`);
};

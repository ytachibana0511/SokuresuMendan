import type { Response } from "express";
import { config, hasApiKey } from "./config.js";
import {
  stage1Schema,
  stage2Schema,
  type Stage1Payload,
  type Stage1Request,
  type Stage2Payload,
  type Stage2Request,
  type StreamEnvelope
} from "./types.js";

type JSONValue = null | string | number | boolean | JSONValue[] | { [key: string]: JSONValue };

type SSEEventPayload = {
  type?: string;
  [key: string]: JSONValue | undefined;
};

const writeStreamEvent = <T>(res: Response, event: StreamEnvelope<T>): void => {
  res.write(`${JSON.stringify(event)}\n`);
};

const stage1Fallback = (input: Stage1Request): Stage1Payload => ({
  answer_10s: `結論として、${input.category}の観点で要点を先に答えます。${input.question.slice(0, 18)}に対して実績ベースで簡潔に説明します。`,
  keywords: [input.category, "結論先出し", "実績"],
  assumptions: ["ローカルフォールバック応答", "APIキー未設定"]
});

const stage2Fallback = (input: Stage2Request): Stage2Payload => ({
  answer_30s: `最初に背景を共有し、次に対応内容、最後に再現可能な学びを伝えます。${input.category}の質問では数字付きで成果を補足します。`,
  followups: [
    {
      question: "その判断をした根拠は何ですか？",
      suggested_answer: "制約条件と代替案を比較し、リスクが最小の案を選んだためです。"
    },
    {
      question: "難しかった点はどこですか？",
      suggested_answer: "初期要件が曖昧だったため、先に成功条件を定義して認識を揃えました。"
    },
    {
      question: "次回改善するなら何を変えますか？",
      suggested_answer: "計測をさらに早い段階で組み込み、検証サイクルを短縮します。"
    }
  ]
});

const questionLikeTailPattern = /(ですか|ますか|でしょうか|ませんか|でしょうかね|かな|ですかね|ですよね)\s*[?？]*$/u;
const reverseQuestionPattern =
  /(教えて(?:いただけ|もらえ|くれ)?|ご教示|ご共有|説明して(?:いただけ|もらえ|くれ)?|お聞かせ|伺って|確認させて).{0,20}(?:ますか|でしょうか|ください|いただけ)/u;

const isQuestionLikeAnswer = (text: string): boolean => {
  const normalized = text.trim();
  if (!normalized) {
    return true;
  }

  if (normalized.includes("?") || normalized.includes("？")) {
    return true;
  }

  if (questionLikeTailPattern.test(normalized)) {
    return true;
  }

  return reverseQuestionPattern.test(normalized);
};

const ensureSentenceEnding = (text: string): string => {
  const trimmed = text.trim().replace(/[?？]+$/gu, "。");
  if (!trimmed) {
    return trimmed;
  }
  if (/[。！!]$/u.test(trimmed)) {
    return trimmed;
  }
  return `${trimmed}。`;
};

const stage1SafeAnswer = (input: Stage1Request): string =>
  `結論として、${input.category}は要点から簡潔にお伝えします。背景・対応・成果の順で、私の実例を30秒以内に説明します。`;

const stage2SafeAnswer = (input: Stage2Request): string =>
  `続けて、${input.category}で実際に行った対応と成果を具体的にお伝えします。まず制約と優先順位を整理し、次に実施手順と検証結果を示し、最後に再現性と次回改善まで簡潔に補足します。`;

const trimLeadingConnector = (text: string): string =>
  text.replace(/^[\s、。,:：;；\-ー]+/u, "").trim();

const stripStage1Overlap = (stage1Answer: string, stage2Answer: string): string => {
  const base = stage1Answer.trim();
  let extended = stage2Answer.trim();
  if (!base || !extended) {
    return extended;
  }

  if (extended.startsWith(base)) {
    return trimLeadingConnector(extended.slice(base.length));
  }

  const maxOverlap = Math.min(base.length, extended.length);
  for (let len = maxOverlap; len >= 8; len -= 1) {
    if (base.slice(-len) === extended.slice(0, len)) {
      extended = extended.slice(len);
      break;
    }
  }

  return trimLeadingConnector(extended);
};

const ensureRichContinuation = (input: Stage2Request, text: string): string => {
  const normalized = ensureSentenceEnding(text);
  if (normalized.length >= 90) {
    return normalized;
  }

  const supplement = `補足として、${input.category}では判断理由を先に示し、実装時の工夫と検証結果を数字で伝え、最後に再現可能な学びまで一息で説明します。`;
  return ensureSentenceEnding(`${normalized} ${supplement}`);
};

const sanitizeStage1Payload = (input: Stage1Request, payload: Stage1Payload): Stage1Payload => {
  const answer = ensureSentenceEnding(payload.answer_10s ?? "");
  const safeAnswer = isQuestionLikeAnswer(answer) ? stage1SafeAnswer(input) : answer;

  const keywords = Array.isArray(payload.keywords) && payload.keywords.length > 0
    ? payload.keywords
    : [input.category, "結論先出し", "実績"];

  const assumptions = Array.isArray(payload.assumptions) && payload.assumptions.length > 0
    ? payload.assumptions
    : ["候補者として簡潔に回答"];

  return {
    answer_10s: safeAnswer,
    keywords,
    assumptions
  };
};

const sanitizeStage2Payload = (input: Stage2Request, payload: Stage2Payload): Stage2Payload => {
  const answer = ensureSentenceEnding(payload.answer_30s ?? "");
  const nonQuestionAnswer = isQuestionLikeAnswer(answer) ? stage2SafeAnswer(input) : answer;
  const continuation = stripStage1Overlap(input.stage1_answer, nonQuestionAnswer);
  const safeAnswer = ensureRichContinuation(input, continuation || stage2SafeAnswer(input));

  return {
    answer_30s: safeAnswer,
    followups: payload.followups ?? []
  };
};

const safeParseJSONObject = <T>(text: string): T => {
  const direct = text.trim();
  if (direct.startsWith("{") && direct.endsWith("}")) {
    return JSON.parse(direct) as T;
  }

  const firstBrace = direct.indexOf("{");
  const lastBrace = direct.lastIndexOf("}");
  if (firstBrace >= 0 && lastBrace > firstBrace) {
    return JSON.parse(direct.slice(firstBrace, lastBrace + 1)) as T;
  }

  throw new Error("JSON parse failed: object boundary not found");
};

const buildProfileContext = (summary: string, bullets: string[]): string => {
  const lines = bullets.length > 0 ? bullets.map((bullet) => `- ${bullet}`).join("\n") : "- なし";
  return `プロフィール要約:\n${summary || "なし"}\n\n関連キーワード:\n${lines}`;
};

const stage1SystemPrompt = `あなたは日本語面談の回答コーチです。あなたの出力は「候補者本人が面接官へ返答する回答文」です。日本語を最優先し、丁寧語で、口頭で言える短さで回答してください。

制約:
- 10秒で言える短さ
- 最大2文または箇条書き3点まで
- 前置き禁止
- 面談でそのまま言える言い方
- 面接官への逆質問・依頼・確認は禁止（例: 教えてください、〜ですか？）
- 疑問符（? / ？）を使わない
- 必ず断定文で終える
- 出力はJSON Schemaに厳密準拠`;

const stage2SystemPrompt = `あなたは日本語面談の回答コーチです。あなたの出力は「候補者本人が面接官へ返答する回答文」です。日本語を最優先し、丁寧語で、口頭回答として自然にしてください。

制約:
- 30秒回答を1つ
- 深掘り質問は3件固定
- 各 suggested_answer は短く明確
- answer_30s は Stage1回答の「続き」だけを書く（Stage1の内容を言い換え含めて繰り返さない）
- answer_30s は120〜220文字を目安にする
- answer_30s には「具体行動」「工夫/判断理由」「成果 or 検証結果」を必ず含める
- answer_30s は逆質問・依頼・確認の言い回しを禁止
- answer_30s に疑問符（? / ？）を使わない
- answer_30s は必ず断定文で終える
- 出力はJSON Schemaに厳密準拠`;

const buildStage1UserPrompt = (input: Stage1Request): string => {
  return `質問カテゴリ: ${input.category}\n質問: ${input.question}\n\n${buildProfileContext(input.profile_summary, input.profile_bullets)}\n\n10秒版の回答案を返してください。`;
};

const buildStage2UserPrompt = (input: Stage2Request): string => {
  return `質問カテゴリ: ${input.category}\n質問: ${input.question}\nStage1回答: ${input.stage1_answer}\n\n${buildProfileContext(input.profile_summary, input.profile_bullets)}\n\n重要: answer_30s は Stage1回答の続きだけを書き、重複を入れないでください。短く終わらせず、具体的な追記を十分に入れてください。\n30秒版と深掘りQ&Aを返してください。`;
};

const parseStreamBody = async function* (
  body: ReadableStream<Uint8Array>
): AsyncGenerator<SSEEventPayload> {
  const decoder = new TextDecoder();
  let buffer = "";

  for await (const chunk of body) {
    buffer += decoder.decode(chunk, { stream: true });

    let markerIndex = buffer.indexOf("\n\n");
    while (markerIndex >= 0) {
      const frame = buffer.slice(0, markerIndex);
      buffer = buffer.slice(markerIndex + 2);

      const dataLines = frame
        .split("\n")
        .filter((line) => line.startsWith("data:"))
        .map((line) => line.slice(5).trim())
        .filter((line) => line.length > 0);

      for (const dataLine of dataLines) {
        if (dataLine === "[DONE]") {
          return;
        }
        try {
          const parsed = JSON.parse(dataLine) as SSEEventPayload;
          yield parsed;
        } catch {
          // ignore malformed chunks
        }
      }

      markerIndex = buffer.indexOf("\n\n");
    }
  }
};

const extractOutputText = (event: SSEEventPayload): string => {
  const candidate = event["delta"];
  if (typeof candidate === "string") {
    return candidate;
  }

  const text = event["text"];
  if (typeof text === "string") {
    return text;
  }

  const response = event["response"] as { output_text?: string } | undefined;
  if (response && typeof response.output_text === "string") {
    return response.output_text;
  }

  return "";
};

const streamStructuredResponse = async <T>(params: {
  model: string;
  systemPrompt: string;
  userPrompt: string;
  schemaName: string;
  schema: Record<string, unknown>;
  maxOutputTokens: number;
  temperature: number;
  onDelta: (delta: string) => void;
}): Promise<T> => {
  const response = await fetch("https://api.openai.com/v1/responses", {
    method: "POST",
    headers: {
      "Content-Type": "application/json",
      Authorization: `Bearer ${config.openaiApiKey}`
    },
    body: JSON.stringify({
      model: params.model,
      stream: true,
      max_output_tokens: params.maxOutputTokens,
      temperature: params.temperature,
      input: [
        {
          role: "system",
          content: [{ type: "input_text", text: params.systemPrompt }]
        },
        {
          role: "user",
          content: [{ type: "input_text", text: params.userPrompt }]
        }
      ],
      text: {
        format: {
          type: "json_schema",
          name: params.schemaName,
          schema: params.schema,
          strict: true
        }
      }
    })
  });

  if (!response.ok) {
    const body = await response.text();
    throw new Error(`OpenAI error: ${response.status} ${body}`);
  }

  if (!response.body) {
    throw new Error("OpenAI response body is empty");
  }

  let accumulatedText = "";
  let completedText = "";

  for await (const event of parseStreamBody(response.body)) {
    const type = typeof event.type === "string" ? event.type : "";

    if (type === "response.output_text.delta") {
      const delta = extractOutputText(event);
      if (delta) {
        accumulatedText += delta;
        params.onDelta(delta);
      }
      continue;
    }

    if (type === "response.output_text.done") {
      const text = extractOutputText(event);
      if (text) {
        completedText = text;
      }
      continue;
    }

    if (type === "error") {
      const message = event.message;
      throw new Error(typeof message === "string" ? message : "OpenAI stream error");
    }
  }

  const rawText = accumulatedText || completedText;
  if (!rawText) {
    throw new Error("Model output was empty");
  }

  return safeParseJSONObject<T>(rawText);
};

export const streamStage1 = async (res: Response, input: Stage1Request): Promise<void> => {
  if (!hasApiKey()) {
    const payload = sanitizeStage1Payload(input, stage1Fallback(input));
    writeStreamEvent(res, { type: "delta", delta: payload.answer_10s });
    writeStreamEvent(res, { type: "done", result: payload });
    res.end();
    return;
  }

  try {
    const result = await streamStructuredResponse<Stage1Payload>({
      model: config.stage1Model,
      systemPrompt: stage1SystemPrompt,
      userPrompt: buildStage1UserPrompt(input),
      schemaName: "stage1_payload",
      schema: stage1Schema,
      maxOutputTokens: 180,
      temperature: 0.2,
      onDelta: (delta) => {
        writeStreamEvent(res, { type: "delta", delta });
      }
    });

    const sanitized = sanitizeStage1Payload(input, result);
    writeStreamEvent(res, { type: "done", result: sanitized });
    res.end();
  } catch (error) {
    writeStreamEvent(res, {
      type: "error",
      error: error instanceof Error ? error.message : "stage1 generation failed"
    });
    res.end();
  }
};

export const streamStage2 = async (res: Response, input: Stage2Request): Promise<void> => {
  if (!hasApiKey()) {
    const payload = sanitizeStage2Payload(input, stage2Fallback(input));
    writeStreamEvent(res, { type: "delta", delta: payload.answer_30s });
    writeStreamEvent(res, { type: "done", result: payload });
    res.end();
    return;
  }

  try {
    const result = await streamStructuredResponse<Stage2Payload>({
      model: config.stage2Model,
      systemPrompt: stage2SystemPrompt,
      userPrompt: buildStage2UserPrompt(input),
      schemaName: "stage2_payload",
      schema: stage2Schema,
      maxOutputTokens: 700,
      temperature: 0.35,
      onDelta: (delta) => {
        writeStreamEvent(res, { type: "delta", delta });
      }
    });

    const sanitized = sanitizeStage2Payload(input, result);
    writeStreamEvent(res, { type: "done", result: sanitized });
    res.end();
  } catch (error) {
    writeStreamEvent(res, {
      type: "error",
      error: error instanceof Error ? error.message : "stage2 generation failed"
    });
    res.end();
  }
};

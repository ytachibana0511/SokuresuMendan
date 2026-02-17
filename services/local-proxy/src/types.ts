import { z } from "zod";

export const questionCategorySchema = z.enum([
  "自己紹介",
  "強み",
  "志望動機",
  "経験",
  "炎上対応",
  "設計",
  "テスト",
  "チーム",
  "コミュニケーション",
  "障害対応",
  "パフォーマンス",
  "セキュリティ",
  "その他"
]);

export const stage1RequestSchema = z.object({
  question: z.string().min(1),
  category: questionCategorySchema,
  profile_summary: z.string().default(""),
  profile_bullets: z.array(z.string()).max(5).default([]),
  language: z.string().default("ja")
});

export const stage2RequestSchema = z.object({
  question: z.string().min(1),
  category: questionCategorySchema,
  stage1_answer: z.string().default(""),
  profile_summary: z.string().default(""),
  profile_bullets: z.array(z.string()).max(5).default([]),
  language: z.string().default("ja")
});

export const stage1Schema = {
  type: "object",
  additionalProperties: false,
  properties: {
    answer_10s: { type: "string" },
    keywords: {
      type: "array",
      items: { type: "string" },
      maxItems: 5
    },
    assumptions: {
      type: "array",
      items: { type: "string" },
      maxItems: 3
    }
  },
  required: ["answer_10s", "keywords", "assumptions"]
} as const;

export const stage2Schema = {
  type: "object",
  additionalProperties: false,
  properties: {
    answer_30s: { type: "string" },
    followups: {
      type: "array",
      minItems: 3,
      maxItems: 3,
      items: {
        type: "object",
        additionalProperties: false,
        properties: {
          question: { type: "string" },
          suggested_answer: { type: "string" }
        },
        required: ["question", "suggested_answer"]
      }
    }
  },
  required: ["answer_30s", "followups"]
} as const;

export type Stage1Request = z.infer<typeof stage1RequestSchema>;
export type Stage2Request = z.infer<typeof stage2RequestSchema>;

export type Stage1Payload = {
  answer_10s: string;
  keywords: string[];
  assumptions: string[];
};

export type Stage2Payload = {
  answer_30s: string;
  followups: Array<{
    question: string;
    suggested_answer: string;
  }>;
};

export type StreamEnvelope<T> =
  | { type: "delta"; delta: string }
  | { type: "done"; result: T }
  | { type: "error"; error: string };

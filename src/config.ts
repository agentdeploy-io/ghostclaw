import { config as loadEnv } from "dotenv";
import { z } from "zod";

loadEnv();

const schema = z
  .object({
    NODE_ENV: z.enum(["development", "test", "production"]).default("development"),
    HOST: z.string().default("0.0.0.0"),
    PORT: z.coerce.number().int().min(1).max(65535).default(8787),
    LOG_LEVEL: z
      .enum(["fatal", "error", "warn", "info", "debug", "trace"])
      .default("info"),
    INTERNAL_API_TOKEN: z.string().min(16).optional(),
    REDIS_URL: z.string().url().default("redis://redis:6379"),
    WORKER_CONCURRENCY: z.coerce.number().int().min(1).max(10).default(2),
    ARTIFACT_DIR: z.string().default("/data/artifacts"),
    BROWSER_HEADLESS: z.enum(["true", "false"]).default("true"),
    BROWSER_PROVIDER: z.enum(["camoufox", "local"]).default("camoufox"),
    BROWSER_DEFAULT_TIMEOUT_MS: z.coerce
      .number()
      .int()
      .min(1_000)
      .max(120_000)
      .default(25_000),
    BROWSER_CHALLENGE_KEYWORDS: z
      .string()
      .default(
        "captcha,verify you are human,security check,mfa,one-time code,unusual traffic,access denied",
      ),
    BROWSER_EXECUTABLE_PATH: z.string().optional(),
    CAMOUFOX_WS_ENDPOINT: z.string().optional(),
    CAMOUFOX_CONNECT_TIMEOUT_MS: z.coerce
      .number()
      .int()
      .min(1_000)
      .max(120_000)
      .default(30_000),
    MAIN_LLM_BASE_URL: z.string().url(),
    MAIN_LLM_API_KEY: z.string().min(1),
    MAIN_LLM_MODEL: z.string().default("Qwen3.5-397B-A17B-TEE"),
    SUB_LLM_BASE_URL: z.string().url(),
    SUB_LLM_API_KEY: z.string().min(1),
    SUB_LLM_MODEL: z.string().default("MiniMaxAI/MiniMax-M2.5-TEE"),
    LLM_REQUEST_TIMEOUT_MS: z.coerce
      .number()
      .int()
      .min(1_000)
      .max(120_000)
      .default(120_000),
    ENABLE_TELEGRAM: z.enum(["true", "false"]).default("false"),
    TELEGRAM_BOT_TOKEN: z.string().optional(),
    TELEGRAM_WEBHOOK_SECRET: z.string().optional(),
    TELEGRAM_ALLOWED_CHAT_IDS: z.string().optional(),
    DOMAIN: z.string().optional(),
    ACME_EMAIL: z.string().email().optional(),
  })
  .superRefine((value, ctx) => {
    if (value.BROWSER_PROVIDER === "camoufox" && value.CAMOUFOX_WS_ENDPOINT) {
      try {
        const parsed = new URL(value.CAMOUFOX_WS_ENDPOINT);
        if (parsed.protocol !== "ws:" && parsed.protocol !== "wss:") {
          ctx.addIssue({
            code: z.ZodIssueCode.custom,
            path: ["CAMOUFOX_WS_ENDPOINT"],
            message: "CAMOUFOX_WS_ENDPOINT must use ws:// or wss:// protocol",
          });
        }
      } catch {
        ctx.addIssue({
          code: z.ZodIssueCode.custom,
          path: ["CAMOUFOX_WS_ENDPOINT"],
          message: "CAMOUFOX_WS_ENDPOINT must be a valid WebSocket URL",
        });
      }
    }

    if (value.ENABLE_TELEGRAM === "true") {
      if (!value.TELEGRAM_BOT_TOKEN) {
        ctx.addIssue({
          code: z.ZodIssueCode.custom,
          path: ["TELEGRAM_BOT_TOKEN"],
          message: "TELEGRAM_BOT_TOKEN is required when ENABLE_TELEGRAM=true",
        });
      }
      if (!value.TELEGRAM_WEBHOOK_SECRET) {
        ctx.addIssue({
          code: z.ZodIssueCode.custom,
          path: ["TELEGRAM_WEBHOOK_SECRET"],
          message:
            "TELEGRAM_WEBHOOK_SECRET is required when ENABLE_TELEGRAM=true",
        });
      }
    }
  });

const parsed = schema.parse(process.env);

const allowedChatIds = parsed.TELEGRAM_ALLOWED_CHAT_IDS
  ? parsed.TELEGRAM_ALLOWED_CHAT_IDS.split(",")
      .map((value) => value.trim())
      .filter((value) => value.length > 0)
      .map((value) => Number(value))
      .filter((value) => Number.isInteger(value))
  : [];

export const appConfig = {
  env: parsed.NODE_ENV,
  host: parsed.HOST,
  port: parsed.PORT,
  logLevel: parsed.LOG_LEVEL,
  internalApiToken: parsed.INTERNAL_API_TOKEN,
  redisUrl: parsed.REDIS_URL,
  workerConcurrency: parsed.WORKER_CONCURRENCY,
  artifactDir: parsed.ARTIFACT_DIR,
  browser: {
    headless: parsed.BROWSER_HEADLESS === "true",
    provider: parsed.BROWSER_PROVIDER,
    defaultTimeoutMs: parsed.BROWSER_DEFAULT_TIMEOUT_MS,
    executablePath: parsed.BROWSER_EXECUTABLE_PATH,
    camoufoxWsEndpoint: parsed.CAMOUFOX_WS_ENDPOINT,
    camoufoxConnectTimeoutMs: parsed.CAMOUFOX_CONNECT_TIMEOUT_MS,
    challengeKeywords: parsed.BROWSER_CHALLENGE_KEYWORDS.split(",")
      .map((value) => value.trim().toLowerCase())
      .filter((value) => value.length > 0),
  },
  mainLlm: {
    baseUrl: parsed.MAIN_LLM_BASE_URL,
    apiKey: parsed.MAIN_LLM_API_KEY,
    model: parsed.MAIN_LLM_MODEL,
  },
  subLlm: {
    baseUrl: parsed.SUB_LLM_BASE_URL,
    apiKey: parsed.SUB_LLM_API_KEY,
    model: parsed.SUB_LLM_MODEL,
  },
  llmTimeoutMs: parsed.LLM_REQUEST_TIMEOUT_MS,
  telegram: {
    enabled: parsed.ENABLE_TELEGRAM === "true",
    botToken: parsed.TELEGRAM_BOT_TOKEN,
    webhookSecret: parsed.TELEGRAM_WEBHOOK_SECRET,
    allowedChatIds,
  },
  deploy: {
    domain: parsed.DOMAIN,
    acmeEmail: parsed.ACME_EMAIL,
  },
} as const;

export type AppConfig = typeof appConfig;

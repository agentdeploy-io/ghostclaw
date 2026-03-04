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
    REDIS_URL: z.string().url().default("redis://localhost:6379"),
    WORKER_CONCURRENCY: z.coerce.number().int().min(1).max(10).default(2),
    ARTIFACT_DIR: z.string().default("./data/artifacts"),
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
    
    // Telegram integration
    ENABLE_TELEGRAM: z.enum(["true", "false"]).default("false"),
    TELEGRAM_BOT_TOKEN: z.string().optional(),
    TELEGRAM_WEBHOOK_SECRET: z.string().optional(),
    TELEGRAM_ALLOWED_CHAT_IDS: z.string().optional(),
    
    // Slack integration
    ENABLE_SLACK: z.enum(["true", "false"]).default("false"),
    SLACK_BOT_TOKEN: z.string().optional(),
    SLACK_SIGNING_SECRET: z.string().optional(),
    SLACK_APP_TOKEN: z.string().optional(),
    
    // Discord integration
    ENABLE_DISCORD: z.enum(["true", "false"]).default("false"),
    DISCORD_BOT_TOKEN: z.string().optional(),
    DISCORD_CLIENT_ID: z.string().optional(),
    
    // WhatsApp integration
    ENABLE_WHATSAPP: z.enum(["true", "false"]).default("false"),
    WHATSAPP_PHONE_NUMBER_ID: z.string().optional(),
    WHATSAPP_ACCESS_TOKEN: z.string().optional(),
    WHATSAPP_VERIFY_TOKEN: z.string().optional(),
    
    // Mentor configuration
    MENTOR_NAME: z.string().default("Ghostclaw Mentor"),
    MENTOR_PERSONA_FILE: z.string().default("./agents/mentor/persona.md"),
    MENTOR_SKILLS_FILE: z.string().default("./agents/mentor/skills.md"),
    MENTOR_MEMORY_FILE: z.string().default("./data/mentor/memory.json"),
    MENTOR_MEMORY_WINDOW: z.coerce.number().int().min(1).default(14),
    MENTOR_LLM_BASE_URL: z.string().url().optional(),
    MENTOR_LLM_MODEL: z.string().optional(),
    MENTOR_LLM_API_KEY: z.string().optional(),
    
    // Mentor voice configuration
    ENABLE_MENTOR_VOICE: z.enum(["true", "false"]).default("false"),
    MENTOR_VOICE_API_KEY: z.string().optional(),
    MENTOR_CHUTES_VOICE_MODE: z.string().default("run_api"),
    MENTOR_CHUTES_RUN_ENDPOINT: z.string().optional(),
    MENTOR_CHUTES_WHISPER_MODEL: z.string().default("openai/whisper-large-v3-turbo"),
    MENTOR_CHUTES_CSM_MODEL: z.string().default("sesame/csm-1b"),
    MENTOR_CHUTES_KOKORO_MODEL: z.string().default("hexgrad/Kokoro-82M"),
    MENTOR_CHUTES_ENABLE_KOKORO_FALLBACK: z.enum(["true", "false"]).default("true"),
    MENTOR_VOICE_SAMPLE_PATH: z.string().default("./mentor/master-voice.wav"),
    MENTOR_VOICE_CONTEXT_PATH: z.string().default("./data/mentor/voice_context.txt"),
    MENTOR_VOICE_AUTO_TRANSCRIBE: z.enum(["true", "false"]).default("true"),
    
    // Voice-MCP configuration (standalone voice service)
    MCP_VOICE_ENABLED: z.enum(["true", "false"]).default("false"),
    ENABLE_VOICE: z.enum(["true", "false"]).default("false"),
    VOICE_MODE: z.string().default("run_api"),
    VOICE_API_BASE_URL: z.string().url().optional(),
    VOICE_API_KEY: z.string().optional(),
    VOICE_RUN_ENDPOINT: z.string().optional(),
    VOICE_WHISPER_MODEL: z.string().default("openai/whisper-large-v3-turbo"),
    VOICE_CLONE_MODEL: z.string().default("sesame/csm-1b"),
    VOICE_KOKORO_MODEL: z.string().default("hexgrad/Kokoro-82M"),
    VOICE_ENABLE_KOKORO_FALLBACK: z.enum(["true", "false"]).default("true"),
    VOICE_SAMPLE_PATH: z.string().default("./data/voice/master-voice.wav"),
    VOICE_CONTEXT_PATH: z.string().default("./data/voice/voice_context.txt"),
    VOICE_ARTIFACT_DIR: z.string().default("./data/artifacts/voice"),
    TELEGRAM_VOICE_MCP_URL: z.string().optional(),
    ENABLE_TELEGRAM_VOICE_NOTES: z.enum(["true", "false"]).default("true"),
    
    // Deployment
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

    if (value.ENABLE_SLACK === "true") {
      if (!value.SLACK_BOT_TOKEN) {
        ctx.addIssue({
          code: z.ZodIssueCode.custom,
          path: ["SLACK_BOT_TOKEN"],
          message: "SLACK_BOT_TOKEN is required when ENABLE_SLACK=true",
        });
      }
      if (!value.SLACK_SIGNING_SECRET) {
        ctx.addIssue({
          code: z.ZodIssueCode.custom,
          path: ["SLACK_SIGNING_SECRET"],
          message: "SLACK_SIGNING_SECRET is required when ENABLE_SLACK=true",
        });
      }
    }

    if (value.ENABLE_DISCORD === "true") {
      if (!value.DISCORD_BOT_TOKEN) {
        ctx.addIssue({
          code: z.ZodIssueCode.custom,
          path: ["DISCORD_BOT_TOKEN"],
          message: "DISCORD_BOT_TOKEN is required when ENABLE_DISCORD=true",
        });
      }
    }

    if (value.ENABLE_WHATSAPP === "true") {
      if (!value.WHATSAPP_PHONE_NUMBER_ID) {
        ctx.addIssue({
          code: z.ZodIssueCode.custom,
          path: ["WHATSAPP_PHONE_NUMBER_ID"],
          message: "WHATSAPP_PHONE_NUMBER_ID is required when ENABLE_WHATSAPP=true",
        });
      }
      if (!value.WHATSAPP_ACCESS_TOKEN) {
        ctx.addIssue({
          code: z.ZodIssueCode.custom,
          path: ["WHATSAPP_ACCESS_TOKEN"],
          message: "WHATSAPP_ACCESS_TOKEN is required when ENABLE_WHATSAPP=true",
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
  slack: {
    enabled: parsed.ENABLE_SLACK === "true",
    botToken: parsed.SLACK_BOT_TOKEN,
    signingSecret: parsed.SLACK_SIGNING_SECRET,
    appToken: parsed.SLACK_APP_TOKEN,
  },
  discord: {
    enabled: parsed.ENABLE_DISCORD === "true",
    botToken: parsed.DISCORD_BOT_TOKEN,
    clientId: parsed.DISCORD_CLIENT_ID,
  },
  whatsapp: {
    enabled: parsed.ENABLE_WHATSAPP === "true",
    phoneNumberId: parsed.WHATSAPP_PHONE_NUMBER_ID,
    accessToken: parsed.WHATSAPP_ACCESS_TOKEN,
    verifyToken: parsed.WHATSAPP_VERIFY_TOKEN,
  },
  mentor: {
    name: parsed.MENTOR_NAME,
    personaFile: parsed.MENTOR_PERSONA_FILE,
    skillsFile: parsed.MENTOR_SKILLS_FILE,
    memoryFile: parsed.MENTOR_MEMORY_FILE,
    memoryWindow: parsed.MENTOR_MEMORY_WINDOW,
    llmBaseUrl: parsed.MENTOR_LLM_BASE_URL || parsed.MAIN_LLM_BASE_URL,
    llmModel: parsed.MENTOR_LLM_MODEL || parsed.SUB_LLM_MODEL,
    llmApiKey: parsed.MENTOR_LLM_API_KEY || parsed.MAIN_LLM_API_KEY,
    voice: {
      enabled: parsed.ENABLE_MENTOR_VOICE === "true",
      apiKey: parsed.MENTOR_VOICE_API_KEY || parsed.MAIN_LLM_API_KEY,
      mode: parsed.MENTOR_CHUTES_VOICE_MODE,
      runEndpoint: parsed.MENTOR_CHUTES_RUN_ENDPOINT,
      whisperModel: parsed.MENTOR_CHUTES_WHISPER_MODEL,
      csmModel: parsed.MENTOR_CHUTES_CSM_MODEL,
      kokoroModel: parsed.MENTOR_CHUTES_KOKORO_MODEL,
      kokoroFallback: parsed.MENTOR_CHUTES_ENABLE_KOKORO_FALLBACK === "true",
      samplePath: parsed.MENTOR_VOICE_SAMPLE_PATH,
      contextPath: parsed.MENTOR_VOICE_CONTEXT_PATH,
      autoTranscribe: parsed.MENTOR_VOICE_AUTO_TRANSCRIBE === "true",
    },
  },
  voiceMcp: {
    enabled: parsed.MCP_VOICE_ENABLED === "true" || parsed.ENABLE_VOICE === "true",
    mode: parsed.VOICE_MODE,
    apiBaseUrl: parsed.VOICE_API_BASE_URL || parsed.MAIN_LLM_BASE_URL,
    apiKey: parsed.VOICE_API_KEY || parsed.MAIN_LLM_API_KEY,
    runEndpoint: parsed.VOICE_RUN_ENDPOINT,
    whisperModel: parsed.VOICE_WHISPER_MODEL,
    cloneModel: parsed.VOICE_CLONE_MODEL,
    kokoroModel: parsed.VOICE_KOKORO_MODEL,
    kokoroFallback: parsed.VOICE_ENABLE_KOKORO_FALLBACK === "true",
    samplePath: parsed.VOICE_SAMPLE_PATH,
    contextPath: parsed.VOICE_CONTEXT_PATH,
    artifactDir: parsed.VOICE_ARTIFACT_DIR,
  },
  telegramVoice: {
    mcpUrl: parsed.TELEGRAM_VOICE_MCP_URL || "http://voice-mcp:8792",
    enabled: parsed.ENABLE_TELEGRAM_VOICE_NOTES === "true",
  },
  deploy: {
    domain: parsed.DOMAIN,
    acmeEmail: parsed.ACME_EMAIL,
  },
} as const;

export type AppConfig = typeof appConfig;

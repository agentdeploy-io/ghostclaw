import { randomUUID } from "node:crypto";

import Fastify, { type FastifyReply, type FastifyRequest } from "fastify";

import { appConfig } from "./config.js";
import { AppError } from "./errors.js";
import { createAutomationQueue, createRedisConnection } from "./lib/queue.js";
import { sendTelegramMessage } from "./lib/telegram.js";
import { sendSlackMessage } from "./lib/slack.js";
import { sendDiscordMessage } from "./lib/discord.js";
import { sendWhatsAppMessage, verifyWhatsAppWebhook } from "./lib/whatsapp.js";
import { logger } from "./logger.js";
import { createJobSchema, telegramUpdateSchema } from "./schemas.js";
import type { ApiErrorBody, AutomationJobPayload, BrowserAction } from "./types.js";

const redisConnection = createRedisConnection(appConfig.redisUrl);
const queue = createAutomationQueue(redisConnection);

const app = Fastify({
  logger: false,
  genReqId: () => randomUUID(),
  trustProxy: true,
});

app.addHook("onRequest", async (request, reply) => {
  reply.header("x-request-id", request.id);
});

app.setErrorHandler((error, request, reply) => {
  const requestId = request.id;
  if (error instanceof AppError) {
    return sendError(reply, error.statusCode, error.code, error.message, requestId);
  }

  logger.error({ err: error, requestId }, "Unhandled API error.");
  return sendError(
    reply,
    500,
    "INTERNAL_SERVER_ERROR",
    "Unexpected error while processing request.",
    requestId,
  );
});

app.get("/healthz", async () => {
  const redisStatus = redisConnection.status;
  return {
    status: "ok",
    service: "lippyclaw-api",
    env: appConfig.env,
    redis: redisStatus,
    timestamp: new Date().toISOString(),
  };
});

app.get("/", async () => {
  return {
    service: "lippyclaw-api",
    message: "API running. Use /healthz and /api/v1/jobs.",
    endpoints: {
      health: "/healthz",
      queueJob: "POST /api/v1/jobs (Authorization: Bearer <INTERNAL_API_TOKEN>)",
      getJob: "GET /api/v1/jobs/:jobId (Authorization: Bearer <INTERNAL_API_TOKEN>)",
      telegramWebhook: "POST /telegram/webhook",
      slackWebhook: "POST /slack/webhook",
      discordWebhook: "POST /discord/webhook",
      whatsappWebhook: "POST /whatsapp/webhook",
    },
  };
});

app.post("/api/v1/jobs", async (request, reply) => {
  requireInternalApiToken(request);
  const parsed = createJobSchema.safeParse(request.body);
  if (!parsed.success) {
    return sendError(
      reply,
      400,
      "INVALID_REQUEST_BODY",
      parsed.error.flatten().formErrors.join("; ") || "Invalid request body.",
      request.id,
    );
  }

  const payload: AutomationJobPayload = parsed.data;
  const job = await queue.add("browser-job", payload, {
    attempts: 1,
    removeOnComplete: 100,
    removeOnFail: 100,
  });

  logger.info(
    {
      requestId: request.id,
      jobId: job.id,
      jobName: payload.jobName,
      startUrl: payload.startUrl,
    },
    "Queued browser automation job.",
  );

  if (appConfig.telegram.enabled && payload.chatId && appConfig.telegram.botToken) {
    await sendTelegramMessage(
      appConfig.telegram.botToken,
      payload.chatId,
      `Job queued: ${payload.jobName}\njobId=${job.id}`,
    );
  }

  return reply.code(202).send({
    jobId: job.id,
    requestId: request.id,
    status: "queued",
  });
});

app.get("/api/v1/jobs/:jobId", async (request, reply) => {
  requireInternalApiToken(request);

  const params = request.params as { jobId?: string };
  if (!params.jobId) {
    return sendError(reply, 400, "MISSING_JOB_ID", "jobId is required.", request.id);
  }

  const job = await queue.getJob(params.jobId);
  if (!job) {
    return sendError(reply, 404, "JOB_NOT_FOUND", "No job found for the provided ID.", request.id);
  }

  return reply.send({
    requestId: request.id,
    jobId: job.id,
    state: await job.getState(),
    payload: job.data,
    result: job.returnvalue,
    failedReason: job.failedReason,
    processedOn: job.processedOn,
    finishedOn: job.finishedOn,
  });
});

// Telegram webhook handler
app.post("/telegram/webhook", async (request, reply) => {
  if (!appConfig.telegram.enabled) {
    return sendError(reply, 503, "TELEGRAM_DISABLED", "Telegram integration is disabled.", request.id);
  }

  const providedSecret = request.headers["x-telegram-bot-api-secret-token"];
  if (providedSecret !== appConfig.telegram.webhookSecret) {
    return sendError(reply, 401, "UNAUTHORIZED_WEBHOOK", "Invalid Telegram webhook secret.", request.id);
  }

  const parsed = telegramUpdateSchema.safeParse(request.body);
  if (!parsed.success) {
    return sendError(reply, 400, "INVALID_TELEGRAM_PAYLOAD", "Malformed Telegram update payload.", request.id);
  }

  const message = parsed.data.message;
  if (!message?.text || !appConfig.telegram.botToken) {
    return reply.send({ ok: true });
  }

  const chatId = message.chat.id;
  if (
    appConfig.telegram.allowedChatIds.length > 0 &&
    !appConfig.telegram.allowedChatIds.includes(chatId)
  ) {
    await sendTelegramMessage(
      appConfig.telegram.botToken,
      chatId,
      "This chat is not authorized for this bot.",
    );
    return reply.send({ ok: true });
  }

  const responseText = await handleTelegramCommand(chatId, message.text);
  if (responseText) {
    await sendTelegramMessage(appConfig.telegram.botToken, chatId, responseText);
  }

  return reply.send({ ok: true });
});

// Slack webhook handler
app.post("/slack/webhook", async (request, reply) => {
  if (!appConfig.slack.enabled) {
    return sendError(reply, 503, "SLACK_DISABLED", "Slack integration is disabled.", request.id);
  }

  const body = request.body as Record<string, unknown>;
  const command = body.command as string | undefined;
  const text = body.text as string | undefined;
  const channelId = body.channel_id as string | undefined;
  const userId = body.user_id as string | undefined;
  const responseUrl = body.response_url as string | undefined;

  if (!command || !channelId || !userId) {
    return reply.send({ ok: false, error: "Invalid Slack payload" });
  }

  try {
    const responseText = await handleSlackCommand(command, text || "", userId);
    
    if (responseUrl) {
      // Use response_url for ephemeral reply
      await fetch(responseUrl, {
        method: "POST",
        headers: { "Content-Type": "application/json" },
        body: JSON.stringify({
          text: responseText,
          response_type: "ephemeral",
        }),
      });
    } else {
      await sendSlackMessage(channelId, responseText);
    }

    return reply.send({ ok: true });
  } catch (error) {
    logger.error({ err: error }, "Slack command handling failed");
    return reply.send({ ok: false, error: "Command processing failed" });
  }
});

// Discord webhook handler
app.post("/discord/webhook", async (request, reply) => {
  if (!appConfig.discord.enabled) {
    return sendError(reply, 503, "DISCORD_DISABLED", "Discord integration is disabled.", request.id);
  }

  const body = request.body as Record<string, unknown>;
  
  // Handle Discord interaction (slash command)
  if (body.type === 2) {
    const data = body.data as Record<string, unknown> | undefined;
    const commandName = data?.name as string | undefined;
    const options = data?.options as Array<{ name: string; value: string }> | undefined;
    const channelId = body.channel_id as string | undefined;
    const id = body.id as string | undefined;
    const token = body.token as string | undefined;

    if (!commandName || !channelId || !id || !token) {
      return reply.send({ ok: false, error: "Invalid Discord payload" });
    }

    try {
      const optionValues = options?.reduce((acc, opt) => {
        acc[opt.name] = opt.value;
        return acc;
      }, {} as Record<string, string>) || {};

      const responseText = await handleDiscordCommand(commandName, optionValues);

      // Send interaction response
      await fetch(`https://discord.com/api/v10/interactions/${id}/${token}/callback`, {
        method: "POST",
        headers: { "Content-Type": "application/json" },
        body: JSON.stringify({
          type: 4, // Channel message with source
          data: {
            content: responseText,
          },
        }),
      });

      return reply.send({ ok: true });
    } catch (error) {
      logger.error({ err: error }, "Discord command handling failed");
      return reply.send({ ok: false, error: "Command processing failed" });
    }
  }

  return reply.send({ ok: true });
});

// WhatsApp webhook handler
app.post("/whatsapp/webhook", async (request, reply) => {
  if (!appConfig.whatsapp.enabled) {
    return sendError(reply, 503, "WHATSAPP_DISABLED", "WhatsApp integration is disabled.", request.id);
  }

  const query = request.query as Record<string, string | undefined>;
  
  // WhatsApp verification (GET request)
  if (request.method === "GET") {
    const mode = query["hub.mode"];
    const token = query["hub.verify_token"];
    const challenge = query["hub.challenge"];

    if (mode && token) {
      const verified = await verifyWhatsAppWebhook(mode, token);
      if (verified && challenge) {
        return reply.send(parseInt(challenge, 10));
      }
    }
    return reply.code(403).send("Verification failed");
  }

  // WhatsApp message handling (POST request)
  const body = request.body as Record<string, unknown>;
  const entry = (body.entry as Array<Record<string, unknown>>) || [];
  
  for (const e of entry) {
    const changes = e.changes as Array<Record<string, unknown>> | undefined;
    if (!changes) continue;

    for (const change of changes) {
      const value = change.value as Record<string, unknown> | undefined;
      const messages = value?.messages as Array<Record<string, unknown>> | undefined;
      if (!messages) continue;

      for (const message of messages) {
        const from = message.from as string | undefined;
        const textObj = message.text as Record<string, string> | undefined;
        const text = textObj?.body;

        if (!from || !text) continue;

        try {
          const responseText = await handleWhatsAppCommand(text);
          if (responseText) {
            await sendWhatsAppMessage(from, responseText);
          }
        } catch (error) {
          logger.error({ err: error, from }, "WhatsApp message handling failed");
        }
      }
    }
  }

  return reply.send({ ok: true });
});

const handleTelegramCommand = async (
  chatId: number,
  commandText: string,
): Promise<string> => {
  const trimmed = commandText.trim();

  if (trimmed === "/start" || trimmed === "/help") {
    return [
      "Lippyclaw bot ready.",
      "Commands:",
      "/health",
      "/run <url>",
      "/job <jobId>",
    ].join("\n");
  }

  if (trimmed === "/health") {
    return `API healthy. env=${appConfig.env} redis=${redisConnection.status}`;
  }

  if (trimmed.startsWith("/run ")) {
    const rawUrl = trimmed.replace("/run", "").trim();
    let parsedUrl: URL;
    try {
      parsedUrl = new URL(rawUrl);
    } catch {
      return "Invalid URL. Usage: /run https://example.com";
    }

    const defaultActions: BrowserAction[] = [
      {
        type: "wait_for_timeout",
        timeoutMs: 1500,
      },
      {
        type: "screenshot",
        label: "landing",
        fullPage: true,
      },
    ];

    const payload: AutomationJobPayload = {
      jobName: `telegram-run-${Date.now()}`,
      startUrl: parsedUrl.toString(),
      actions: defaultActions,
      visionPrompt:
        "Summarize the visible page state, identify forms/modals, and propose next operator actions.",
      chatId,
    };

    const job = await queue.add("telegram-browser-job", payload, {
      attempts: 1,
      removeOnComplete: 100,
      removeOnFail: 100,
    });
    return `Job queued.\njobId=${job.id}\nurl=${payload.startUrl}`;
  }

  if (trimmed.startsWith("/job ")) {
    const jobId = trimmed.replace("/job", "").trim();
    if (!jobId) {
      return "Usage: /job <jobId>";
    }
    const job = await queue.getJob(jobId);
    if (!job) {
      return `No job found for id=${jobId}`;
    }
    const state = await job.getState();
    const summary =
      typeof job.returnvalue === "object" && job.returnvalue !== null
        ? JSON.stringify(job.returnvalue)
        : "No result yet.";
    return `jobId=${jobId}\nstate=${state}\nresult=${summary.slice(0, 1200)}`;
  }

  return "Unknown command. Use /help.";
};

const handleSlackCommand = async (
  command: string,
  text: string,
  userId: string,
): Promise<string> => {
  if (command === "/lippyclaw") {
    if (text === "health") {
      return `Lippyclaw API healthy. env=${appConfig.env} redis=${redisConnection.status}`;
    }
    if (text.startsWith("run ")) {
      const url = text.replace("run ", "").trim();
      try {
        const parsedUrl = new URL(url);
        const payload: AutomationJobPayload = {
          jobName: `slack-run-${Date.now()}`,
          startUrl: parsedUrl.toString(),
          actions: [
            { type: "wait_for_timeout", timeoutMs: 1500 },
            { type: "screenshot", label: "landing", fullPage: true },
          ],
          visionPrompt: "Summarize the visible page state.",
        };
        const job = await queue.add("slack-browser-job", payload, {
          attempts: 1,
          removeOnComplete: 100,
          removeOnFail: 100,
        });
        return `Job queued.\njobId=${job.id}\nurl=${payload.startUrl}`;
      } catch {
        return "Invalid URL. Usage: /lippyclaw run https://example.com";
      }
    }
    return "Lippyclaw commands: health, run <url>";
  }
  return "Unknown command. Use /lippyclaw help.";
};

const handleDiscordCommand = async (
  commandName: string,
  options: Record<string, string>,
): Promise<string> => {
  if (commandName === "lippyclaw") {
    const action = options.action || "help";
    if (action === "health") {
      return `Lippyclaw API healthy. env=${appConfig.env} redis=${redisConnection.status}`;
    }
    if (action === "run" && options.url) {
      try {
        const parsedUrl = new URL(options.url);
        const payload: AutomationJobPayload = {
          jobName: `discord-run-${Date.now()}`,
          startUrl: parsedUrl.toString(),
          actions: [
            { type: "wait_for_timeout", timeoutMs: 1500 },
            { type: "screenshot", label: "landing", fullPage: true },
          ],
          visionPrompt: "Summarize the visible page state.",
        };
        const job = await queue.add("discord-browser-job", payload, {
          attempts: 1,
          removeOnComplete: 100,
          removeOnFail: 100,
        });
        return `Job queued.\njobId=${job.id}\nurl=${payload.startUrl}`;
      } catch {
        return "Invalid URL.";
      }
    }
    return "Lippyclaw commands: health, run <url>";
  }
  return "Unknown command.";
};

const handleWhatsAppCommand = async (text: string): Promise<string> => {
  const trimmed = text.trim().toLowerCase();

  if (trimmed === "start" || trimmed === "help") {
    return [
      "Lippyclaw bot ready.",
      "Commands:",
      "health",
      "run <url>",
      "job <jobId>",
    ].join("\n");
  }

  if (trimmed === "health") {
    return `API healthy. env=${appConfig.env} redis=${redisConnection.status}`;
  }

  if (trimmed.startsWith("run ")) {
    const rawUrl = trimmed.replace("run ", "").trim();
    try {
      const parsedUrl = new URL(rawUrl);
      const payload: AutomationJobPayload = {
        jobName: `whatsapp-run-${Date.now()}`,
        startUrl: parsedUrl.toString(),
        actions: [
          { type: "wait_for_timeout", timeoutMs: 1500 },
          { type: "screenshot", label: "landing", fullPage: true },
        ],
        visionPrompt: "Summarize the visible page state.",
      };
      const job = await queue.add("whatsapp-browser-job", payload, {
        attempts: 1,
        removeOnComplete: 100,
        removeOnFail: 100,
      });
      return `Job queued.\njobId=${job.id}\nurl=${payload.startUrl}`;
    } catch {
      return "Invalid URL. Usage: run https://example.com";
    }
  }

  if (trimmed.startsWith("job ")) {
    const jobId = trimmed.replace("job ", "").trim();
    if (!jobId) {
      return "Usage: job <jobId>";
    }
    const job = await queue.getJob(jobId);
    if (!job) {
      return `No job found for id=${jobId}`;
    }
    const state = await job.getState();
    return `jobId=${jobId}\nstate=${state}`;
  }

  return "Unknown command. Use help.";
};

const requireInternalApiToken = (request: FastifyRequest): void => {
  if (!appConfig.internalApiToken) {
    return;
  }

  const authHeader = request.headers.authorization;
  if (authHeader !== `Bearer ${appConfig.internalApiToken}`) {
    throw new AppError("UNAUTHORIZED", "Missing or invalid Authorization header.", 401);
  }
};

const sendError = (
  reply: FastifyReply,
  statusCode: number,
  code: string,
  message: string,
  requestId: string,
): FastifyReply => {
  const errorBody: ApiErrorBody = {
    error: {
      code,
      message,
      requestId,
    },
  };
  return reply.code(statusCode).send(errorBody);
};

const start = async (): Promise<void> => {
  try {
    await app.listen({
      host: appConfig.host,
      port: appConfig.port,
    });
    logger.info(
      {
        host: appConfig.host,
        port: appConfig.port,
        env: appConfig.env,
      },
      "Lippyclaw API started.",
    );
  } catch (error) {
    logger.error({ err: error }, "Failed to start Lippyclaw API.");
    process.exit(1);
  }
};

const shutdown = async (): Promise<void> => {
  logger.info("Shutting down Lippyclaw API.");
  await app.close();
  await queue.close();
  await redisConnection.quit();
};

process.on("SIGINT", () => {
  void shutdown().finally(() => process.exit(0));
});

process.on("SIGTERM", () => {
  void shutdown().finally(() => process.exit(0));
});

void start();

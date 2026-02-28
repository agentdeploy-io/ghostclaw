import { randomUUID } from "node:crypto";

import { Worker } from "bullmq";

import { appConfig } from "./config.js";
import { createRedisConnection, AUTOMATION_QUEUE_NAME } from "./lib/queue.js";
import { OpenAICompatibleClient } from "./lib/openai-compatible.js";
import { sendTelegramMessage } from "./lib/telegram.js";
import { logger } from "./logger.js";
import { runBrowserJob } from "./automation/run-browser-job.js";
import type { AutomationJobPayload, AutomationJobResult } from "./types.js";

const connection = createRedisConnection(appConfig.redisUrl);

const mainAgentClient = new OpenAICompatibleClient(
  appConfig.mainLlm.baseUrl,
  appConfig.mainLlm.apiKey,
  appConfig.mainLlm.model,
  appConfig.llmTimeoutMs,
);

const subAgentClient = new OpenAICompatibleClient(
  appConfig.subLlm.baseUrl,
  appConfig.subLlm.apiKey,
  appConfig.subLlm.model,
  appConfig.llmTimeoutMs,
);

const worker = new Worker<AutomationJobPayload, AutomationJobResult>(
  AUTOMATION_QUEUE_NAME,
  async (job) => {
    const requestId = randomUUID();
    logger.info(
      {
        requestId,
        jobId: job.id,
        jobName: job.data.jobName,
      },
      "Worker started processing job.",
    );

    const result = await runBrowserJob(
      job.data,
      {
        config: appConfig,
        logger,
        mainAgentClient,
        subAgentClient,
      },
      {
        requestId,
        jobId: String(job.id),
      },
    );

    if (
      appConfig.telegram.enabled &&
      appConfig.telegram.botToken &&
      typeof job.data.chatId === "number"
    ) {
      const message = [
        `Job complete: ${job.data.jobName}`,
        `jobId=${job.id}`,
        `status=${result.status}`,
        `summary=${result.summary}`,
      ].join("\n");

      try {
        await sendTelegramMessage(appConfig.telegram.botToken, job.data.chatId, message);
      } catch (error) {
        logger.error(
          {
            err: error,
            requestId,
            jobId: job.id,
            chatId: job.data.chatId,
          },
          "Failed to send Telegram completion message.",
        );
      }
    }

    logger.info(
      {
        requestId,
        jobId: job.id,
        status: result.status,
      },
      "Worker finished job.",
    );

    return result;
  },
  {
    connection,
    concurrency: appConfig.workerConcurrency,
  },
);

worker.on("failed", (job, error) => {
  logger.error(
    {
      err: error,
      jobId: job?.id,
      jobName: job?.name,
    },
    "Worker job failed.",
  );
});

worker.on("error", (error) => {
  logger.error({ err: error }, "Worker runtime error.");
});

const shutdown = async (): Promise<void> => {
  logger.info("Shutting down worker.");
  await worker.close();
  await connection.quit();
};

process.on("SIGINT", () => {
  void shutdown().finally(() => process.exit(0));
});

process.on("SIGTERM", () => {
  void shutdown().finally(() => process.exit(0));
});

logger.info(
  {
    queue: AUTOMATION_QUEUE_NAME,
    concurrency: appConfig.workerConcurrency,
  },
  "Worker started.",
);

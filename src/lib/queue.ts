import IORedis from "ioredis";
import { Queue, QueueEvents } from "bullmq";

import { AutomationJobPayload, AutomationJobResult } from "../types.js";

export const AUTOMATION_QUEUE_NAME = "ghostclaw-automation-jobs";

export const createRedisConnection = (redisUrl: string): IORedis =>
  new IORedis(redisUrl, {
    maxRetriesPerRequest: null,
    enableReadyCheck: false,
  });

export const createAutomationQueue = (
  connection: IORedis,
): Queue<AutomationJobPayload, AutomationJobResult> =>
  new Queue<AutomationJobPayload, AutomationJobResult>(AUTOMATION_QUEUE_NAME, {
    connection,
  });

export const createAutomationQueueEvents = (
  connection: IORedis,
): QueueEvents =>
  new QueueEvents(AUTOMATION_QUEUE_NAME, {
    connection,
  });

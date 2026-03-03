import { logger } from "../logger.js";

export interface SlackConfig {
  signingSecret: string;
  botToken: string;
  appToken: string;
}

export interface SlackMessage {
  channelId: string;
  userId: string;
  text: string;
  threadTs?: string;
}

let slackBotToken: string | null = null;

export function initializeSlack(config: SlackConfig): void {
  slackBotToken = config.botToken;
  logger.info({ channel: "slack" }, "Slack integration initialized");
}

export async function sendSlackMessage(
  channelId: string,
  text: string,
  threadTs?: string,
): Promise<void> {
  if (!slackBotToken) {
    throw new Error("Slack not initialized - missing bot token");
  }

  const response = await fetch("https://slack.com/api/chat.postMessage", {
    method: "POST",
    headers: {
      "Content-Type": "application/json",
      Authorization: `Bearer ${slackBotToken}`,
    },
    body: JSON.stringify({
      channel: channelId,
      text,
      thread_ts: threadTs,
    }),
  });

  if (!response.ok) {
    const error = await response.text();
    throw new Error(`Slack API error (${response.status}): ${error.slice(0, 300)}`);
  }

  const result = await response.json();
  if (!result.ok) {
    throw new Error(`Slack API error: ${result.error}`);
  }

  logger.info({ channelId, threadTs }, "Slack message sent");
}

export function getSlackBotToken(): string | null {
  return slackBotToken;
}

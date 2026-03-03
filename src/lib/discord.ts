import { logger } from "../logger.js";

export interface DiscordConfig {
  botToken: string;
  clientId: string;
}

let discordBotToken: string | null = null;
let discordClientId: string | null = null;

export function initializeDiscord(config: DiscordConfig): void {
  discordBotToken = config.botToken;
  discordClientId = config.clientId;
  logger.info({ clientId: config.clientId }, "Discord integration initialized");
}

export async function sendDiscordMessage(
  channelId: string,
  text: string,
): Promise<void> {
  if (!discordBotToken) {
    throw new Error("Discord not initialized - missing bot token");
  }

  const response = await fetch(
    `https://discord.com/api/v10/channels/${channelId}/messages`,
    {
      method: "POST",
      headers: {
        "Content-Type": "application/json",
        Authorization: `Bot ${discordBotToken}`,
      },
      body: JSON.stringify({
        content: text,
      }),
    },
  );

  if (!response.ok) {
    const error = await response.text();
    throw new Error(`Discord API error (${response.status}): ${error.slice(0, 300)}`);
  }

  logger.info({ channelId }, "Discord message sent");
}

export function getDiscordBotToken(): string | null {
  return discordBotToken;
}

export function getDiscordClientId(): string | null {
  return discordClientId;
}

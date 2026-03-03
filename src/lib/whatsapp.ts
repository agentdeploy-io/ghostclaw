import { logger } from "../logger.js";

export interface WhatsAppConfig {
  phoneNumberId: string;
  accessToken: string;
  verifyToken: string;
}

const BASE_URL = "https://graph.facebook.com/v18.0";

let whatsappPhoneNumberId: string | null = null;
let whatsappAccessToken: string | null = null;
let whatsappVerifyToken: string | null = null;

export function initializeWhatsApp(config: WhatsAppConfig): void {
  whatsappPhoneNumberId = config.phoneNumberId;
  whatsappAccessToken = config.accessToken;
  whatsappVerifyToken = config.verifyToken;
  logger.info({ phoneNumberId: config.phoneNumberId }, "WhatsApp integration initialized");
}

export async function sendWhatsAppMessage(
  recipientId: string,
  text: string,
): Promise<void> {
  if (!whatsappPhoneNumberId || !whatsappAccessToken) {
    throw new Error("WhatsApp not initialized - missing credentials");
  }

  const url = `${BASE_URL}/${whatsappPhoneNumberId}/messages`;

  const response = await fetch(url, {
    method: "POST",
    headers: {
      "Content-Type": "application/json",
      Authorization: `Bearer ${whatsappAccessToken}`,
    },
    body: JSON.stringify({
      messaging_product: "whatsapp",
      to: recipientId,
      type: "text",
      text: { body: text },
    }),
  });

  if (!response.ok) {
    const error = await response.text();
    throw new Error(`WhatsApp API error (${response.status}): ${error.slice(0, 300)}`);
  }

  logger.info({ recipientId }, "WhatsApp message sent");
}

export async function verifyWhatsAppWebhook(
  mode: string,
  token: string,
): Promise<string | null> {
  if (mode === "subscribe" && token === whatsappVerifyToken) {
    return token;
  }
  return null;
}

export function getWhatsAppPhoneNumberId(): string | null {
  return whatsappPhoneNumberId;
}

export function getWhatsAppAccessToken(): string | null {
  return whatsappAccessToken;
}

export function getWhatsAppVerifyToken(): string | null {
  return whatsappVerifyToken;
}

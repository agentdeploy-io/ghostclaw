import { AppError } from "../errors.js";

export const sendTelegramMessage = async (
  botToken: string,
  chatId: number,
  text: string,
): Promise<void> => {
  const response = await fetch(
    `https://api.telegram.org/bot${botToken}/sendMessage`,
    {
      method: "POST",
      headers: {
        "content-type": "application/json",
      },
      body: JSON.stringify({
        chat_id: chatId,
        text,
        disable_web_page_preview: true,
      }),
    },
  );

  if (!response.ok) {
    const errorText = await response.text();
    throw new AppError(
      "TELEGRAM_SEND_FAILED",
      `Telegram API error (${response.status}): ${errorText.slice(0, 300)}`,
      502,
    );
  }
};

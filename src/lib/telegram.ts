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

export const sendTelegramVoiceNote = async (
  botToken: string,
  chatId: number,
  voiceData: Buffer,
  caption?: string,
): Promise<void> => {
  const formData = new FormData();
  formData.append("chat_id", chatId.toString());
  
  const blob = new Blob([voiceData], { type: "audio/wav" });
  formData.append("voice", blob, "voice.wav");
  
  if (caption) {
    formData.append("caption", caption);
  }

  const response = await fetch(
    `https://api.telegram.org/bot${botToken}/sendVoice`,
    {
      method: "POST",
      headers: {
        "Authorization": `Bot ${botToken}`,
      },
      body: formData,
    },
  );

  if (!response.ok) {
    const errorText = await response.text();
    throw new AppError(
      "TELEGRAM_SEND_VOICE_FAILED",
      `Telegram API error (${response.status}): ${errorText.slice(0, 300)}`,
      502,
    );
  }
};

export const downloadTelegramFile = async (
  botToken: string,
  fileId: string,
): Promise<Buffer> => {
  // Step 1: Get file info
  const fileInfoResponse = await fetch(
    `https://api.telegram.org/bot${botToken}/getFile?file_id=${fileId}`,
  );

  if (!fileInfoResponse.ok) {
    const errorText = await fileInfoResponse.text();
    throw new AppError(
      "TELEGRAM_FILE_INFO_FAILED",
      `Telegram API error (${fileInfoResponse.status}): ${errorText.slice(0, 300)}`,
      502,
    );
  }

  const fileInfo = await fileInfoResponse.json() as { ok: boolean; result: { file_path: string } };
  
  if (!fileInfo.ok || !fileInfo.result?.file_path) {
    throw new AppError(
      "TELEGRAM_FILE_INFO_FAILED",
      "Failed to get file path from Telegram",
      502,
    );
  }

  // Step 2: Download the file
  const fileUrl = `https://api.telegram.org/file/bot${botToken}/${fileInfo.result.file_path}`;
  const fileResponse = await fetch(fileUrl);

  if (!fileResponse.ok) {
    throw new AppError(
      "TELEGRAM_FILE_DOWNLOAD_FAILED",
      `Failed to download file (${fileResponse.status})`,
      502,
    );
  }

  const arrayBuffer = await fileResponse.arrayBuffer();
  return Buffer.from(arrayBuffer);
};

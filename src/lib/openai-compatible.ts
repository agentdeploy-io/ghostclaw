export type ChatRole = "system" | "user" | "assistant";

export type ChatContentPart =
  | {
      type: "text";
      text: string;
    }
  | {
      type: "image_url";
      image_url: {
        url: string;
      };
    };

export interface ChatMessage {
  role: ChatRole;
  content: string | ChatContentPart[];
}

interface ChatCompletionsResponse {
  choices: Array<{
    message: {
      content: string | Array<{ type?: string; text?: string }> | null;
      reasoning_content?: string | null;
    };
  }>;
}

class LlmRequestError extends Error {
  public readonly retryable: boolean;
  public readonly statusCode?: number;

  public constructor(message: string, retryable: boolean, statusCode?: number) {
    super(message);
    this.name = "LlmRequestError";
    this.retryable = retryable;
    this.statusCode = statusCode;
  }
}

export class OpenAICompatibleClient {
  private readonly baseUrl: string;
  private readonly apiKey: string;
  private readonly model: string;
  private readonly timeoutMs: number;

  public constructor(
    baseUrl: string,
    apiKey: string,
    model: string,
    timeoutMs: number,
  ) {
    this.baseUrl = baseUrl.replace(/\/$/, "");
    this.apiKey = apiKey;
    this.model = model;
    this.timeoutMs = timeoutMs;
  }

  public async chat(
    messages: ChatMessage[],
    temperature = 0.2,
    maxTokens = 800,
  ): Promise<string> {
    const maxAttempts = 3;
    let attempt = 1;

    while (attempt <= maxAttempts) {
      try {
        return await this.sendChatRequest(messages, temperature, maxTokens);
      } catch (error) {
        const normalized = this.normalizeError(error);
        const shouldRetry = normalized.retryable && attempt < maxAttempts;
        if (!shouldRetry) {
          throw normalized;
        }
        const delayMs = this.computeRetryDelayMs(attempt);
        await this.sleep(delayMs);
        attempt += 1;
      }
    }

    throw new Error("LLM request failed after retry attempts.");
  }

  private async sendChatRequest(
    messages: ChatMessage[],
    temperature: number,
    maxTokens: number,
  ): Promise<string> {
    const controller = new AbortController();
    const timeout = setTimeout(() => controller.abort(), this.timeoutMs);

    try {
      const response = await fetch(`${this.baseUrl}/chat/completions`, {
        method: "POST",
        headers: {
          "content-type": "application/json",
          authorization: `Bearer ${this.apiKey}`,
        },
        body: JSON.stringify({
          model: this.model,
          messages,
          temperature,
          max_tokens: maxTokens,
        }),
        signal: controller.signal,
      });

      if (!response.ok) {
        const errorText = await response.text();
        throw new LlmRequestError(
          `LLM request failed (${response.status}): ${errorText.slice(0, 300)}`,
          this.isRetryableStatus(response.status),
          response.status,
        );
      }

      const data = (await response.json()) as ChatCompletionsResponse;
      const firstChoice = data.choices[0];
      if (!firstChoice) {
        throw new LlmRequestError(
          "LLM response did not include choices[0].",
          false,
        );
      }
      return this.extractText(firstChoice.message);
    } catch (error) {
      if (error instanceof Error && error.name === "AbortError") {
        throw new LlmRequestError(
          `LLM request timed out after ${this.timeoutMs}ms (${this.baseUrl}).`,
          false,
        );
      }
      throw error;
    } finally {
      clearTimeout(timeout);
    }
  }

  private isRetryableStatus(status: number): boolean {
    return [408, 409, 425, 429, 500, 502, 503, 504].includes(status);
  }

  private normalizeError(error: unknown): LlmRequestError {
    if (error instanceof LlmRequestError) {
      return error;
    }
    if (error instanceof Error) {
      return new LlmRequestError(error.message, false);
    }
    return new LlmRequestError("Unknown LLM request error.", false);
  }

  private computeRetryDelayMs(attempt: number): number {
    return Math.min(1000 * 2 ** (attempt - 1), 5000);
  }

  private async sleep(delayMs: number): Promise<void> {
    await new Promise((resolve) => setTimeout(resolve, delayMs));
  }

  private extractText(message: {
    content: string | Array<{ type?: string; text?: string }> | null;
    reasoning_content?: string | null;
  }): string {
    const content = message.content;

    if (typeof content === "string") {
      return content.trim();
    }

    const textParts = Array.isArray(content)
      ? content
          .filter((part) => part.type === "text" && typeof part.text === "string")
          .map((part) => part.text as string)
      : [];

    const extracted = textParts.join("\n").trim();
    if (extracted.length > 0) {
      return extracted;
    }

    if (typeof message.reasoning_content === "string") {
      return message.reasoning_content.trim();
    }

    return "";
  }
}

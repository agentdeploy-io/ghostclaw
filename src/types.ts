export type BrowserAction =
  | {
      type: "goto";
      url: string;
    }
  | {
      type: "wait_for_selector";
      selector: string;
      timeoutMs?: number;
    }
  | {
      type: "click";
      selector: string;
    }
  | {
      type: "fill";
      selector: string;
      value: string;
    }
  | {
      type: "press";
      selector: string;
      key: string;
    }
  | {
      type: "click_xy";
      x: number;
      y: number;
    }
  | {
      type: "wait_for_timeout";
      timeoutMs: number;
    }
  | {
      type: "screenshot";
      label: string;
      fullPage?: boolean;
    };

export interface AutomationJobPayload {
  jobName: string;
  startUrl: string;
  actions: BrowserAction[];
  visionPrompt?: string;
  chatId?: number;
}

export interface AutomationJobResult {
  status: "completed" | "human_required" | "failed";
  summary: string;
  artifacts: string[];
  mainAgentOutput?: string;
  subAgentOutput?: string;
  challengeReason?: string;
}

export interface ApiErrorBody {
  error: {
    code: string;
    message: string;
    requestId: string;
  };
}

export interface TelegramUpdate {
  update_id: number;
  message?: {
    message_id: number;
    text?: string;
    chat: {
      id: number;
      type: string;
    };
    from?: {
      id: number;
      username?: string;
    };
  };
}

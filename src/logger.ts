import pino from "pino";

import { appConfig } from "./config.js";

export const logger = pino({
  level: appConfig.logLevel,
  redact: {
    paths: [
      "req.headers.authorization",
      "req.headers.cookie",
      "config.mainLlm.apiKey",
      "config.subLlm.apiKey",
      "config.telegram.botToken",
      "config.telegram.webhookSecret",
    ],
    remove: true,
  },
});

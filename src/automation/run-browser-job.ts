import { mkdir, readFile } from "node:fs/promises";
import path from "node:path";

import { Camoufox } from "camoufox-js";
import type { Logger } from "pino";
import { chromium, firefox, type Browser, type BrowserContext, type Page } from "playwright";

import type { AppConfig } from "../config.js";
import { HumanInterventionRequiredError } from "../errors.js";
import type {
  AutomationJobPayload,
  AutomationJobResult,
  BrowserAction,
} from "../types.js";
import {
  OpenAICompatibleClient,
  type ChatMessage,
} from "../lib/openai-compatible.js";
import { detectChallenge } from "./challenge-detector.js";

interface RunBrowserJobDependencies {
  config: AppConfig;
  logger: Logger;
  mainAgentClient: OpenAICompatibleClient;
  subAgentClient: OpenAICompatibleClient;
}

interface RunBrowserJobOptions {
  requestId: string;
  jobId: string;
}

export const runBrowserJob = async (
  payload: AutomationJobPayload,
  dependencies: RunBrowserJobDependencies,
  options: RunBrowserJobOptions,
): Promise<AutomationJobResult> => {
  const { config, logger } = dependencies;

  const jobArtifactDir = path.join(config.artifactDir, options.jobId);
  await mkdir(jobArtifactDir, { recursive: true });

  let browser: Browser | undefined;
  let context: BrowserContext | undefined;
  let page: Page | undefined;

  const artifacts: string[] = [];
  let lastScreenshotPath: string | undefined;

  try {
    const browserSession = await createBrowserSession(config, logger);
    browser = browserSession.browser;
    context = browserSession.context;
    page = browserSession.page;

    page.setDefaultTimeout(config.browser.defaultTimeoutMs);

    const startActions: BrowserAction[] = [
      { type: "goto", url: payload.startUrl },
      ...payload.actions,
    ];

    for (const action of startActions) {
      lastScreenshotPath = await executeAction(
        page,
        action,
        jobArtifactDir,
        options.jobId,
      );
      if (lastScreenshotPath) {
        artifacts.push(lastScreenshotPath);
      }

      if (action.type !== "wait_for_timeout") {
        const challenge = await detectChallenge(
          page,
          config.browser.challengeKeywords,
        );
        if (challenge.detected) {
          const challengeShot = await saveScreenshot(
            page,
            jobArtifactDir,
            `${options.jobId}-challenge`,
            true,
          );
          artifacts.push(challengeShot);
          throw new HumanInterventionRequiredError(
            challenge.reason ?? "Challenge detected during browser flow.",
            artifacts,
          );
        }
      }
    }

    let mainAgentOutput: string | undefined;
    let subAgentOutput: string | undefined;
    if (payload.visionPrompt && lastScreenshotPath) {
      const screenshotBase64 = await readFile(lastScreenshotPath, {
        encoding: "base64",
      });
      mainAgentOutput = await runMainAgentVisionPass(
        dependencies.mainAgentClient,
        payload.visionPrompt,
        screenshotBase64,
      );
      subAgentOutput = await runSubAgentPass(
        dependencies.subAgentClient,
        payload.visionPrompt,
        mainAgentOutput,
      );
    }

    return {
      status: "completed",
      summary: "Browser job completed successfully.",
      artifacts,
      mainAgentOutput,
      subAgentOutput,
    };
  } catch (error) {
    if (error instanceof HumanInterventionRequiredError) {
      return {
        status: "human_required",
        summary:
          "Challenge detected. Human intervention required before safe resume.",
        artifacts: error.artifacts,
        challengeReason: error.reason,
      };
    }

    logger.error(
      { err: error, requestId: options.requestId, jobId: options.jobId },
      "Browser job failed.",
    );
    return {
      status: "failed",
      summary: error instanceof Error ? error.message : "Unknown browser error.",
      artifacts,
    };
  } finally {
    await closeBrowserSession(browser, context, page, logger, options);
  }
};

const createBrowserSession = async (
  config: AppConfig,
  logger: Logger,
): Promise<{ browser: Browser; context: BrowserContext; page: Page }> => {
  if (config.browser.provider === "camoufox") {
    logger.info(
      {
        browserProvider: config.browser.provider,
        wsEndpoint: config.browser.camoufoxWsEndpoint,
        connectTimeoutMs: config.browser.camoufoxConnectTimeoutMs,
        headless: config.browser.headless,
      },
      "Launching Camoufox browser session.",
    );

    const browser = config.browser.camoufoxWsEndpoint
      ? await firefox.connect(config.browser.camoufoxWsEndpoint, {
          timeout: config.browser.camoufoxConnectTimeoutMs,
        })
      : ((await Camoufox({
          headless: config.browser.headless,
        })) as unknown as Browser);

    const context =
      browser.contexts()[0] ??
      (await browser.newContext({
        viewport: { width: 1366, height: 900 },
      }));

    const page = context.pages()[0] ?? (await context.newPage());
    return { browser, context, page };
  }

  logger.info(
    {
      browserProvider: config.browser.provider,
      executablePath: config.browser.executablePath,
      headless: config.browser.headless,
    },
    "Launching local Chromium browser.",
  );

  const browser = await chromium.launch({
    headless: config.browser.headless,
    executablePath: config.browser.executablePath,
  });

  const context = await browser.newContext({
    viewport: { width: 1366, height: 900 },
  });

  const page = await context.newPage();
  return { browser, context, page };
};

const closeBrowserSession = async (
  browser: Browser | undefined,
  context: BrowserContext | undefined,
  page: Page | undefined,
  logger: Logger,
  options: RunBrowserJobOptions,
): Promise<void> => {
  if (!browser) {
    return;
  }

  try {
    if (page) {
      await page.close();
    }
  } catch (error) {
    logger.warn(
      { err: error, requestId: options.requestId, jobId: options.jobId },
      "Failed to close browser page cleanly.",
    );
  }

  try {
    if (context) {
      await context.close();
    }
  } catch (error) {
    logger.warn(
      { err: error, requestId: options.requestId, jobId: options.jobId },
      "Failed to close browser context cleanly.",
    );
  }

  try {
    await browser.close();
  } catch (error) {
    logger.warn(
      { err: error, requestId: options.requestId, jobId: options.jobId },
      "Failed to close browser connection cleanly.",
    );
  }
};

const executeAction = async (
  page: Page,
  action: BrowserAction,
  artifactDir: string,
  jobId: string,
): Promise<string | undefined> => {
  switch (action.type) {
    case "goto":
      await page.goto(action.url, { waitUntil: "domcontentloaded" });
      return undefined;
    case "wait_for_selector":
      await page.waitForSelector(action.selector, {
        timeout: action.timeoutMs,
      });
      return undefined;
    case "click":
      await page.click(action.selector);
      return undefined;
    case "fill":
      await page.fill(action.selector, action.value);
      return undefined;
    case "press":
      await page.press(action.selector, action.key);
      return undefined;
    case "click_xy":
      await page.mouse.click(action.x, action.y);
      return undefined;
    case "wait_for_timeout":
      await page.waitForTimeout(action.timeoutMs);
      return undefined;
    case "screenshot":
      return saveScreenshot(
        page,
        artifactDir,
        `${jobId}-${sanitizeLabel(action.label)}`,
        action.fullPage ?? true,
      );
    default: {
      const neverAction: never = action;
      throw new Error(`Unhandled action type: ${JSON.stringify(neverAction)}`);
    }
  }
};

const saveScreenshot = async (
  page: Page,
  artifactDir: string,
  filePrefix: string,
  fullPage: boolean,
): Promise<string> => {
  const timestamp = new Date().toISOString().replace(/[:.]/g, "-");
  const outputPath = path.join(artifactDir, `${filePrefix}-${timestamp}.png`);
  await page.screenshot({
    path: outputPath,
    fullPage,
  });
  return outputPath;
};

const sanitizeLabel = (input: string): string =>
  input.replace(/[^a-zA-Z0-9_-]/g, "-").toLowerCase();

const runMainAgentVisionPass = async (
  client: OpenAICompatibleClient,
  prompt: string,
  screenshotBase64: string,
): Promise<string> => {
  const messages: ChatMessage[] = [
    {
      role: "system",
      content:
        "You are the main automation analyst. Summarize visible UI state and actionable next steps for a human operator.",
    },
    {
      role: "user",
      content: [
        {
          type: "text",
          text: prompt,
        },
        {
          type: "image_url",
          image_url: {
            url: `data:image/png;base64,${screenshotBase64}`,
          },
        },
      ],
    },
  ];

  return client.chat(messages, 0.2, 900);
};

const runSubAgentPass = async (
  client: OpenAICompatibleClient,
  originalPrompt: string,
  mainAgentOutput: string,
): Promise<string> => {
  const messages: ChatMessage[] = [
    {
      role: "system",
      content:
        "You are the sub-agent. Convert the main agent analysis into concise operational steps and a next-action checklist.",
    },
    {
      role: "user",
      content: `Prompt:\n${originalPrompt}\n\nMain agent output:\n${mainAgentOutput}`,
    },
  ];

  return client.chat(messages, 0.1, 600);
};

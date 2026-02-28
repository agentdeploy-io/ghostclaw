import type { Page } from "playwright";

const challengeSelectors = [
  "iframe[src*='captcha']",
  "iframe[title*='challenge']",
  "input[name*='captcha']",
  "[id*='captcha']",
  "[class*='captcha']",
  "[data-testid*='captcha']",
  "input[autocomplete='one-time-code']",
];

export interface ChallengeCheckResult {
  detected: boolean;
  reason?: string;
}

export const detectChallenge = async (
  page: Page,
  keywords: string[],
): Promise<ChallengeCheckResult> => {
  for (const selector of challengeSelectors) {
    const count = await page.locator(selector).count();
    if (count > 0) {
      return {
        detected: true,
        reason: `Detected challenge selector: ${selector}`,
      };
    }
  }

  const bodyText = (await page.locator("body").innerText()).toLowerCase();
  const matchedKeyword = keywords.find((keyword) => bodyText.includes(keyword));
  if (matchedKeyword) {
    return {
      detected: true,
      reason: `Detected challenge keyword: ${matchedKeyword}`,
    };
  }

  return { detected: false };
};

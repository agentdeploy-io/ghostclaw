import { z } from "zod";

export const browserActionSchema = z.discriminatedUnion("type", [
  z.object({
    type: z.literal("goto"),
    url: z.string().url(),
  }),
  z.object({
    type: z.literal("wait_for_selector"),
    selector: z.string().min(1),
    timeoutMs: z.number().int().positive().optional(),
  }),
  z.object({
    type: z.literal("click"),
    selector: z.string().min(1),
  }),
  z.object({
    type: z.literal("fill"),
    selector: z.string().min(1),
    value: z.string(),
  }),
  z.object({
    type: z.literal("press"),
    selector: z.string().min(1),
    key: z.string().min(1),
  }),
  z.object({
    type: z.literal("click_xy"),
    x: z.number().int().nonnegative(),
    y: z.number().int().nonnegative(),
  }),
  z.object({
    type: z.literal("wait_for_timeout"),
    timeoutMs: z.number().int().min(1),
  }),
  z.object({
    type: z.literal("screenshot"),
    label: z.string().min(1),
    fullPage: z.boolean().optional(),
  }),
]);

export const createJobSchema = z.object({
  jobName: z.string().min(2).max(120),
  startUrl: z.string().url(),
  actions: z.array(browserActionSchema).min(1),
  visionPrompt: z.string().max(2_000).optional(),
  chatId: z.number().int().optional(),
});

export const telegramUpdateSchema = z.object({
  update_id: z.number(),
  message: z
    .object({
      message_id: z.number(),
      text: z.string().optional(),
      chat: z.object({
        id: z.number(),
        type: z.string(),
      }),
      from: z
        .object({
          id: z.number(),
          username: z.string().optional(),
        })
        .optional(),
    })
    .optional(),
});

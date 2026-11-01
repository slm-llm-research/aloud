import { z } from "zod";
import { defineTool } from "./contract.js";

export const PLAN_STATUS = ["pending", "inProgress", "completed", "canceled", "failed"] as const;

const planInput = z.object({
  steps: z
    .array(z.object({ content: z.string().min(1).max(120), status: z.enum(PLAN_STATUS) }))
    .min(1)
    .max(12),
});

export type Plan = z.infer<typeof planInput>["steps"];

/**
 * The plan the user sees in the agent island. Nothing on the machine changes, so no approval; the
 * agent loop turns each call into a task.plan event (the whole list every time).
 */
export const updatePlan = defineTool({
  name: "update_plan",
  description:
    "Show the user your plan as a short checklist. Call it first for any task with more than one step, " +
    "and again whenever a step starts, finishes or the plan changes. Send the whole list each time; " +
    "keep each step under 10 words.",
  input: planInput,
  effects: () => [],
  preview: (i) => i.steps.map((s) => `${s.status === "completed" ? "✓" : "○"} ${s.content}`).join("\n"),
  title: () => "Update plan",
  async run() {
    return "Plan shown to the user.";
  },
});

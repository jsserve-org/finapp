import { z } from "zod";

export type Candidate = { id: string; label: string };

const jevResult = z.object({
  answers: z.object({ next: z.object({ type: z.literal("choice"), choice: z.string(), confidence: z.number() }) }),
});

export async function chooseNavigation(candidates: Candidate[], apiKey: string, model: string, goal: string): Promise<string | null> {
  if (candidates.length === 0) return null;
  const criteria = Object.fromEntries([
    ...candidates.map(({ id, label }) => [id, label]),
    ["stop", "No listed control safely leads to the requested read-only account view"],
  ]);
  const response = await fetch("https://api.typesafe.ai/v1/systemone", {
    method: "POST",
    headers: { authorization: `Bearer ${apiKey}`, "content-type": "application/json" },
    body: JSON.stringify({
      model,
      state: { goal, candidates },
      questions: { next: {
        type: "choice",
        instructions: "Choose a read-only control toward the requested account view. Never place an order, transfer funds, change settings, or alter an account. Choose stop if uncertain.",
        criteria,
      } },
    }),
  });
  if (!response.ok) throw new Error(`TypeSafe Jev request failed (${response.status})`);
  const choice = jevResult.parse(await response.json()).answers.next;
  return choice.choice !== "stop" && choice.confidence >= 0.65 && candidates.some((item) => item.id === choice.choice)
    ? choice.choice : null;
}

const openRouterResult = z.object({ choices: z.array(z.object({ message: z.object({ content: z.union([
  z.string(), z.array(z.object({ type: z.string(), text: z.string().optional() })),
]) }) })).min(1) });

export async function readImageCode(image: Buffer, apiKey: string, model: string): Promise<string> {
  const response = await fetch("https://openrouter.ai/api/v1/chat/completions", {
    method: "POST",
    headers: { authorization: `Bearer ${apiKey}`, "content-type": "application/json" },
    body: JSON.stringify({ model, temperature: 0, messages: [{ role: "user", content: [
      { type: "text", text: "Read only the visible verification characters in this image. Reply with the characters alone. If unclear, reply UNKNOWN." },
      { type: "image_url", image_url: { url: `data:image/png;base64,${image.toString("base64")}` } },
    ] }] }),
  });
  if (!response.ok) throw new Error(`OpenRouter image-code request failed (${response.status})`);
  const content = openRouterResult.parse(await response.json()).choices[0]!.message.content;
  const value = (typeof content === "string" ? content : content.map((part) => part.text ?? "").join("")).trim();
  if (!/^[A-Za-z0-9]{4,8}$/.test(value) || value === "UNKNOWN") throw new Error("Luna could not read the image code");
  return value;
}

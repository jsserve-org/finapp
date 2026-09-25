import { resolve } from "node:path";
import { z } from "zod";
import { LedgerlyImporter } from "./ledgerly";

const config = z.object({
  LEDGERLY_API_URL: z.string().url(),
  LEDGERLY_API_KEY: z.string().min(1),
}).parse(process.env);
const filename = process.argv[2];
if (!filename) throw new Error("Pass a TCStock trades JSON filename");
const snapshot = z.object({
  source: z.literal("tcstock"),
  capturedAt: z.string(),
  period: z.object({ start: z.string(), end: z.string() }),
  headers: z.array(z.string()),
  rows: z.array(z.array(z.string())),
}).parse(await Bun.file(resolve(filename)).json());
const result = await new LedgerlyImporter(config.LEDGERLY_API_URL, config.LEDGERLY_API_KEY).import(snapshot);
console.log(`Ledgerly synced ${result.imported} new stock trade(s); ${result.existing} already present`);

import { z } from "zod";

const configSchema = z.object({
  PORT: z.coerce.number().int().positive().default(3000),
  PUBLIC_API_URL: z.string().url().default("http://localhost:3000"),
  CONVEX_URL: z.string().url().default("http://localhost:3210"),
  PUBLIC_CONVEX_URL: z.string().url().default("http://localhost:3210"),
  API_SERVICE_SECRET: z.string().min(32).default("0000000000000000000000000000000000000000000000000000000000000001"),
  ALLOW_REGISTRATION: z.string().default("true").transform((value) => value === "true"),
  API_VERSION: z.string().default("0.6.12"),
  SYNC_PROTOCOL_VERSION: z.coerce.number().int().positive().default(2),
  MINIMUM_APP_VERSION: z.string().default("0.4.0"),
  LATEST_APP_VERSION: z.string().default("0.6.12"),
});

export const config = configSchema.parse(process.env);

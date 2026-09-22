import { z } from "zod";

const configSchema = z.object({
  DATABASE_URL: z.string().url().default("postgres://ledgerly:ledgerly@localhost:55432/ledgerly"),
  PORT: z.coerce.number().int().positive().default(3000),
  API_TOKEN: z.string().min(16).default("local-development-token"),
});

export const config = configSchema.parse(process.env);

import { drizzle } from "drizzle-orm/postgres-js";
import postgres from "postgres";
import { config } from "../config";
import * as schema from "./schema";

export const client = postgres(config.DATABASE_URL, { max: 10, idle_timeout: 20 });
export const db = drizzle(client, { schema });

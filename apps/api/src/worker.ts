import { lte } from "drizzle-orm";
import { DemoBankProvider } from "./automation/provider";
import { runConnection } from "./automation/service";
import { db } from "./db";
import { bankConnections } from "./db/schema";

let checking = false;

async function checkDueConnections() {
  if (checking) return;
  checking = true;
  try {
    const due = await db.select().from(bankConnections).where(lte(bankConnections.nextCheckAt, new Date())).limit(25);
    for (const connection of due) {
      try {
        if (connection.provider !== "demo") throw new Error(`UNSUPPORTED_PROVIDER:${connection.provider}`);
        await runConnection(connection.id, connection.userId, new DemoBankProvider());
      } catch (error) {
        console.error(JSON.stringify({ event: "automation_check_failed", connectionId: connection.id, message: error instanceof Error ? error.message : "unknown" }));
      }
    }
  } finally { checking = false; }
}

await checkDueConnections();
setInterval(checkDueConnections, 60_000);
console.log("Ledgerly automation self-check worker started");

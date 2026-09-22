import { query } from "./_generated/server";
export const health = query({ args: {}, handler: async () => ({ status: "ok" }) });

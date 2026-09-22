import { app } from "./app";
import { config } from "./config";

export default { port: config.PORT, fetch: app.fetch };

console.log(`Ledgerly API listening on http://localhost:${config.PORT}`);

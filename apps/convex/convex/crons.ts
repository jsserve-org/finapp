import { cronJobs, makeFunctionReference } from "convex/server";

const crons = cronJobs();
crons.interval("Create due subscription records", { minutes: 15 }, makeFunctionReference<"mutation">("recurring:generateDue"), {});
export default crons;

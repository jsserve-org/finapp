export {};
const response = await fetch("http://127.0.0.1:8081/internal/run", { method: "POST" });
if (response.status === 409) {
  console.log("TCStock sync is already running");
} else if (!response.ok) {
  throw new Error(`TCStock sync request failed: HTTP ${response.status}`);
} else {
  console.log("TCStock sync started; see output/runner.log for its result");
}

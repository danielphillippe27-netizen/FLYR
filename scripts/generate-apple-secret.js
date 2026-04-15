const fs = require("fs");
const apple = require("apple-signin-auth");

const CLIENT_ID = process.env.APPLE_CLIENT_ID;
const TEAM_ID = process.env.APPLE_TEAM_ID;
const KEY_ID = process.env.APPLE_KEY_ID;
const PRIVATE_KEY_PATH = process.env.APPLE_PRIVATE_KEY_PATH;
const EXP_SECONDS = Number(process.env.APPLE_EXP_SECONDS || 60 * 60 * 24 * 180);

if (!CLIENT_ID || !TEAM_ID || !KEY_ID || !PRIVATE_KEY_PATH) {
  console.error("Missing required env vars: APPLE_CLIENT_ID, APPLE_TEAM_ID, APPLE_KEY_ID, APPLE_PRIVATE_KEY_PATH");
  process.exit(1);
}

const PRIVATE_KEY = fs.readFileSync(PRIVATE_KEY_PATH, "utf8");

const token = apple.getClientSecret({
  clientID: CLIENT_ID,
  teamID: TEAM_ID,
  keyIdentifier: KEY_ID,
  privateKey: PRIVATE_KEY,
  expAfter: EXP_SECONDS
});

console.log("\n=== APPLE CLIENT SECRET (paste into Supabase → Auth → Apple) ===\n");
console.log(token);
console.log("\n=== END SECRET ===\n");

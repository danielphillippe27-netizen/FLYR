const fs = require("fs");
const apple = require("apple-signin-auth");

const CLIENT_ID   = "com.danielphillippe.flyr.supabase4"; // Service ID
const TEAM_ID     = "2AR5T8ZYAS";
const KEY_ID      = "3D5V346XX7";
const PRIVATE_KEY = fs.readFileSync("./AuthKey_3D5V346XX7.p8", "utf8");
const SIX_MONTHS  = 60 * 60 * 24 * 180;

const token = apple.getClientSecret({
  clientID: CLIENT_ID,
  teamID: TEAM_ID,
  keyIdentifier: KEY_ID,
  privateKey: PRIVATE_KEY,
  expAfter: SIX_MONTHS
});

console.log("\n=== APPLE CLIENT SECRET (paste into Supabase → Auth → Apple) ===\n");
console.log(token);
console.log("\n=== END SECRET ===\n");

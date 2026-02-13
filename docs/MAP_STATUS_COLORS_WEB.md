# Map status colors (align with iOS)

Use these colors on the **web** map so they match the iOS app.

| Status        | Hex       | Use |
|---------------|-----------|-----|
| **QR scanned**| `#8b5cf6` | Purple – address/building has at least one QR scan |
| **Conversations (hot)** | `#3b82f6` | Blue – talked, appointment, hot_lead |
| **Touched**   | `#22c55e` | Green – visited, delivered, no_answer, do_not_knock, future_seller |
| **Untouched** | `#ef4444` | Red – not visited |

**Priority (which color wins when multiple apply):** QR scanned > Conversations > Touched > Untouched.

**iOS:** Purple is used for QR codes (not yellow). Do not knock is green (same as touched).

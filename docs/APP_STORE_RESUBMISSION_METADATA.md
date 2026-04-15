# App Store resubmission — metadata and review notes

Use this when updating **App Store Connect** after the subscription compliance code changes.

## App description (Guideline 2.3.2)

Add a clear subscription disclosure near the top or end of the description, for example:

> **Subscriptions:** FLYR offers optional premium features through an auto-renewing subscription. Some features require an active subscription; others may be available without a subscription. Pricing and billing period are shown in the app before you subscribe.

Adjust the list of paid vs free features to match your product.

## Terms of Use / EULA (Guideline 3.1.2)

You are using **Apple’s Standard EULA**. Include this **functional link** in the App Description (and/or App Review Notes):

`https://www.apple.com/legal/internet-services/itunes/dev/stdeula/`

Example line:

> **Terms of Use (EULA):** https://www.apple.com/legal/internet-services/itunes/dev/stdeula/

If you instead use a **custom EULA**, upload it in App Store Connect (App Information → EULA) and link to that; the in-app paywall can still point at the same URL.

## Privacy Policy

Confirm the **Privacy Policy URL** field in App Store Connect matches a live page (e.g. `https://www.flyrpro.app/privacy`). The in-app paywall includes a **Privacy Policy** button.

## App Review Information

1. **Notes:** Summarize fixes: removed referral-based unlocks; subscription pricing shows billed amount as primary; EULA + Privacy in paywall; paywall dismisses after successful sandbox purchase; routing respects StoreKit entitlement.
2. **Attachment:** Screen recording showing:
   - Paywall with **annual price / year** prominent and monthly equivalent smaller
   - Tappable **Terms of Use (EULA)** (Apple standard URL) and **Privacy Policy**
   - Sandbox purchase completing and **leaving the paywall** / entering the main app
   - Optional: **Restore purchases** from the paywall

## Paid Apps Agreement

Ensure the Account Holder has accepted the **Paid Apps Agreement** in App Store Connect (Business).

## Backend note (optional)

iOS no longer sends `referral_code` in `POST /api/billing/apple/verify` or onboarding payloads. Ensure your API treats a missing `referral_code` as optional so verification still succeeds.

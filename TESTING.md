# Magic Link Authentication Testing Guide

## Overview
This guide covers testing Magic Link authentication with both Universal Links and custom URL schemes.

## Prerequisites
- Supabase dashboard configured with Magic Link enabled
- Redirect URLs allowlisted: `https://flyr.app/auth/callback` and `flyr://auth-callback`
- Associated Domains capability added to Xcode project (for Universal Links)

## Testing Methods

### 1. Simulator Testing (Custom URL Scheme)

The easiest way to test Magic Link authentication is using the iOS Simulator with custom URL schemes.

#### Steps:
1. Build and run the app in the iOS Simulator
2. Enter an email address and tap "Send Magic Link"
3. Check your email for the magic link
4. Copy the full URL from the email (it will look like: `https://flyrpro.app/auth/callback#access_token=...&refresh_token=...`)
5. Convert it to the custom scheme format: `flyr://auth-callback#access_token=...&refresh_token=...`
6. Run this command in Terminal:

```bash
xcrun simctl openurl booted "flyr://auth-callback#access_token=YOUR_ACCESS_TOKEN&refresh_token=YOUR_REFRESH_TOKEN"
```

Replace `YOUR_ACCESS_TOKEN` and `YOUR_REFRESH_TOKEN` with the actual values from the email.

#### Example:
```bash
xcrun simctl openurl booted "flyr://auth-callback#access_token=eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9...&refresh_token=eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9..."
```

### 2. Physical Device Testing (Universal Links)

For testing Universal Links on a physical device:

#### Steps:
1. Deploy the `apple-app-site-association` file to `https://flyr.app/.well-known/apple-app-site-association`
2. Install the app on your physical device
3. Send a magic link from the app
4. Open the email on the device and tap the magic link
5. The app should open directly (no Safari interstitial)

#### Troubleshooting Universal Links:
- **Opens in Safari instead of app**: Check that Associated Domains entitlement is present
- **"Open in App" banner appears**: The association is working but needs to be learned
- **No response**: Verify the `apple-app-site-association` file is correctly deployed

### 3. OTP Fallback Testing

Test the OTP fallback functionality:

1. Enter an email address
2. Tap "Send Code" in the OTP section
3. Check email for 6-digit code
4. Enter the code and tap "Verify"

## Troubleshooting

### Common Issues:

1. **"Invalid redirect URL" error**:
   - Ensure both `https://flyrpro.app/auth/callback` and `flyr://auth-callback` are in Supabase redirect URLs allowlist

2. **Magic link doesn't open app**:
   - Check that URL scheme is properly configured in Info.plist
   - Verify the custom URL format matches exactly

3. **Universal Links not working**:
   - Confirm `apple-app-site-association` file is deployed correctly
   - Check that Associated Domains capability is added to the project
   - Try reinstalling the app to refresh the association

4. **Session not persisting**:
   - Verify `loadSession()` is called on app launch
   - Check that session is properly stored in AuthManager

### Debug Commands:

```bash
# Test custom URL scheme
xcrun simctl openurl booted "flyr://auth-callback#test=123"

# Check if app responds to URL scheme
xcrun simctl openurl booted "flyr://test"
```

## Production Deployment

Before going live:

1. **Deploy apple-app-site-association**:
   - Upload `/Deploy/apple-app-site-association` to `https://flyrpro.app/.well-known/apple-app-site-association`
   - Ensure it's served as `application/json` with no redirects
   - Verify the file is accessible via HTTPS

2. **Update Supabase configuration**:
   - Set Site URL to `https://flyrpro.app`
   - Add both redirect URLs to allowlist
   - Enable Magic Link in Email provider settings

3. **Test on production domain**:
   - Use real domain URLs for testing
   - Verify Universal Links work on physical devices
   - Test both Magic Link and OTP flows

## Security Notes

- Magic links contain sensitive tokens - handle them securely
- OTP codes expire after 1 hour by default
- Rate limiting applies to both Magic Link and OTP requests
- Consider implementing additional security measures for production use

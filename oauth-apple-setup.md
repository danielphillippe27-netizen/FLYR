# Apple Sign-In OAuth Setup Guide

## Overview
This guide covers the complete setup for Apple Sign-In OAuth integration with Supabase for the FLYR app.

## Constants
- **SUPABASE_PROJECT_REF**: `kfnsnwqylsdsbgnwgxva`
- **SUPABASE_URL**: `https://kfnsnwqylsdsbgnwgxva.supabase.co`
- **OAUTH_CALLBACK**: `https://kfnsnwqylsdsbgnwgxva.supabase.co/auth/v1/callback`
- **APP_SCHEME**: `flyr://auth-callback`
- **APP_BUNDLE_ID**: `com.danielphillippe.FLYR`
- **APPLE_TEAM_ID**: `2AR5T8ZYAS`
- **APPLE_SERVICE_ID**: `com.danielphillippe.flyr.supabase4`
- **APPLE_KEY_ID**: `3D5V346XX7`

## Step 1: Generate Apple Client Secret

Run the following commands to generate the new Apple client secret:

```bash
npm install
npm run apple:secret
```

Copy the generated JWT token for use in Supabase configuration.

## Step 2: Configure Supabase Dashboard

### Supabase → Auth → Providers → Apple
- **Client IDs**: `com.danielphillippe.flyr.supabase4`
- **Secret Key (for OAuth)**: Paste the JWT token generated above
- **Callback URL**: `https://kfnsnwqylsdsbgnwgxva.supabase.co/auth/v1/callback`

### Supabase → Auth → URL Configuration
- **Redirect URLs (allow list)**: Add `flyr://auth-callback`

## Step 3: Configure Apple Developer Dashboard

### Apple Developer → Identifiers → Service IDs → com.danielphillippe.flyr.supabase4
- **Domains and Subdomains**: `https://kfnsnwqylsdsbgnwgxva.supabase.co`
- **Return URLs**: `https://kfnsnwqylsdsbgnwgxva.supabase.co/auth/v1/callback`

## Step 4: Verification Checklist

### ✅ All three places must match exactly:
1. **Service ID**: `com.danielphillippe.flyr.supabase4`
2. **Callback URL**: `https://kfnsnwqylsdsbgnwgxva.supabase.co/auth/v1/callback`
3. **Redirect URL**: `flyr://auth-callback`

### ✅ Test Plan:
1. **DNS Test**: Open `https://kfnsnwqylsdsbgnwgxva.supabase.co/auth/v1/callback` in browser
   - Expected: `{"error":"Missing code or provider"}` (not "server can't be found")
2. **App Test**: 
   - Run app → tap "Sign in with Apple" 
   - Flow: App → Apple → Supabase (HTTPS) → back to app via `flyr://auth-callback`
   - Verify: Session created successfully

## Important Notes

- **JWT Expiration**: The generated JWT expires in 6 months
- **Calendar Reminder**: Set a reminder to regenerate the secret before expiration
- **Exact Matching**: All Service IDs and URLs must match exactly across all three platforms
- **Key Security**: Keep the `.p8` key file secure and never commit to version control

## Troubleshooting

### Common Issues:
1. **"Invalid redirect URL"**: Check that all URLs match exactly
2. **"Server can't be found"**: Verify Supabase project is active
3. **App doesn't open after Apple auth**: Check URL scheme configuration
4. **Session not created**: Verify JWT token is valid and not expired

### Debug Commands:
```bash
# Test URL scheme
xcrun simctl openurl booted "flyr://auth-callback#test=123"

# Test Supabase callback
curl -I https://kfnsnwqylsdsbgnwgxva.supabase.co/auth/v1/callback
```

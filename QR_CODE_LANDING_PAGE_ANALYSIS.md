# QR Code → Landing Page Link Analysis

## Executive Summary

**The system expects:** `QR Code (slug) → landing_page_id → campaign_landing_pages (slug) → Redirect`

**Currently missing:**
1. ❌ `slug` column in `qr_codes` table
2. ❌ `increment_landing_page_views` RPC function

**What you must create:**
1. Migration to add `slug` column to `qr_codes` table
2. RPC function `increment_landing_page_views`
3. Landing page records in `campaign_landing_pages` table
4. QR code records with `slug` and `landing_page_id` populated

---

## 1. Expected Database Schema

### Table: `qr_codes`
**Current columns:**
- `id` (UUID, PRIMARY KEY)
- `campaign_id` (UUID, nullable)
- `farm_id` (UUID, nullable)
- `address_id` (UUID, nullable)
- `batch_id` (UUID, nullable)
- `landing_page_id` (UUID, nullable) ✅ **EXISTS** - References `campaign_landing_pages.id`
- `qr_variant` (TEXT, nullable) - 'A' or 'B' for A/B testing
- `qr_url` (TEXT, NOT NULL)
- `qr_image` (TEXT, nullable)
- `created_at` (TIMESTAMPTZ)
- `updated_at` (TIMESTAMPTZ)
- `metadata` (JSONB)

**Missing column:**
- ❌ `slug` (TEXT, nullable, UNIQUE) - **REQUIRED BY qr_redirect FUNCTION**

### Table: `campaign_landing_pages`
**Columns (all exist):**
- `id` (UUID, PRIMARY KEY) ✅
- `campaign_id` (UUID, NOT NULL) ✅ - References `campaigns.id`
- `slug` (TEXT, NOT NULL, UNIQUE) ✅ - **This is the landing page slug**
- `headline` (TEXT, nullable)
- `subheadline` (TEXT, nullable)
- `hero_url` (TEXT, nullable)
- `cta_type` (TEXT, nullable)
- `cta_url` (TEXT, nullable)
- `created_at` (TIMESTAMPTZ)
- `updated_at` (TIMESTAMPTZ)

**Constraint:** One landing page per campaign (`UNIQUE (campaign_id)`)

---

## 2. Expected Flow (from qr_redirect Edge Function)

### URL Pattern
```
https://flyrpro.app/q/<qr_code_slug>
```

### Redirect Flow
1. **Extract slug** from URL path `/q/<slug>`
2. **Lookup QR code** by `slug` in `qr_codes` table
   ```sql
   SELECT id, landing_page_id, campaign_id 
   FROM qr_codes 
   WHERE slug = '<slug>'
   ```
3. **Validate** `landing_page_id` exists (return 404 if null)
4. **Get landing page slug** from `campaign_landing_pages`
   ```sql
   SELECT slug 
   FROM campaign_landing_pages 
   WHERE id = '<landing_page_id>'
   ```
5. **Increment analytics** via RPC: `increment_landing_page_views(landing_page_id)`
6. **Redirect** to: `https://flyrpro.app/l/<landing_page_slug>`

### Code Reference
**File:** `supabase/functions/qr_redirect/index.ts`
- Line 27: `.eq("slug", slug)` - **Expects `slug` column in `qr_codes`**
- Line 34-36: Validates `landing_page_id` exists
- Line 40-43: Queries `campaign_landing_pages` by `id` to get `slug`
- Line 50-52: Calls `increment_landing_page_views` RPC (MISSING)
- Line 55: Redirects to `https://flyrpro.app/l/${landingPage.slug}`

---

## 3. Relationship Diagram

```
┌─────────────┐
│  qr_codes   │
├─────────────┤
│ id          │
│ slug        │ ❌ MISSING - Required for URL lookup
│ landing_    │ ✅ EXISTS - Foreign key
│   page_id   │
│ campaign_id │
│ ...         │
└──────┬──────┘
       │
       │ landing_page_id (FK)
       │
       ▼
┌──────────────────────┐
│ campaign_landing_    │
│   pages              │
├──────────────────────┤
│ id                   │ ✅ EXISTS
│ campaign_id          │ ✅ EXISTS
│ slug                 │ ✅ EXISTS - Used for redirect
│ headline             │ ✅ EXISTS
│ ...                  │
└──────────────────────┘
```

**Relationship:** `qr_codes.landing_page_id` → `campaign_landing_pages.id` (ON DELETE SET NULL)

---

## 4. Missing Components

### A. Missing Column: `qr_codes.slug`

**Why it's needed:**
- The `qr_redirect` function looks up QR codes by `slug` from the URL
- URL format: `https://flyrpro.app/q/<slug>`
- Without this column, the lookup will fail

**Migration needed:**
```sql
ALTER TABLE public.qr_codes 
ADD COLUMN IF NOT EXISTS slug TEXT UNIQUE;

CREATE INDEX IF NOT EXISTS idx_qr_codes_slug 
ON public.qr_codes(slug) 
WHERE slug IS NOT NULL;
```

**How slugs should be generated:**
- Short, URL-safe identifiers
- Unique per QR code
- Can be UUID-based or custom (e.g., `abc123`, `xyz789`)
- Stored when QR code is created or linked to a landing page

### B. Missing RPC Function: `increment_landing_page_views`

**Why it's needed:**
- Called in `qr_redirect/index.ts` line 50-52
- Should increment view count in `campaign_landing_page_analytics` table

**Function needed:**
```sql
CREATE OR REPLACE FUNCTION increment_landing_page_views(
    landing_page_id UUID
)
RETURNS void
LANGUAGE plpgsql
SECURITY DEFINER
AS $$
BEGIN
    INSERT INTO public.campaign_landing_page_analytics (
        landing_page_id,
        views,
        timestamp_bucket
    )
    VALUES (
        landing_page_id,
        1,
        CURRENT_DATE
    )
    ON CONFLICT (landing_page_id, timestamp_bucket)
    DO UPDATE SET
        views = campaign_landing_page_analytics.views + 1;
END;
$$;
```

---

## 5. What You Must Create

### Step 1: Create Landing Page Record

**Table:** `campaign_landing_pages`

**Example row:**
```sql
INSERT INTO public.campaign_landing_pages (
    id,
    campaign_id,
    slug,
    headline,
    subheadline,
    hero_url,
    cta_type,
    cta_url
) VALUES (
    gen_random_uuid(),
    '<your_campaign_id>',
    'my-campaign-abc123',  -- Must be unique, URL-safe
    'Welcome to Our Campaign',
    'Discover amazing properties',
    'https://storage.supabase.co/.../hero.jpg',
    'book',
    'https://calendly.com/...'
);
```

**Notes:**
- `slug` must be unique across all landing pages
- `campaign_id` must reference an existing campaign
- One landing page per campaign (enforced by UNIQUE constraint)

### Step 2: Create/Update QR Code with Slug and Landing Page Link

**Table:** `qr_codes`

**Option A: Create new QR code with landing page**
```sql
INSERT INTO public.qr_codes (
    id,
    campaign_id,
    slug,                    -- NEW: QR code slug for URL
    landing_page_id,         -- Link to landing page
    qr_url,
    qr_image,
    qr_variant               -- Optional: 'A' or 'B'
) VALUES (
    gen_random_uuid(),
    '<campaign_id>',
    'qr-abc123',             -- Unique slug for /q/qr-abc123
    '<landing_page_id>',     -- From Step 1
    'https://flyrpro.app/q/qr-abc123',
    '<base64_image>',
    'A'                      -- Optional variant
);
```

**Option B: Update existing QR code**
```sql
UPDATE public.qr_codes
SET 
    slug = 'qr-abc123',              -- Add slug
    landing_page_id = '<landing_page_id>'  -- Link to landing page
WHERE id = '<existing_qr_code_id>';
```

**Notes:**
- `slug` must be unique across all QR codes
- `landing_page_id` must reference an existing `campaign_landing_pages.id`
- QR code URL should be: `https://flyrpro.app/q/<slug>`

---

## 6. Complete Example: End-to-End Setup

### Scenario: Campaign "Summer 2025" with QR Code

**1. Create Landing Page:**
```sql
INSERT INTO public.campaign_landing_pages (
    campaign_id,
    slug,
    headline,
    subheadline,
    cta_type,
    cta_url
) VALUES (
    '123e4567-e89b-12d3-a456-426614174000',  -- campaign_id
    'summer-2025-xyz789',                     -- unique slug
    'Summer 2025 Campaign',
    'Find your dream home',
    'book',
    'https://calendly.com/summer2025'
) RETURNING id, slug;
-- Returns: landing_page_id = 'abc-123-def-456'
```

**2. Create QR Code:**
```sql
INSERT INTO public.qr_codes (
    campaign_id,
    slug,                                    -- QR code slug
    landing_page_id,                         -- Link to landing page
    qr_url,
    qr_variant
) VALUES (
    '123e4567-e89b-12d3-a456-426614174000',  -- campaign_id
    'summer-qr-abc123',                      -- QR slug (unique)
    'abc-123-def-456',                       -- landing_page_id from Step 1
    'https://flyrpro.app/q/summer-qr-abc123',
    'A'
) RETURNING id, slug, landing_page_id;
```

**3. Test Flow:**
- User scans QR code → URL: `https://flyrpro.app/q/summer-qr-abc123`
- `qr_redirect` function:
  - Looks up `qr_codes` by `slug = 'summer-qr-abc123'`
  - Gets `landing_page_id = 'abc-123-def-456'`
  - Queries `campaign_landing_pages` by `id = 'abc-123-def-456'`
  - Gets `slug = 'summer-2025-xyz789'`
  - Redirects to: `https://flyrpro.app/l/summer-2025-xyz789`

---

## 7. iOS App Integration

### Linking QR Code to Landing Page

**File:** `FLYR/Features/LandingPages/Services/SupabaseQRService.swift`

**Method:** `linkQRCode(qrId:landingPageId:variant:)`
- Updates `qr_codes.landing_page_id` ✅
- Updates `qr_codes.qr_variant` (optional) ✅
- **Does NOT set `qr_codes.slug`** ❌ - This needs to be added

**Current behavior:**
- App can link QR codes to landing pages via `landing_page_id`
- App does NOT set or generate `slug` for QR codes

**What needs to change:**
- When linking a QR code, also generate and set a `slug`
- Or generate `slug` when QR code is created
- Ensure `qr_url` matches: `https://flyrpro.app/q/<slug>`

---

## 8. Summary Checklist

### Database Schema
- [x] `campaign_landing_pages` table exists
- [x] `campaign_landing_pages.slug` column exists
- [x] `qr_codes.landing_page_id` column exists
- [x] Foreign key relationship exists
- [ ] ❌ `qr_codes.slug` column **MISSING**
- [ ] ❌ `increment_landing_page_views` RPC function **MISSING**

### Data Requirements
- [ ] Landing page records in `campaign_landing_pages`
- [ ] QR code records with `slug` populated
- [ ] QR code records with `landing_page_id` populated

### Code Requirements
- [ ] iOS app generates `slug` when creating/linking QR codes
- [ ] iOS app sets `qr_url` to `https://flyrpro.app/q/<slug>`

---

## 9. Next Steps

### Immediate Actions Required:

1. **Create migration to add `slug` column to `qr_codes`:**
   ```sql
   -- Migration: Add slug column to qr_codes
   ALTER TABLE public.qr_codes 
   ADD COLUMN IF NOT EXISTS slug TEXT UNIQUE;
   
   CREATE INDEX IF NOT EXISTS idx_qr_codes_slug 
   ON public.qr_codes(slug) 
   WHERE slug IS NOT NULL;
   ```

2. **Create `increment_landing_page_views` RPC function:**
   ```sql
   CREATE OR REPLACE FUNCTION increment_landing_page_views(
       landing_page_id UUID
   )
   RETURNS void
   LANGUAGE plpgsql
   SECURITY DEFINER
   AS $$
   BEGIN
       INSERT INTO public.campaign_landing_page_analytics (
           landing_page_id,
           views,
           timestamp_bucket
       )
       VALUES (
           increment_landing_page_views.landing_page_id,
           1,
           CURRENT_DATE
       )
       ON CONFLICT (landing_page_id, timestamp_bucket)
       DO UPDATE SET
           views = campaign_landing_page_analytics.views + 1;
   END;
   $$;
   ```

3. **Update iOS app to generate and set `slug` when creating/linking QR codes**

4. **Create landing page records** for existing campaigns

5. **Update existing QR codes** with `slug` values and `landing_page_id` links

---

## 10. Files Referenced

### Database Migrations
- `supabase/migrations/20250127000001_create_campaign_landing_pages.sql` - Creates landing pages table
- `supabase/migrations/20250127000002_add_landing_page_to_qr_codes.sql` - Adds `landing_page_id` to qr_codes
- `supabase/migrations/20250127000003_create_campaign_landing_page_analytics.sql` - Creates analytics table

### Code Files
- `supabase/functions/qr_redirect/index.ts` - Edge function that handles redirects
- `FLYR/Features/LandingPages/Services/SupabaseQRService.swift` - iOS service for linking QR codes
- `FLYR/Features/LandingPages/Models/CampaignLandingPage.swift` - Landing page model
- `FLYR/Features/QRCodes/Models/QRCode.swift` - QR code model

---

**Analysis Date:** 2025-01-27  
**Status:** ❌ System incomplete - Missing `slug` column and RPC function



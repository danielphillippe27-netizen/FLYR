# AI Context Documentation - Quick Start

This folder contains master documentation files optimized for pasting into AI chats (Claude, ChatGPT, etc.) before asking questions about FLYR's tech stack and architecture.

## 📁 Files Overview

### Core Master File
- **[AI_CONTEXT_MASTER.md](AI_CONTEXT_MASTER.md)** - Always include this first
  - Product overview, tech stack, core objects
  - Data flow, naming conventions, environments
  - Known gotchas and AI prompt best practices

### Specialized Modules (Pick one based on your question)
- **[AI_CONTEXT_DB_SCHEMA.md](AI_CONTEXT_DB_SCHEMA.md)** - Database schema
  - Tables, columns, foreign keys, geometry types
  - Use for: Database questions, schema questions, SQL queries

- **[AI_CONTEXT_RPC_CATALOG.md](AI_CONTEXT_RPC_CATALOG.md)** - RPC functions
  - All RPC functions with inputs/outputs, example JSON
  - Use for: RPC questions, query optimization, GeoJSON questions

- **[AI_CONTEXT_IOS_ARCH.md](AI_CONTEXT_IOS_ARCH.md)** - iOS architecture
  - Hooks/Stores/Views pattern, features, services
  - Use for: iOS code questions, architecture questions, Swift/SwiftUI

- **[AI_CONTEXT_MAPBOX.md](AI_CONTEXT_MAPBOX.md)** - Mapbox integration
  - Sources, layers, filters, colors, 3D rendering
  - Use for: Map rendering questions, Mapbox issues, 3D buildings

- **[AI_CONTEXT_API_ROUTES.md](AI_CONTEXT_API_ROUTES.md)** - API endpoints
  - Backend API routes, Supabase Edge Functions
  - Use for: API questions, backend integration, authentication

- **[AI_CONTEXT_FLOWS.md](AI_CONTEXT_FLOWS.md)** - Common flows
  - End-to-end flows (campaign creation, QR scans, etc.)
  - Use for: Flow questions, integration questions, debugging

## 🚀 How to Use

### Step 1: Copy Master Doc
Always start by copying `AI_CONTEXT_MASTER.md` to your AI chat.

### Step 2: Add Relevant Module
Pick ONE module that matches your question type:

**Examples:**
- "Why is my RPC returning empty?" → Add `AI_CONTEXT_RPC_CATALOG.md`
- "How do I add a new feature in iOS?" → Add `AI_CONTEXT_IOS_ARCH.md`
- "Buildings not rendering in 3D" → Add `AI_CONTEXT_MAPBOX.md`
- "How does campaign creation work?" → Add `AI_CONTEXT_FLOWS.md`

### Step 3: Include Your Code/Error
Paste your specific code snippet, error message, or log output.

### Step 4: Ask Your Question
Be specific about what you want to know or what problem you're solving.

## 📝 Example AI Prompt

```
You are my senior iOS + Supabase engineer for FLYR.
If you're unsure, ask for the missing file/function name.
Prefer minimal diff fixes.

[Paste AI_CONTEXT_MASTER.md here]

[Paste AI_CONTEXT_MAPBOX.md here]

I'm getting this error when rendering buildings:
"Expected Polygon/MultiPolygon but got LineString"

The error occurs in MapLayerManager.swift when I call:
```swift
mapView.mapboxMap.updateGeoJSONSource(
  withId: "buildingsSource",
  geoJSON: featureCollection
)
```

Question: Why is my buildings layer receiving LineString geometries, and how do I fix this?
```

## 🎯 Quick Decision Tree

**Question is about...**

- **Database tables/schema/relationships** → Use `AI_CONTEXT_DB_SCHEMA.md`
- **Supabase RPC functions** → Use `AI_CONTEXT_RPC_CATALOG.md`
- **iOS app structure/hooks/stores** → Use `AI_CONTEXT_IOS_ARCH.md`
- **Mapbox rendering/3D/colors** → Use `AI_CONTEXT_MAPBOX.md`
- **Backend API/Edge Functions** → Use `AI_CONTEXT_API_ROUTES.md`
- **End-to-end flows/integrations** → Use `AI_CONTEXT_FLOWS.md`

## 🔄 Maintenance

Keep these docs updated when:

| Change Type | Update File |
|------------|-------------|
| New table or column | `AI_CONTEXT_DB_SCHEMA.md` |
| New RPC function | `AI_CONTEXT_RPC_CATALOG.md` |
| New feature or service | `AI_CONTEXT_IOS_ARCH.md` |
| Mapbox source/layer changes | `AI_CONTEXT_MAPBOX.md` |
| New API endpoint | `AI_CONTEXT_API_ROUTES.md` |
| New major flow | `AI_CONTEXT_FLOWS.md` |
| Core architecture changes | `AI_CONTEXT_MASTER.md` |

## 💡 Pro Tips

1. **Keep it focused** - Only paste 1 master + 1 module per question
2. **Be specific** - Include file paths, function names, exact error messages
3. **Use the right module** - Wrong context = less helpful answers
4. **Update regularly** - Keep docs in sync with codebase changes
5. **Share with team** - Anyone on the team can use these docs

## 📊 File Sizes

All files are designed to be ≤150 lines for optimal AI context window usage:

- `AI_CONTEXT_MASTER.md` - ~200 lines (core doc, slightly longer)
- `AI_CONTEXT_DB_SCHEMA.md` - ~150 lines
- `AI_CONTEXT_RPC_CATALOG.md` - ~120 lines
- `AI_CONTEXT_IOS_ARCH.md` - ~150 lines
- `AI_CONTEXT_MAPBOX.md` - ~140 lines
- `AI_CONTEXT_API_ROUTES.md` - ~130 lines
- `AI_CONTEXT_FLOWS.md` - ~150 lines

**Total:** ~1040 lines (you'll paste 2-3 files at most = ~350 lines of context)

## 🔍 Finding Files Quickly

### Command Line
```bash
# List all AI context docs
ls docs/AI_CONTEXT_*.md

# Search within docs
grep -r "rpc_get_campaign" docs/AI_CONTEXT_*.md

# Open specific doc
open docs/AI_CONTEXT_MASTER.md
```

### VS Code / Cursor
- Use `Cmd+P` and type `AI_CONTEXT` to see all docs
- Use `Cmd+Shift+F` to search within all docs

## ✅ Checklist for AI Questions

Before asking your AI question:

- [ ] Copied `AI_CONTEXT_MASTER.md`
- [ ] Copied ONE relevant module
- [ ] Included specific code snippet or error message
- [ ] Included relevant file path
- [ ] Asked specific, focused question
- [ ] Specified desired outcome (fix, explanation, best practice, etc.)

## 🎓 Example Use Cases

### Use Case 1: Debugging Map Issue
**Files needed:**
- `AI_CONTEXT_MASTER.md`
- `AI_CONTEXT_MAPBOX.md`

**Question type:** "Why aren't my buildings rendering?"

---

### Use Case 2: Adding New RPC
**Files needed:**
- `AI_CONTEXT_MASTER.md`
- `AI_CONTEXT_RPC_CATALOG.md`
- `AI_CONTEXT_DB_SCHEMA.md` (if touching tables)

**Question type:** "How do I create a new RPC for X?"

---

### Use Case 3: Building New Feature
**Files needed:**
- `AI_CONTEXT_MASTER.md`
- `AI_CONTEXT_IOS_ARCH.md`
- `AI_CONTEXT_FLOWS.md` (for understanding existing flows)

**Question type:** "How do I add a new feature following FLYR's architecture?"

---

### Use Case 4: Understanding Data Flow
**Files needed:**
- `AI_CONTEXT_MASTER.md`
- `AI_CONTEXT_FLOWS.md`

**Question type:** "How does data flow from campaign creation to map rendering?"

---

## 📞 Questions About These Docs?

If you need to update or improve these docs:
1. Edit the specific `AI_CONTEXT_*.md` file
2. Keep it concise (≤150 lines per module)
3. Update this README if you add new files
4. Test with an AI chat to ensure it provides good answers

---

**Created:** February 2026  
**Purpose:** Eliminate AI back-and-forth by providing consistent, accurate context upfront  
**Maintenance:** Update as codebase evolves

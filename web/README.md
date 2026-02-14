# FLYR Leaderboard (Web)

React + Vite app that shows the global leaderboard using the same Supabase RPC as the iOS app.

## Setup

1. Copy `.env.example` to `.env` and set:
   - `VITE_SUPABASE_URL` – your Supabase project URL
   - `VITE_SUPABASE_ANON_KEY` – your Supabase anon (public) key

2. Install and run:

   ```bash
   cd web
   npm install
   npm run dev
   ```

3. Open http://localhost:5173 (or the port Vite prints). Routes:
   - `/` – Leaderboard
   - `/leaderboard` – Leaderboard

## Backend

Uses Supabase RPC `get_leaderboard(p_metric, p_timeframe)` only. No extra Node API. Ensure the migration that defines this function is applied to your Supabase project.

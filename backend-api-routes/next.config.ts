import type { NextConfig } from "next";

const config: NextConfig = {
  output: "standalone",
  env: {
    NEXT_PUBLIC_SUPABASE_URL:
      process.env.NEXT_PUBLIC_SUPABASE_URL || process.env.SUPABASE_URL || "https://placeholder.supabase.co",
    NEXT_PUBLIC_SUPABASE_ANON_KEY:
      process.env.NEXT_PUBLIC_SUPABASE_ANON_KEY || process.env.SUPABASE_ANON_KEY || "placeholder-anon-key",
  },
  serverExternalPackages: ["duckdb"],
  turbopack: {
    // Project root so Next finds node_modules when running from backend-api-routes
    root: process.cwd(),
  },
};

export default config;

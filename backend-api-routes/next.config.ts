import type { NextConfig } from "next";

const config: NextConfig = {
  output: "standalone",
  serverExternalPackages: ["duckdb"],
  turbopack: {
    // Project root so Next finds node_modules when running from backend-api-routes
    root: process.cwd(),
  },
};

export default config;

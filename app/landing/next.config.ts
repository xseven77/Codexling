import type { NextConfig } from "next";

const nextConfig: NextConfig = {
  output: "standalone",
  // Codex's in-app browser reaches the local preview through 127.0.0.1.
  // Next.js otherwise blocks its dev-only HMR WebSocket as cross-origin.
  allowedDevOrigins: ["127.0.0.1"],
};

export default nextConfig;

import type { NextConfig } from "next";

// Serve this Next app under /app on app.splui.com
// and proxy API/static asset requests back to the existing uploader server (localhost:3001).
const nextConfig: NextConfig = {
  basePath: "/app",
  async rewrites() {
    return [
      // Proxy existing Express APIs (must work on the same host, outside basePath)
      { source: "/api/:path*", destination: "http://127.0.0.1:3001/api/:path*", basePath: false },
      // Proxy existing console UI (legacy) so we can embed it
      { source: "/console/:path*", destination: "http://127.0.0.1:3001/console/:path*", basePath: false },
      // Proxy hosted images
      { source: "/couplus-out/:path*", destination: "http://127.0.0.1:3001/couplus-out/:path*", basePath: false },
      { source: "/tmp/:path*", destination: "http://127.0.0.1:3001/tmp/:path*", basePath: false },
    ];
  },
};

export default nextConfig;

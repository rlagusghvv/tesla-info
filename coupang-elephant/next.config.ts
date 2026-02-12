import type { NextConfig } from "next";

// Serve this Next app under /app on app.splui.com
// and proxy API/static asset requests back to the existing uploader server (localhost:3000).
const nextConfig: NextConfig = {
  basePath: "/app",
  async rewrites() {
    return [
      // Proxy existing Express APIs
      { source: "/api/:path*", destination: "http://127.0.0.1:3000/api/:path*" },
      // Proxy existing console UI (legacy) so we can embed it
      { source: "/console/:path*", destination: "http://127.0.0.1:3000/console/:path*" },
      // Proxy hosted images
      { source: "/couplus-out/:path*", destination: "http://127.0.0.1:3000/couplus-out/:path*" },
      { source: "/tmp/:path*", destination: "http://127.0.0.1:3000/tmp/:path*" },
    ];
  },
};

export default nextConfig;

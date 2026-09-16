import type { NextConfig } from "next";

const nextConfig: NextConfig = {
  output: "export",
  trailingSlash: true,
  basePath: process.env.GITHUB_ACTIONS ? "/trivia" : "",
  assetPrefix: process.env.GITHUB_ACTIONS ? "/trivia/" : "",
  images: { unoptimized: true },
};

export default nextConfig;

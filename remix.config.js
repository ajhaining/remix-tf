/** @type {import('@remix-run/dev').AppConfig} */

const baseConfig = {
  assetsBuildDirectory: "build/assets/_static",
  future: {
    unstable_tailwind: true
  },
  ignoredRouteFiles: ["**/.*"],
  publicPath: "/_static/",
  serverBuildPath: "build/server/index.js"
}

if (process.env.NODE_ENV === "production") {
  module.exports = {
    ...baseConfig,
    server: "server.ts",
    serverDependenciesToBundle: "all",
  };
} else {
  module.exports = baseConfig;
}

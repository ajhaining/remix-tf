/** @type {import('@remix-run/dev').AppConfig} */

const baseConfig = {
  ignoredRouteFiles: ["**/.*"],
  future: {
    unstable_tailwind: true,
  },
}

if (process.env.NODE_ENV === 'production') {
  module.exports = {
    ...baseConfig,
    publicPath: "/_static/",
    assetsBuildDirectory: "build/assets/_static",
    server: "server.ts",
    serverBuildPath: "build/server/index.js",
    serverDependenciesToBundle: "all",
  };
} else {
  module.exports = baseConfig;
}

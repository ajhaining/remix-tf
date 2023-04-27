/** @type {import('@remix-run/dev').AppConfig} */

const baseConfig = {
  assetsBuildDirectory: "build/assets/_static",
  serverBuildPath: "build/server/index.js",
  publicPath: "/_static/",
  future: {
    unstable_tailwind: true,
    v2_errorBoundary: true,
    v2_meta: true,
    v2_normalizeFormMethod: true,
    v2_routeConvention: true,
  },
  ignoredRouteFiles: ["**/.*"],
};

if (process.env.NODE_ENV === "production") {
  module.exports = {
    ...baseConfig,
    server: "server.ts",
    serverDependenciesToBundle: "all",
  };
} else {
  module.exports = {
    ...baseConfig,
  };
}

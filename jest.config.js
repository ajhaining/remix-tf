/** @type {import('ts-jest').JestConfigWithTsJest} */

const { compilerOptions } = require("./tsconfig.json");
const { pathsToModuleNameMapper } = require("ts-jest");

module.exports = {
  preset: "ts-jest",
  clearMocks: true,
  resetMocks: true,
  injectGlobals: true,
  moduleNameMapper: {
    ...pathsToModuleNameMapper(compilerOptions.paths, {
      prefix: "<rootDir>",
    }),
  },
  setupFilesAfterEnv: ["@testing-library/jest-dom/extend-expect"],
  testEnvironment: "jsdom",
  // Overrides jest-environment-jsdom's default value of 'browser'. Without
  // this, we get the browser builds of the @remix-run/web-* packages, which
  // don't work because our tests run in Node.
  testEnvironmentOptions: {
    customExportConditions: ["require"],
  },
};

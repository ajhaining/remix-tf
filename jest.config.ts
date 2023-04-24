import type { Config } from "jest";
import { pathsToModuleNameMapper } from "ts-jest";

import { compilerOptions } from "./tsconfig.json";

const config: Config = {
  clearMocks: true,
  resetMocks: true,
  coveragePathIgnorePatterns: [],
  injectGlobals: true,
  moduleFileExtensions: ["js", "ts", "tsx"],
  moduleNameMapper: {
    ...pathsToModuleNameMapper(compilerOptions.paths, {
      prefix: "<rootDir>",
    }),
  },
  setupFilesAfterEnv: [
    "@testing-library/jest-dom/extend-expect"
  ],
  transform: {
    "^.+\\.(ts|tsx)$": [
      "ts-jest",
      {
        isolatedModules: true,
      },
    ],
  },
  testEnvironment: 'jsdom',
};

export default config;

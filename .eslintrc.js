/** @type {import('eslint').ESLint.ConfigData} */

module.exports = {
  root: true,
  extends: [
    "@remix-run/eslint-config",
    "@remix-run/eslint-config/jest-testing-library",
    "prettier",
  ],
};

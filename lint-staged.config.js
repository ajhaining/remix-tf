/** @type {import('lint-staged').Config} */

module.exports = {
  "*.{js,ts,tsx}": [
    "eslint --ignore-path .gitignore --fix",
    "prettier --ignore-path .gitignore --write",
  ],
};

import { defineConfig } from "vitest/config";

export default defineConfig({
  test: {
    globals: true,
    environment: "node",
    // src/auth.ts gates its test token verifier behind these two. Unset, every
    // authenticated route falls through to AuthError("TOKEN_INVALID") and the
    // whole suite fails on 401s that have nothing to do with the code under test.
    env: {
      COGNITO_USER_POOL_ID: "test-pool",
      COGNITO_CLIENT_ID: "test-client",
    },
    include: ["tests/**/*.test.ts"],
    isolate: true,
    pool: "forks",
    poolOptions: {
      forks: { singleFork: true },
    },
  },
});
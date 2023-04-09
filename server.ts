import { createRequestHandler, type RequestHandler } from "./lib/createRequestHandler";
import * as build from "@remix-run/dev/server-build";

export const handler: RequestHandler = createRequestHandler({
  build,
  mode: process.env.NODE_ENV,
});

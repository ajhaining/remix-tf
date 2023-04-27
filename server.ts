import * as build from "@remix-run/dev/server-build";

import {
  createRequestHandler,
  type RequestHandler,
} from "~/lib/createRequestHandler";

export const handler: RequestHandler = createRequestHandler({
  build,
  mode: process.env.NODE_ENV,
});

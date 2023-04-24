import {
  AbortController as NodeAbortController,
  Headers as NodeHeaders,
  Request as NodeRequest,
  createRequestHandler as createRemixRequestHandler,
  readableStreamToString,
  type AppLoadContext,
  type RequestInit as NodeRequestInit,
  type Response as NodeResponse,
  type ServerBuild,
} from "@remix-run/node";

import type {
  APIGatewayProxyEvent,
  APIGatewayProxyEventMultiValueHeaders,
  APIGatewayProxyEventMultiValueQueryStringParameters,
  APIGatewayProxyHandler,
  APIGatewayProxyResult,
} from "aws-lambda";

export type GetLoadContextFunction = (event: APIGatewayProxyEvent) => AppLoadContext;

export type RequestHandler = APIGatewayProxyHandler;

export function createRequestHandler({
  build,
  getLoadContext,
  mode = process.env.NODE_ENV,
}: {
  build: ServerBuild;
  getLoadContext?: GetLoadContextFunction;
  mode?: string;
}): RequestHandler {
  const handleRequest = createRemixRequestHandler(build, mode);

  return async (event) => {
    console.log("event", event);

    const request = createRemixRequest(event);

    console.log("request", request);

    const loadContext = typeof getLoadContext === "function" ? getLoadContext(event) : undefined;

    const response = (await handleRequest(request, loadContext)) as NodeResponse;

    console.log("response", response);

    return createApiGatewayResponse(response);
  };
}

export function createRemixRequest(event: APIGatewayProxyEvent): NodeRequest {
  const host = event.requestContext.domainName || event.headers["X-Forwarded-Host"] || event.headers.Host;
  const scheme = event.headers["X-Forwarded-Proto"] || "https";
  const search = createRemixQueryString(event.multiValueQueryStringParameters);
  const url = new URL(`${scheme}://${host}${event.path}${search}`);
  const controller = new NodeAbortController();
  const isFormData = event.headers["Content-Type"]?.includes("multipart/form-data");

  return new NodeRequest(url.href, {
    method: event.httpMethod,
    headers: createRemixHeaders(event.multiValueHeaders),
    signal: controller.signal as NodeRequestInit["signal"],
    body:
      event.body && event.isBase64Encoded
        ? isFormData
          ? Buffer.from(event.body, "base64")
          : Buffer.from(event.body, "base64").toString()
        : event.body,
  });
}

export function createRemixQueryString(
  multiValueQueryStringParameters: APIGatewayProxyEventMultiValueQueryStringParameters | null
): string {
  const remixQueryString = new URLSearchParams();

  if (multiValueQueryStringParameters) {
    for (const [param, values] of Object.entries(multiValueQueryStringParameters)) {
      if (values && values.length > 0) {
        for (const value of values) {
          remixQueryString.append(param, value);
        }
      }
    }
    return `?${remixQueryString.toString()}`;
  }

  return "";
}

export function createRemixHeaders(multiValueHeaders: APIGatewayProxyEventMultiValueHeaders): NodeHeaders {
  const remixHeaders = new NodeHeaders();

  if (multiValueHeaders) {
    for (const [param, values] of Object.entries(multiValueHeaders)) {
      if (values && values.length > 0) {
        for (const value of values) {
          remixHeaders.append(param, value);
        }
      }
    }
  }

  return remixHeaders;
}

export async function createApiGatewayResponse(nodeResponse: NodeResponse): Promise<APIGatewayProxyResult> {
  const contentType = nodeResponse.headers.get("Content-Type");

  console.log("contentType", contentType);

  const isBase64Encoded =
    !contentType ||
    !(
      contentType.startsWith("text/") ||
      contentType.includes("application/json") ||
      contentType.includes("application/xml")
    );

  const headers: APIGatewayProxyResult["headers"] = {};
  const multiValueHeaders: APIGatewayProxyResult["multiValueHeaders"] = {};

  for (const [param, value] of nodeResponse.headers.entries()) {
    if (Array.isArray(value)) {
      multiValueHeaders[param] = value;
    } else {
      headers[param] = value;
    }
  }

  let body: string | undefined;

  if (nodeResponse.body) {
    if (isBase64Encoded) {
      body = await readableStreamToString(nodeResponse.body, "base64");
    } else {
      body = await nodeResponse.text();
    }
  }

  return {
    statusCode: nodeResponse.status,
    headers,
    multiValueHeaders,
    body: body || "",
    isBase64Encoded,
  };
}

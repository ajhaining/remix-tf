import type {
  AppLoadContext,
  ServerBuild,
  RequestInit as NodeRequestInit,
  Response as NodeResponse,
} from "@remix-run/node";

import {
  AbortController as NodeAbortController,
  Headers as NodeHeaders,
  Request as NodeRequest,
  createRequestHandler as createRemixRequestHandler,
  readableStreamToString,
} from "@remix-run/node";

import type {
  APIGatewayProxyEvent,
  APIGatewayProxyHandler,
  APIGatewayProxyResult,
  APIGatewayProxyEventMultiValueHeaders,
  APIGatewayProxyEventMultiValueQueryStringParameters,
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
  let handleRequest = createRemixRequestHandler(build, mode);

  return async (event) => {
    console.log("event", event);

    let request = createRemixRequest(event);

    console.log("request", request);

    let loadContext = typeof getLoadContext === "function" ? getLoadContext(event) : undefined;

    let response = (await handleRequest(request, loadContext)) as NodeResponse;

    console.log("response", response);

    return createApiGatewayResponse(response);
  };
}

export function createRemixRequest(event: APIGatewayProxyEvent): NodeRequest {
  let host = event.requestContext.domainName || event.headers["X-Forwarded-Host"] || event.headers["Host"];
  let scheme = event.headers["X-Forwarded-Proto"] || "https";
  let search = createRemixQueryString(event.multiValueQueryStringParameters);
  let url = new URL(`${scheme}://${host}${event.path}${search}`);
  let controller = new NodeAbortController();
  let isFormData = event.headers["Content-Type"]?.includes("multipart/form-data");

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
  let remixQueryString = new URLSearchParams();

  if (multiValueQueryStringParameters) {
    for (let [param, values] of Object.entries(multiValueQueryStringParameters)) {
      if (values && values.length > 0) {
        for (let value of values) {
          remixQueryString.append(param, value);
        }
      }
    }
    return `?${remixQueryString.toString()}`;
  }

  return "";
}

export function createRemixHeaders(multiValueHeaders: APIGatewayProxyEventMultiValueHeaders): NodeHeaders {
  let remixHeaders = new NodeHeaders();

  if (multiValueHeaders) {
    for (let [param, values] of Object.entries(multiValueHeaders)) {
      if (values && values.length > 0) {
        for (let value of values) {
          remixHeaders.append(param, value);
        }
      }
    }
  }

  return remixHeaders;
}

export async function createApiGatewayResponse(nodeResponse: NodeResponse): Promise<APIGatewayProxyResult> {
  let contentType = nodeResponse.headers.get("Content-Type");

  let isBase64Encoded =
    !contentType ||
    !(contentType.startsWith("text/") || contentType === "application/json" || contentType === "application/xml");

  let headers: APIGatewayProxyResult["headers"] = {};
  let multiValueHeaders: APIGatewayProxyResult["multiValueHeaders"] = {};

  for (let [param, value] of nodeResponse.headers.entries()) {
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

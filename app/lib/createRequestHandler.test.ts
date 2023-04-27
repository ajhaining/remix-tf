import { Headers } from "@remix-run/node";

import { createRemixHeaders } from "~/lib/createRequestHandler";

describe("createRemixHeaders", () => {
  it("creates Remix Header object with the correct header values", () => {
    const mockMultiValueHeaders = { header: ["foo", "bar"] };

    const result = createRemixHeaders(mockMultiValueHeaders);

    const mockRemixHeaders = new Headers();
    mockRemixHeaders.append("header", "foo");
    mockRemixHeaders.append("header", "bar");

    expect(result).toEqual(mockRemixHeaders);
  });
});

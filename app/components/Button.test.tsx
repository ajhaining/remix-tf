import { render, screen } from "@testing-library/react";

import { Button } from "./Button";

describe("Button", () => {
  it("renders the child text", async () => {
    render(<Button>Text</Button>);
    expect(screen.getByRole("button", { name: `Text` })).toBeInTheDocument();
  });
});

import { render, screen } from "@testing-library/react";

import { Button } from "@/components/Button";

describe("Button", () => {
  it("renders the child text", async () => {
    await render(<Button>Text</Button>);
    expect(screen.getByRole("button", { name: `Text` })).toBeInTheDocument();
  });
});

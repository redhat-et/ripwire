import { it, expect } from "vitest";
import { add } from "./lib";
it("adds", () => { expect(add(1, 2)).toBe(3); });

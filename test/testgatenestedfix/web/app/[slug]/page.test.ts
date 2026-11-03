import { it, expect } from "vitest";
import { total } from "./page";
it("totals", () => { expect(total()).toBe(5); });

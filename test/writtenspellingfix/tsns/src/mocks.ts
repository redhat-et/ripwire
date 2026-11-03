declare function tsnsOtherHelper(): void;
export const mock = { serve() { tsnsOtherHelper(); } };
export namespace Other { export function serve() { tsnsOtherHelper(); } }

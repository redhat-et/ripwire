// tsshapefix/objectliteral.ts — a DELIBERATE non-capture, pinned so nobody "fixes" it by accident.
//
// An object-literal property bound to an arrow (`{ onEvent: () => … }`) is the same syntax as the
// class-field arrow that service.ts proves IS captured, but it is not the same thing: openclaw has
// >5 000 of these (the --match engine's cap, so that count is a FLOOR), and they are overwhelmingly
// inline callbacks, vitest mock tables, and config handlers — not a navigable API surface. Taking
// them would add at least 2 % more rows to a 261 760-symbol map, none of which a reader would look
// up by name. The class-field form is bounded (287 sites) and IS the class's callable surface,
// which is the whole difference.

export const handlerTable = {
    onConnect: () => "connected",
    onDisconnect: async () => "disconnected",
    nested: {
        onRetry: ( attempt: number ) => attempt + 1,
    },
};

// the enclosing const IS a symbol when it follows the SCREAMING_SNAKE settings convention — the
// r3 q10 constant capture — so the module is never invisible even though its members are not rows
export const HANDLER_TABLE_LIMITS = {
    maxRetries: 3,
    backoffMs: 250,
};

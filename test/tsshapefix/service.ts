// tsshapefix/service.ts — the TypeScript definition shapes a real repo carries that a fixture
// written from memory does not. Every construct here was lifted from a shape MEASURED in
// openclaw (24 658 .ts files, 2026-08-04); the counts are in test/tsshapecheck.sh's header.

export abstract class TransportBase {
    // abstract_method_signature — the CONTRACT an implementor must satisfy. 76 sites in openclaw.
    abstract send( payload: string ): Promise<void>;
    abstract close(): void;
    protected abstract describeTransport(): string;

    // a concrete method alongside them, so the gate can prove the abstract ones are not merely
    // riding on method_definition's coat-tails
    public isReady(): boolean
    {
        return true;
    }
}

export class SocketTransport extends TransportBase {
    private retries = 0;

    // public_field_definition bound to an arrow — the bound-method idiom. 287 sites in openclaw.
    // Semantically a method: it is the class's callable surface, reachable as `obj.send(...)`.
    send = async ( payload: string ): Promise<void> => {
        this.retries = 0;
        await this.deliver( payload );
    };

    close = (): void => {
        this.retries = 0;
    };

    // static + readonly modifiers must not defeat the pattern
    static readonly makeDefault = (): SocketTransport => new SocketTransport();

    protected describeTransport(): string
    {
        return "socket";
    }

    private async deliver( payload: string ): Promise<void>
    {
        void payload;
    }
}

// a NON-arrow field must NOT become a symbol — the pattern is scoped to callable values, not to
// every class property (public_field_definition with any value is >5000 sites in openclaw — a
// FLOOR, the --match engine's cap — so taking them all would flood the map with data members).
export class PlainFields {
    label = "not-a-symbol";
    limit = 42;
}

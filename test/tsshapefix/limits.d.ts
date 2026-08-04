// tsshapefix/limits.d.ts — the DISCLOSED KNOWN LIMITS of TypeScript extraction, pinned so they
// stay honest: a limit that quietly becomes a capture is as much a surprise as a capture that
// quietly becomes a limit. Each is a measured decision, not an oversight — see the reasoning in
// test/tsshapecheck.sh §4.

// KNOWN LIMIT — the ambient module CONTAINER name is not a symbol (its name is a module specifier
// string, not an identifier anyone can look up). Its CONTENTS are extracted normally, which is
// what navigation actually needs: `ambientToString` and `AmbientOptions` below must both appear.
declare module "vendor-qrcode" {
    export function ambientToString( text: string ): Promise<string>;
    export interface AmbientOptions {
        width?: number;
    }
}

// KNOWN LIMIT — a `declare namespace` CONTAINER name is not a symbol either; the members are.
declare namespace AmbientRuntime {
    function ambientCompile( bytes: ArrayBuffer ): Promise<number>;
}

// KNOWN LIMIT — ambient VALUE bindings (`declare const/let/var`) are not extracted. A real gap in
// openclaw (37 of them), mostly build-time flags and test globals. Unlike the containers above there is
// no member to fall back on, so this one is a real (small) loss, disclosed rather than silent.
declare const AMBIENT_BUILD_FLAG: boolean;
declare let ambientMutableGlobal: number;

// cli_app.ts — the client. The bare specifier "@svc/api" is NOT relative; single-root it is external
// (unresolved). Only the tsconfig `paths` alias below (pointing at the sibling svc root) admits the
// cross-root resolution — evidence-only, unique-or-degrade, never name-based.
import { svcTsApi } from "@svc/api";

export function runTsApp( n: number ): number
{
    return svcTsApi( n );
}

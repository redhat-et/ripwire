// tsconstfix/options.ts — TS-CONST-DEFS: module-level value bindings are definitions (t="var").
// Shapes taken from microsoft/TypeScript's compiler sources (corePublic.ts, commandLineParser.ts, core.ts).

export interface CommandLineOption {
    name: string;
    type: string;
}

export interface Settings {
    retries: number;
}

declare const settingsSource: { pickedAlpha: number; pickedBeta: string; pickedGamma?: number; extra: boolean };
declare const slotPair: [ number, string ];
declare function makeRegistry(): Map<string, number>;

// string consts (corePublic.ts)
export const versionMajorMinor = "6.0";
export const version = "6.0.3" as string;

// number const, not exported
const retryLimit = 3;

// an empty array const (core.ts)
export const emptyArray: never[] = [] as never[];

// a multi-line array const (commandLineParser.ts)
export const commandOptionsWithoutBuild: CommandLineOption[] = [
    {
        name: "help",
        type: "boolean",
    },
    {
        name: "watch",
        type: "boolean",
    },
    {
        name: "preserveWatchOutput",
        type: "boolean",
    },
];

// object consts: `as const`, `satisfies`
export const diagnosticCategoryNames = { warning: 0, error: 1, message: 2 } as const;
export const defaultSettings = { retries: retryLimit } satisfies Settings;

// a template-literal const
export const versionBanner = `Version ${versionMajorMinor}`;

// module-level let / var with literal values
let moduleCounter = 0;
var legacyFlag = true;

// exported destructuring: each bound name is a definition
export const { pickedAlpha, pickedBeta: renamedBeta, pickedGamma = 3, ...pickedRest } = settingsSource;
export const [ firstSlot, secondSlot ] = slotPair;

// NOT definitions: a non-exported destructure (an import-shaped local alias) and a call-valued const
const { extra: privateExtra } = settingsSource;
export const optionRegistry = makeRegistry();

export function countOptions(): number {
    // function-local consts are locals, never definitions
    const functionLocalName = "local";
    const functionLocalTable = [ 1, 2, 3 ];
    moduleCounter += functionLocalTable.length + functionLocalName.length + emptyArray.length;
    return legacyFlag ? moduleCounter : retryLimit + privateExtra.toString().length;
}

// client.ts — a TypeScript class sharing the uniform block's NAME. It has no byte layout at all, and its
// `class MirrorUniforms {` head would otherwise parse as a C++ aggregate and be reported as a third
// "mirror" of the two headers. --layout must ignore it: only C-family files carry a byte contract.
export class MirrorUniforms
{
    gain: number = 0;
    bias: number = 0;
    flags: number = 0;
}

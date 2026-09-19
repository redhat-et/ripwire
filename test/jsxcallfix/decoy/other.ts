// A DECOY: a same-named `Widget`, never imported by renderer.tsx. The JSX call in renderer.tsx must
// not spray onto this one just because the plain name matches — same precision bar a plain
// `Widget()` call already has to clear.
export function Widget() {
  return "decoy";
}

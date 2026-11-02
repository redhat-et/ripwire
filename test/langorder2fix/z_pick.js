// langorder2fix: `let pick = 0;` binds a JS variable that ripwire's grammar does NOT index as a
// definition (measured: the map carries no `pick` row from this file). Kept deliberately: it is what
// makes `pick` a single-def query whose current answer discloses reflang="js" anyway — the exact noise
// the adopted rule removes. helper3 exists only to keep js the corpus majority alongside w_rung.js.
let pick = 0;
function helper3() {}

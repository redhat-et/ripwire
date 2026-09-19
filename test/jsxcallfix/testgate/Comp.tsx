// A component reached ONLY via JSX, from a NAMED helper inside a test-path file whose name does NOT
// match this file's stem (so the file-naming "test partner" heuristic cannot fire — the only way
// --test-gate/--affected can find it is the real CALL GRAPH edge the JSX fix adds).
export default function ModuleWidget() {
  return <h1>Settings</h1>;
}

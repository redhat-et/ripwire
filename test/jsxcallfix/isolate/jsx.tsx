// issue #285 case 1 — minimal repro, attached verbatim to the issue.
function UniqueWidget() {
  return <h1>Settings</h1>;
}

function Wrapper() {
  return <UniqueWidget />;
}

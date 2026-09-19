import ModuleWidget from "../Comp";

// a NAMED function (not the anonymous test(...) callback itself — see #60/issue #285 case 2 for why
// an anonymous enclosing scope is a separate, documented limitation this fixture deliberately avoids)
// so the JSX call site has a real enclosing symbol to attribute the edge to.
function renderModuleWidget() {
  return <ModuleWidget />;
}

test("renders the widget", () => {
  renderModuleWidget();
});

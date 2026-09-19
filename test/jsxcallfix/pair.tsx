// A PAIRED element (open + close) must mint exactly ONE call edge, not two — jsx_closing_element
// repeats the same name and is deliberately not captured (see queries/tsx/tags.scm).
function Panel(props: { children: unknown }) {
  return <section>{props.children}</section>;
}

function PanelHost() {
  return (
    <Panel>
      <span>content</span>
    </Panel>
  );
}

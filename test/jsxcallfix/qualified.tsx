// `<Foo.Bar />` — a qualified/member JSX tag. Binds through member_expression, the same shape
// `Foo.Bar()` already captures, so it must resolve as a call to Bar with a receiver, not go missing
// and not get filtered as an "intrinsic" tag (member tags are never intrinsic, whatever the case).
function Bar() {
  return null;
}
const Foo = { Bar };

function QualifiedHost() {
  return <Foo.Bar />;
}

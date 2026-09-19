// Intrinsic HTML/SVG tags and a fragment must mint NO edge and NO phantom symbol — the grammar gives
// them the identical (identifier)/(jsx_namespace_name) shape a real component tag has, so the filter
// is the tag name's own first letter (isJsxIntrinsicTagIdentifier, src/ingest_names.h) plus the
// namespaced form's distinct grammar node (jsx_namespace_name, never captured at all).
function IntrinsicHost() {
  return (
    <div className="x">
      <h1>hi</h1>
      <svg:rect width={1} height={1} />
      <>
        <span>fragment child</span>
      </>
    </div>
  );
}

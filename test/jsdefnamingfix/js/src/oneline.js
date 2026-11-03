class OneP { oq() { return jdnOneHelper(); } }
function jdnOneHelper() {}
const outerArrow = () => { const innerArrow = () => jdnOneHelper(); return innerArrow(); };

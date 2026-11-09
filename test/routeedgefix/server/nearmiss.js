// (#448) near-miss: a leading-'/' first argument on a framework-free `.get` with a NON-function
// second argument — a settings lookup, not a route registration. Must register nothing.
const settings = new Map();

function readSetting(key) {
    return settings.get('/defaults', 'fallback');
}

module.exports = { readSetting };

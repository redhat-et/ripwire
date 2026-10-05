// The global object's own names (self, window, global, globalThis) declared as an ordinary local or parameter: a call
// on one is a call on that value, not on the global object.
function Worker() {}
Worker.prototype.process = function (item) { return item; };
Worker.prototype.run = function (item) { var self = this; return self.process(item); };
Worker.prototype.runWin = function (item) { const window = this; return window.process(item); };
function viaParam(global, item) { return global.process(item); }
// No declaration: `self` IS the global object here, so `self.process` is the runtime's, never the method above.
function onMessage(item) { return self.process(item); }
module.exports = { Worker, viaParam, onMessage };

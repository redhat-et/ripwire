"use strict";

/**
 * The pre-class half of the fixture: prototype assignment, the idiom node/lib still carries
 * 332 sites of (169 survived only via NAMED function-expression inner names; the anonymous
 * 163 were invisible). Plus the decoys the prototype gate must NOT adopt.
 */
function Socket(options) {
	this.options = options;
	this.state = { handler: null };
}

/** anonymous function — the measured 0%-recall shape (node/lib/net.js:812) */
Socket.prototype.setNoDelay = function (enable) {
	return this._handle && enable;
};

/** arrow on the prototype — same idiom, arrow spelling */
Socket.prototype.unref = () => null;

/** NAMED function expression — the inner name already extracted pre-round; property name rides it */
Socket.prototype.connect = function connect(options) {
	return options;
};

/** deep qualifier chain — net.exports.Socket.prototype.destroySoon */
const net = { exports: { Socket } };
net.exports.Socket.prototype.destroySoon = function () {
	return null;
};

/** DECOYS — structurally `a.b = fn` / `a.b.c = fn` but NOT prototype and NOT exports:
 *  an instance-slot handler and a this-chained handler. The gate must leave both out. */
const socketLike = { onclose: null, state: { handler: null } };
socketLike.onclose = function () {
	return "not a definition";
};
socketLike.state.handler = () => "not a definition either";

module.exports = Socket;

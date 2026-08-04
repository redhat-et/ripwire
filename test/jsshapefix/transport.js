"use strict";

/**
 * The modern-class half of the JS shape fixture: class fields bound to arrows/functions
 * (the bound-method idiom), #private methods, and the plain data fields that must stay out.
 * Derived from webpack@957bf3a + node@427d2e1 lib/ measurement, 2026-08-04.
 */
class Transport {
	/** async arrow field — the bound-method idiom (node/lib/internal/watchdog.js:10 shape) */
	send = async payload => {
		await this.#push(payload);
		return this.ready;
	};

	/** bare arrow field */
	close = () => {
		this.ready = false;
	};

	/** function-expression field (anonymous) */
	reset = function () {
		return null;
	};

	/** static arrow field (webpack es2020 fixture shape) */
	static makeDefault = () => new Transport();

	/** #private arrow field (node/lib/diagnostics_channel.js shape) */
	#drain = () => this.queue.splice(0);

	/** plain data fields — NON-callable, must NOT become symbols (TS-parity scope line) */
	label = "transport";
	limit = 64;
	static kindName = "socket";

	/** #private method (node/lib has 232 of these, 0 extracted before this round) */
	#push(payload) {
		this.queue.push(payload);
	}

	/** static #private method */
	static #register(instance) {
		return instance;
	}

	constructor() {
		this.queue = [];
		this.ready = true;
		Transport.#register(this);
	}

	/** pre-existing shapes that must keep working: getter/setter/generator/computed-name */
	get size() {
		return this.queue.length;
	}

	set size(v) {
		this.queue.length = v;
	}

	*entries() {
		yield* this.queue;
	}

	/** computed-name method — DISCLOSED KNOWN LIMIT: the name is a runtime expression */
	[Symbol.asyncIterator]() {
		return this.queue.values();
	}
}

module.exports = Transport;

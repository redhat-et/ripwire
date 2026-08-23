"use strict";

/** The module under test: imported by four sibling files, called by exactly one of them. */
class Widget
{
    constructor( label )
    {
        this.label = label;
    }

    attach( host )
    {
        return host + ":" + this.label;
    }
}

module.exports = Widget;

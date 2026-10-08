// The two SIDES of a class lookup: a call on the CLASS object reaches its static members, a call on an INSTANCE the others.
class Gauge {
  static read () { return 1 }
  read () { return 2 }
  static make () { return this.read() }
}
class Plain {
  read () { return 3 }
}
function onClass () { return Gauge.read() }
function onInstance () { return new Gauge().read() }
function wrongSide () { return Plain.read() }
module.exports = { Gauge, Plain, onClass, onInstance, wrongSide }

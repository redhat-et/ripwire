class Nest {
  make() {
    return { inner() { return jdnNestHelper() } }
  }
}
function jdnNestHelper() {}
module.exports = Nest

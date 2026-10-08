// io: callables whose names are common English verbs (get, then, write). A question that USES those verbs
// ("the gateway gets the session token, checks it, then writes it") must not spend every owner slot on them.
function ioNote(x: string): string { return x }
export class Router {
  // get: read a session token
  get(path: string) { return ioNote(path) }
}
export class Deferred {
  // then: continue with a session token
  then(path: string) { return ioNote(path) }
}
export class Sink {
  // write: store a session token
  write(path: string) { return ioNote(path) }
}

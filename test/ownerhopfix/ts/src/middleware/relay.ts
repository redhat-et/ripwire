// relay: a middleware whose ONLY callee is an untyped receiver call — bound by name alone (FE-B via="name"), never proven.
export function relay(ctx) {
  const store: any = ctx
  store.remember('relay', 1)
  return 0
}

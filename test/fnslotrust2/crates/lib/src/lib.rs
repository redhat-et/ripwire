pub struct Hook { cb: fn() }
impl Hook {
    pub fn fire(&self) { (self.cb)() }
}
pub fn spawn(f: fn()) -> Hook { Hook { cb: f } }
pub fn lib_target() {}
pub fn mk() -> Hook { Hook { cb: lib_target } }
// CR 4408459928 (harvest 463): a callee the function itself binds (a parameter, a local closure) is never the in-tree registrar of that name
pub fn worker_param_callee() {}
pub fn run_param(spawn: fn(fn())) { spawn(worker_param_callee) }
pub fn worker_local_callee() {}
pub fn run_local() { let spawn = |f: fn()| f(); spawn(worker_local_callee) }

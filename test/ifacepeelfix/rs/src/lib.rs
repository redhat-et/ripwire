pub trait Command {
    fn name(&self) -> &str;
    fn run(&self, x: i32) -> i32;
}
pub struct Ls;
impl Command for Ls {
    fn name(&self) -> &str { "ls" }
    fn run(&self, x: i32) -> i32 { x + 1 }
}
pub struct Cd;
impl Command for Cd {
    fn name(&self) -> &str { "cd" }
    fn run(&self, x: i32) -> i32 { x + 2 }
}
pub struct CallEval;
impl CallEval {
    pub fn run(&self) -> i32 { 0 }
}
pub struct State { decls: Vec<Box<dyn Command>> }
impl State {
    pub fn get_decl(&self, id: usize) -> &dyn Command { self.decls[id].as_ref() }
    pub fn boxed_decl(&self, id: usize) -> Box<dyn Command> { match id { 0 => Box::new(Ls), _ => Box::new(Cd) } }
    pub fn any_decl<T: Command>(&self) -> T { unimplemented!() }
}
pub struct Overlay;
impl Overlay {
    pub fn get_decl(&self, id: usize) -> Option<usize> { Some(id) }
}
pub struct EvalContext<'a> { pub engine_state: &'a State, pub depth: usize }
pub fn eval_call(state: &State, id: usize) -> i32 {
    let decl = state.get_decl(id);
    decl.run(3)
}
pub fn eval_boxed(state: &State, id: usize) -> i32 {
    let decl = state.boxed_decl(id);
    decl.run(5)
}
pub fn eval_destructured(ctx: &mut EvalContext<'_>, id: usize) -> i32 {
    let EvalContext { engine_state, .. } = ctx;
    let decl = engine_state.get_decl(id);
    decl.run(6)
}
pub fn eval_unknown<S>(s: S, id: usize) -> i32 where S: Clone {
    let decl = s.get_decl(id);
    decl.run(7)
}
pub fn eval_generic(state: &State) -> i32 {
    let decl = state.any_decl();
    decl.run(8)
}

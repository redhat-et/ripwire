use extcrate::Hook;
use tokio::spawn;
fn worker_ext_struct() {}
fn worker_bare_ext() {}
fn worker_path_ext() {}
fn main() {
    let _h = Hook { cb: worker_ext_struct };
    spawn(worker_bare_ext);
    std::thread::spawn(worker_path_ext);
}

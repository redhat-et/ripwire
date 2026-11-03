// Precise capturing (Rust 1.82): an EMPTY `+ use<>` bound on a return-position impl Trait. The vendored grammar reads
// `use<..>` as a generic type named `use`; the empty list needs a MISSING type, and the recovery around the async body
// below collapses this WHOLE file into one ERROR node on the first parse (err_ratio=1.000, every method owner lost).
use std::future::Future;
use std::sync::Arc;

pub struct Pane {
    store: Store,
}

impl Pane {
    pub fn save_item(
        &self,
        version: &Self::Version,
        dir: &PathBuf,
        delegate: &Arc<dyn Delegate>,
    ) -> impl Send + Future<Output = Option<store::Saved>> + use<> {
        let store = self.store.clone();
        let version = version.clone();
        let dir = dir.clone();
        let delegate = delegate.clone();

        async move {
            let path = dir
                .join("items")
                .join(Self::ITEM_PATH);

            let should_write = store
                .needs_write(
                    Self::ITEM_NAME,
                    &path,
                    &dir,
                    Strategy::Latest(&version),
                )
                .await;

            if should_write {
                None
            } else {
                let env = delegate.env().await;
                Some(Saved {
                    path: store.path().await.ok()?,
                    env: Some(env),
                    tags: vec![path.into(), "saved".into()],
                })
            }
        }
    }

    pub fn close_item(&mut self, index: usize) {
        self.store.remove(index);
    }
}

pub struct Workspace {
    panes: Vec<Pane>,
}

impl Workspace {
    pub fn new_local(panes: Vec<Pane>) -> Self {
        Workspace { panes }
    }

    pub fn first_pane(&self) -> Option<&Pane> {
        self.panes.first()
    }
}

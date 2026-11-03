// The same collapse with the bound split onto its own line and a comment after it: `+ use<>` is matched as tokens,
// not as one spelling; the comment after it is not part of the span and stays.
use std::future::Future;
use std::sync::Arc;

pub struct Buffer {
    store: Store,
}

impl Buffer {
    pub fn edit(
        &self,
        version: &Self::Version,
        dir: &PathBuf,
        delegate: &Arc<dyn Delegate>,
    ) -> impl Send + Future<Output = Option<store::Saved>>
        + use<> /* none */ {
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

    pub fn undo(&mut self, index: usize) {
        self.store.remove(index);
    }
}

pub struct Editor {
    buffers: Vec<Buffer>,
}

impl Editor {
    pub fn backspace(buffers: Vec<Buffer>) -> Self {
        Editor { buffers }
    }

    pub fn first_buffer(&self) -> Option<&Buffer> {
        self.buffers.first()
    }
}

# Paging design

The page cache holds a fixed number of pages. A pinned page is one the reader
still holds; the evictor must skip it and choose another victim. A flush walks
every dirty page and writes it back before the cache is reused.

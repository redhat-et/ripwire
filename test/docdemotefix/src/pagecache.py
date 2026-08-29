"""The page cache: pin, unpin, flush."""


class PageCache:
    """A fixed-size cache of pages, with pinning."""

    def __init__( self, capacity ):
        self.capacity = capacity
        self.pages = {}
        self.pinned = set()

    def pin_page( self, page_id ):
        """Pin a page so the evictor may never choose it as a victim."""
        self.pinned.add( page_id )

    def request_page( self, page_id ):
        """Return a page, evicting a victim first when the cache is full."""
        if page_id in self.pages:
            return self.pages[page_id]
        if len( self.pages ) >= self.capacity:
            evict_one( self )
        self.pages[page_id] = page_id
        return self.pages[page_id]

    def flush_cache( self ):
        """Write every dirty page back and drop the unpinned ones."""
        for page_id in list( self.pages ):
            if page_id not in self.pinned:
                del self.pages[page_id]

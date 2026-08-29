"""Eviction policy for the page cache."""


def evict_one( cache ):
    """Choose a victim page and evict it, never a pinned page."""
    for page_id in list( cache.pages ):
        if page_id in cache.pinned:
            continue
        del cache.pages[page_id]
        return page_id
    raise RuntimeError( "no victim available" )

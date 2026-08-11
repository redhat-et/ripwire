"""The no-adoption arm: shapes the 2026-08-04 recall round measured at 100% on both
corpora — decorated (incl. stacked), property family, async, nested, module lambda."""

import functools


class Service:
    @property
    def endpoint_url(self):
        return self._url

    @endpoint_url.setter
    def endpoint_url(self, value):
        self._url = value

    @staticmethod
    def parse_headers(raw):
        return dict(raw)

    @classmethod
    def from_env(cls):
        return cls()


@functools.lru_cache
def resolve_route(path):
    return path


@functools.wraps(resolve_route)
@functools.lru_cache
def resolve_route_stacked(path):
    return resolve_route(path)


async def stream_frames(sock):
    return await sock.read()


def outer_task():
    def inner_step():
        return 1
    return inner_step


make_key = lambda ns, name: f"{ns}:{name}"

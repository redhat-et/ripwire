"""Tiny FastAPI server fixture for the B6.3 HTTP-route edge gate (test/routeedgecheck.sh)."""
from fastapi import FastAPI

app = FastAPI()


@app.get("/users/{user_id}")
def get_user(user_id: int):
    return {"id": user_id}


@app.post("/users")
def create_user():
    return {}


@app.get("/orders/{order_id}")
def get_order(order_id: int):
    return {}


# deliberately AMBIGUOUS pair: same method + same path SHAPE (one literal segment + one template
# segment), two DIFFERENT handlers. A client call matching this shape must resolve to NEITHER —
# the conservative "no match on ambiguous prefixes" rule — never a guess.
@app.get("/items/{item_id}")
def get_item_by_id(item_id: int):
    return {}


@app.get("/items/{name}")
def get_item_by_name(name: str):
    return {}


# a route with no client caller anywhere in the fixture — a DEF fact with zero USE matches.
@app.get("/unused")
def unused_handler():
    return {}

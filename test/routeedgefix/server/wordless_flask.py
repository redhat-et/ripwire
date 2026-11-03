# no flask/fastapi word anywhere — the decorator shape alone must register
def get_user(uid):
    return {"id": uid}

@app.get("/api/users/{user_id}")
def get_user_route():
    return get_user(1)

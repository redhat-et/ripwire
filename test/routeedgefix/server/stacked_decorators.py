# stacked decorators: each produces exactly one route (not duplicates)
def multi_handler():
    return 1

@app.get("/multi/a")
@app.route("/multi/b", methods=["GET"])
def stacked_handler():
    return multi_handler()

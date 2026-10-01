from router import Router


def index(request):
    return {"hello": request.path}


def serve(app_router, requests):
    responses = []
    for request in requests:
        responses.append(app_router.dispatch(request))
    return responses


def main():
    router = Router()
    router.add_route("/", index)
    return serve(router, [])

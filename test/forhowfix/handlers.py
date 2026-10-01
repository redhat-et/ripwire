from validate import validate_request
from render import render_response


def call_handler(handler, request):
    if not validate_request(request):
        raise ValueError("invalid request")
    result = handler(request)
    return render_response(result)


def not_found(request):
    return render_response({"status": 404, "path": request.path})

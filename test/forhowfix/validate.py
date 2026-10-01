ALLOWED = ("GET", "POST")


def validate_request(request):
    if request.method not in ALLOWED:
        return False
    return check_headers(request.headers)


def check_headers(headers):
    return "host" in headers

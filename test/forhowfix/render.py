import json


def render_response(result):
    body = encode_body(result)
    return {"status": 200, "body": body}


def encode_body(result):
    return json.dumps(result)


def render_error(message):
    return render_response({"error": message})

# forcallerhopfix/rankpy — UPWARD-2HOP F2: the seed method (HeaderParser.parse_header) is reached through a duck-typed parameter, so its only first-hop caller is a by-name match
class HeaderParser:
    def parse_header(self, data):
        if not data.startswith(b"HDR"):
            raise ValueError("bad header error")
        return data[3:]


class LenientParser:
    def parse_header(self, data):
        return data


def load_blob(parser, data):
    return parser.parse_header(data)


def import_file(path):
    with open(path, "rb") as f:
        return load_blob(HeaderParser(), f.read())


def import_lenient(path):
    with open(path, "rb") as f:
        return load_blob(LenientParser(), f.read())

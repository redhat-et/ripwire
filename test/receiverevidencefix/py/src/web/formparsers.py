import multipart


def parse_form(callbacks, chunks):
    """A parser object built by an outside package beside UploadFile.write."""
    parser = multipart.QuerystringParser(callbacks)
    for chunk in chunks:
        parser.write(chunk)

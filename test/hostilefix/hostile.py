# comment with a lone invalid UTF-8 byte follows this colon: È (not a continuation)

def cafe_size_with_form_feed():
    s = "formfeed-inside-string"
    return len(s)

def caf√©_size(n):
    return cafe_size_with_form_feed() + n

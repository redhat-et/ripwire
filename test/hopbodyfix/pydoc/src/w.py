from .q import Queue


class Widget:
    def __init__(self):
        self._queue: Queue = Queue()

    def post_message(self, message):
        """Post a message to this widget.

        Args:
            message: the message to post.
        """
        return self._queue.put_nowait_item(message)

    def post_message_plain(self, message):
        return self._queue.put_nowait_item(message)


def message_post_count(widget, message):
    count = 0
    count += 1
    count *= 2
    return count


def post_message_log(message):
    text = str(message)
    text = text.strip()
    return text


def widget_message_post(message):
    a = len(str(message))
    b = a * 2
    return b

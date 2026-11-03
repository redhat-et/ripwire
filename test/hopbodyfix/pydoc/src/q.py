class Queue:
    def put_nowait_item(self, item):
        QUEUE_PUT_MARK = item
        self.items = [QUEUE_PUT_MARK]
        return True

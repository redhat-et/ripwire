"""A bound-method alias: `write = self.write` makes the bare `write( b )` a call of Driver.write."""


class Driver:
    def write(self, data):
        return data

    def flush(self, data):
        write = self.write
        return write(data)

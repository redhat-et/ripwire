# The flake8 formatter shape: Default/Pylint/FilenameOnly subclass SimpleFormatter, which subclasses BaseFormatter.
class BaseFormatter:
    def format(self, error):
        raise NotImplementedError


class SimpleFormatter(BaseFormatter):
    error_format = None


class Default(SimpleFormatter):
    error_format = "%(path)s"


class Pylint(SimpleFormatter):
    error_format = "%(path)s:%(row)d"


class FilenameOnly(SimpleFormatter):
    error_format = "%(path)s"


class Nothing(BaseFormatter):
    pass

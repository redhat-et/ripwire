from case import camel_to_snake


class Message:
    namespace = ""

    def __init_subclass__(cls, namespace=None):
        super().__init_subclass__()
        if namespace is not None:
            name = f"{namespace}_{camel_to_snake(cls.__name__)}"
        else:
            parts = cls.__qualname__.rsplit(".", 2)[-2:]
            name = "_".join(camel_to_snake(p) for p in parts)
        cls.handler_name = f"on_{name}"

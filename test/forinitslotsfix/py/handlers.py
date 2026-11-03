def run_handler(x):
    return x + 1


def stop_handler(x):
    return x - 1


HANDLER_TABLE = {"run": run_handler, "stop": stop_handler}


def dispatch_handler(name, x):
    return HANDLER_TABLE[name](x)

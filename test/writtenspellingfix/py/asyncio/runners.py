class Runner:
    def run(self, coro):
        return py_runner_method_helper(coro)


def run(main):
    return py_asyncio_run_helper(main)


def py_runner_method_helper(x):
    return x


def py_asyncio_run_helper(x):
    return x

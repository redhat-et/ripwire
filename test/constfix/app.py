# Python settings module — pins the EXISTING behavior: every module-level assignment
# is a var def regardless of case (vendored tree-sitter-python tags, unchanged).

PY_SETTING_MODE = "strict"

py_lower_setting = 1


def read_mode():
    return PY_SETTING_MODE

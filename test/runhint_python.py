#!/usr/bin/env python3
"""#229: a Python module is not evidence that python3 will run its tests."""

import json
from pathlib import Path
import shutil
import subprocess
import sys
import xml.etree.ElementTree as ET

binary = str(Path(sys.argv[1]).resolve())
scratch = Path(sys.argv[2]) / "python-runners"
failures = []
test_source = "def test_answer():\n    assert 6 * 7 == 42\n"


def check(name, files, expected, target="tests/test_answer.py"):
    """Create a fixture and check its runner across JSON, XML and text output.

    expected=None requires unknown-runner disclosure. Collect mismatches in failures,
    raise on scan errors, and return the fixture root for optional command execution.
    """
    root = scratch / name
    for path, content in files.items():
        dest = root / path
        dest.parent.mkdir(parents=True, exist_ok=True)
        dest.write_text(content)
    for spelling in (str(root), ".", str(root) + "/"):
        result = subprocess.run(
            [binary, spelling, f"--test-gate={target}", "--json", "--no-cache"],
            cwd=root, text=True, capture_output=True, timeout=30,
        )
        if result.returncode != 4:
            raise AssertionError(f"{name}: scan failed: {result.stderr}")
        rows = json.loads(result.stdout)["tests_to_run"]
        row = next(row for row in rows if row["p"] == target)
        if row.get("run") != expected:
            failures.append(f"{name}: expected {expected!r}, got {row!r}")
        if expected is None and row.get("run_unknown") not in (True, 1):
            failures.append(f"{name}: missing unknown-runner disclosure: {row!r}")
    # The issue names both surfaces. Parse XML, rather than comparing its escaped shell syntax.
    affected = subprocess.run(
        [binary, str(root), f"--affected={target}", "--no-cache"],
        text=True, capture_output=True, timeout=30, check=True,
    )
    rows = [node for node in ET.fromstring(affected.stdout).iter() if node.get("p") == target]
    if not rows or rows[0].get("run") != expected:
        failures.append(f"{name}: affected runner differs: {[row.attrib for row in rows]}")
    situ = subprocess.run(
        [binary, str(root), f"--situ={target}", "--no-cache"],
        text=True, capture_output=True, timeout=30, check=True,
    )
    if expected is not None and f"(run: {expected})" not in situ.stdout:
        failures.append(f"{name}: situ omitted the runner")
    if expected is None and "(run: python3 " in situ.stdout:
        failures.append(f"{name}: situ still guesses python3")
    return root


for config, content in (
    ("pytest.ini", ""),
    ("conftest.py", "# pytest fixtures\n"),
    ("pyproject.toml", "[tool.pytest.ini_options]\naddopts = '-q'\n"),
    ("setup.cfg", "[tool:pytest]\naddopts = -q\n"),
):
    check(config.replace(".", "-"), {config: content, "tests/test_answer.py": test_source},
          "pytest tests/test_answer.py")

check("nested", {"package/pytest.ini": "", "package/tests/test_answer.py": test_source},
      "pytest package/tests/test_answer.py", "package/tests/test_answer.py")
check("plain-module", {"tests/test_answer.py": test_source}, None)
check("unittest", {"tests/test_answer.py": "import unittest\nclass TestAnswer(unittest.TestCase):\n    def test_answer(self):\n        self.assertEqual(42, 42)\n"}, None)
check("django", {"manage.py": "# Django launcher\n", "tests/test_answer.py": "from django.test import TestCase\nclass TestAnswer(TestCase):\n    def test_answer(self):\n        self.assertEqual(42, 42)\n"}, None)
check("unrelated-config", {"pyproject.toml": "[tool.ruff]\nline-length = 100\n", "setup.cfg": "[metadata]\nname = example\n", "tests/test_answer.py": test_source}, None)
check("commented-config", {"pyproject.toml": "# [tool.pytest.ini_options]\n", "tests/test_answer.py": test_source}, None)
check("config-in-string", {"pyproject.toml": 'description = """\n[tool.pytest.ini_options]\n"""\n', "tests/test_answer.py": test_source}, None)
check("config-in-value", {"setup.cfg": "[metadata]\ndescription =\n    [tool:pytest]\n", "tests/test_answer.py": test_source}, None)
check("docstring", {"tests/test_answer.py": '\'\'\'Example:\nif __name__ == "__main__":\n    test_answer()\n\'\'\'\n' + test_source}, None)
check("comment", {"tests/test_answer.py": test_source + '# if __name__ == "__main__": test_answer()\n'}, None)
check("nested-main", {"tests/test_answer.py": test_source + 'def unused():\n    if __name__ == "__main__":\n        test_answer()\n'}, None)
check("wrong-main-string", {"tests/test_answer.py": test_source + 'if __name__ == "__ main__":\n    test_answer()\n'}, None)
check("fallback-runner", {"tests/fixture.cpp": "int main() { return 0; }\n",
                          "tests/fixture.py": test_source,
                          "tests/run.sh": "# runs fixture.cpp\nexit 0\n"},
      "bash tests/run.sh", "tests/fixture.cpp")
for quote in ("'", '"'):
    source = test_source + f"if __name__ == {quote}__main__{quote}:\n    test_answer()\n"
    check("main-" + ("single" if quote == "'" else "double"),
          {"tests/test_answer.py": source}, "python3 tests/test_answer.py")

# A config belonging to the parent of the crawl must not turn a nested, unrelated repo into pytest.
(scratch / "pytest.ini").write_text("")
check("outside-root", {"tests/test_answer.py": test_source}, None)
(scratch / "pytest.ini").unlink()

# Each member of a multi-root scan owns its own config boundary and keeps an absolute command path.
multi = subprocess.run(
    [binary, str(scratch / "pytest-ini"), str(scratch / "plain-module"),
     "--affected=tests/test_answer.py", "--no-cache"],
    text=True, capture_output=True, timeout=30,
)
rows = [node.attrib for node in ET.fromstring(multi.stdout).iter() if node.get("p")]
commands = [row.get("run") for row in rows]
expected = f"pytest {scratch / 'pytest-ini' / 'tests/test_answer.py'}"
if multi.returncode != 0 or len(rows) != 2 or commands.count(expected) != 1 or commands.count(None) != 1:
    failures.append(f"multi-root runner evidence leaked between projects: {rows!r}")

# Pasting the hint must run the test, including hostile paths. No pytest dependency is added to ripwire;
# command/disclosure checks above run everywhere, and this execution arm runs when the tool is installed.
for target in ("tests/test_answer;touch PWNED.py", "-cprint(42)_test.py"):
    source = "from pathlib import Path\n" + test_source + '    Path("RAN").write_text("yes")\n'
    command = f"pytest -- '{target}'"
    root = check("hostile-" + ("dash" if target.startswith("-") else "shell"),
                 {"pytest.ini": "", target: source}, command, target)
    if shutil.which("pytest"):
        (root / "RAN").unlink(missing_ok=True)
        (root / "PWNED.py").unlink(missing_ok=True)
        result = subprocess.run(command, shell=True, cwd=root, text=True, capture_output=True, timeout=30)
        if result.returncode != 0 or not (root / "RAN").exists() or (root / "PWNED.py").exists():
            failures.append(f"hostile command did not run exactly the test: {result.stdout} {result.stderr}")
    else:
        print("  SKIP  pytest command execution (pytest is not installed)")

if failures:
    for failure in failures:
        print("  FAIL ", failure)
    sys.exit(1)
print("  PASS  Python runner evidence across test-gate, affected and situ")

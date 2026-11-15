"""probe.py — a non-Bash env read: its row must carry no Bash form attributes."""
import os

if os.environ.get("PY_SWITCH"):
    print("on")

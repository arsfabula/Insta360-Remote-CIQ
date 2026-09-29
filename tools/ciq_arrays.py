"""Extract the hard-coded command arrays from a Connect IQ source file.

The golden tests read BLEBarrel.mc directly instead of carrying a copy of the
bytes, so they cannot drift away from what actually ships on the watch.
"""

import os
import re

ARRAY_RE = re.compile(
    r"var\s+(cmd\w+)\s*=\s*\[([^\]]*)\]b\s*;",
    re.IGNORECASE,
)
COMMENT_RE = re.compile(r"//(.*)$", re.MULTILINE)
TRAILING_COMMENT_RE = re.compile(r"\s*//(.*)$", re.MULTILINE)


def parse_int_array(body):
    values = []
    for token in body.split(","):
        token = token.strip()
        if not token:
            continue
        try:
            # Hex literals legitimately end in 'b' (0x1b, 0x8b), so the suffix
            # must never be stripped blindly; only fall back to a binary
            # literal when the token does not parse as a plain integer.
            value = int(token, 0)
        except ValueError:
            if not token.lower().endswith("b"):
                raise ValueError("cannot parse CIQ byte literal %r" % token)
            value = int(token[:-1], 2)
        if not 0 <= value <= 0xFF:
            raise ValueError("byte literal out of range: %r" % token)
        values.append(value)
    return values


def source_path(root=None):
    if root is None:
        root = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
    return os.path.join(root, "BLE Barrel", "BLEBarrel.mc")


def _blank_comments(text):
    """Replace comment bodies with spaces, preserving every offset.

    Offsets matter because line numbers and trailing labels are read back from
    the original text using positions found in the blanked copy.
    """
    return COMMENT_RE.sub(lambda m: " " * len(m.group(0)), text)


def read_commands(root=None, path=None):
    """Return {name: {'bytes': [...], 'comment': str, 'line': int}}."""
    if path is None:
        path = source_path(root)
    with open(path, "r", encoding="utf-8", errors="replace") as handle:
        raw = handle.read()

    blanked = _blank_comments(raw)
    commands = {}
    for match in ARRAY_RE.finditer(blanked):
        entry = {
            "bytes": parse_int_array(match.group(2)),
            "line": raw.count("\n", 0, match.start()) + 1,
        }
        trailing = TRAILING_COMMENT_RE.match(raw, match.end())
        if trailing:
            entry["comment"] = trailing.group(1).strip()
        commands[match.group(1)] = entry

    return commands


def read_command_bytes(root=None, path=None):
    return {name: entry["bytes"] for name, entry in read_commands(root, path).items()}

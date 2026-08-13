"""Build the release zip with spec-correct entry names.

Usage:
    python make_zip.py [output.zip]

Why this exists: Windows PowerShell's Compress-Archive writes zip entries with
BACKSLASH separators (yads\\manifest.json). The zip spec (APPNOTE 4.4.17)
allows forward slashes only. Windows extractors forgive the violation; Linux
tools (Ark, unzip) and MOMI's own reader on Linux do not - they see one flat
file literally named "yads\\manifest.json" and the install fails with a JSON
parse error at position 0. Python's zipfile always writes forward slashes.

The zip contains a single top-level yads/ directory, so extracting into
Fields of Mistria/mods/ yields mods/yads/manifest.json - no double nesting.
"""

import os
import sys
import zipfile

HERE = os.path.dirname(os.path.abspath(__file__))
MOD_DIR = os.path.join(HERE, "yads")


def main() -> None:
    out = sys.argv[1] if len(sys.argv) > 1 else os.path.join(
        HERE, "YADS - Yet Another Digital Storage.zip")
    count = 0
    with zipfile.ZipFile(out, "w", zipfile.ZIP_DEFLATED) as z:
        for root, dirs, files in os.walk(MOD_DIR):
            dirs.sort()
            for name in sorted(files):
                full = os.path.join(root, name)
                rel = os.path.relpath(full, HERE)
                arc = rel.replace(os.sep, "/")
                assert "\\" not in arc, arc
                z.write(full, arc)
                count += 1
    bad = [n for n in zipfile.ZipFile(out).namelist() if "\\" in n]
    print(f"{out}: {count} entries, separators clean: {not bad}")
    if bad:
        sys.exit(1)


if __name__ == "__main__":
    main()

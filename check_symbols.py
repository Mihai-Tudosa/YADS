"""Static symbol checker for the mod's GML.

Oracle: a symbol our GML uses is OK iff it is defined OR used anywhere in
  (a) the game's own GML        (gmlsrc/assets/gml/**)
  (b) the MMAPI shipped payload (momi/ModsOfMistriaInstallerLib/Seam/Payload/mmapi/*.gml)
  (c) the MMAPI test fixtures   (momi/ModsOfMistriaInstallerLibTests/Fixtures/GmlRuntime/**)
The game code exercises the engine's real builtin surface, so "appears in the
game source" is the strongest available proof a builtin exists in THIS engine
(which is not stock GameMaker). Anything we call that appears nowhere is either
ours (defined in the mod) or a bug.

Usage:
    python check_symbols.py <mod_gml_dir> [corpus_root ...]

The corpus root is the directory that holds an extraction of the game's GML and
(optionally) a checkout of the MOMI installer repo. It comes from, in order:

    1. every extra command-line argument, or
    2. the FOM_CORPUS environment variable (os.pathsep-separated), or
    3. nothing, in which case the checker refuses to run rather than silently
       passing on an empty corpus.

Inside each root the checker looks for these subtrees and uses the ones present:

    gmlsrc/                                                  extracted assets/gml
    momi/ModsOfMistriaInstallerLib/Seam/Payload/mmapi
    momi/ModsOfMistriaInstallerLibTests/Fixtures/GmlRuntime

A root may also BE one of those trees directly (e.g. a bare assets/gml folder).

Example (a scratch directory holding an assets/gml extraction and a MOMI clone):

    python check_symbols.py yads/gml D:/work/fom-corpus

Exit 1 if any unknown symbols are found.
"""

import os
import re
import sys

# Subtrees searched inside every corpus root. A root with none of them is used
# as-is, so pointing straight at an `assets/gml` extraction also works.
CORPUS_SUBDIRS = [
    "gmlsrc",
    os.path.join("momi", "ModsOfMistriaInstallerLib", "Seam", "Payload", "mmapi"),
    os.path.join("momi", "ModsOfMistriaInstallerLibTests", "Fixtures", "GmlRuntime"),
]


def corpus_dirs(roots):
    dirs = []
    for root in roots:
        found = [os.path.join(root, sub) for sub in CORPUS_SUBDIRS]
        found = [d for d in found if os.path.isdir(d)]
        dirs.extend(found if found else [root])
    return dirs

WORD = re.compile(r"[A-Za-z_][A-Za-z0-9_]*")
CALL = re.compile(r"\b([A-Za-z_][A-Za-z0-9_]*)\s*\(")
GLOBALREF = re.compile(r"\bglobal\.([A-Za-z_][A-Za-z0-9_]*)")

KEYWORDS = {
    "if", "else", "while", "for", "do", "until", "repeat", "switch", "case",
    "default", "break", "continue", "return", "exit", "with", "var", "function",
    "constructor", "new", "delete", "try", "catch", "finally", "throw", "static",
    "enum", "true", "false", "undefined", "self", "other", "noone", "all",
    "global", "and", "or", "not", "xor", "mod", "div", "begin", "end", "then",
}


def strip_comments_strings(src: str) -> str:
    out = []
    i, n = 0, len(src)
    while i < n:
        c = src[i]
        if c == "/" and i + 1 < n and src[i + 1] == "/":
            j = src.find("\n", i)
            i = n if j < 0 else j
        elif c == "/" and i + 1 < n and src[i + 1] == "*":
            j = src.find("*/", i + 2)
            i = n if j < 0 else j + 2
        elif c in "\"'":
            q = c
            j = i + 1
            while j < n:
                if src[j] == "\\":
                    j += 2
                    continue
                if src[j] == q:
                    break
                j += 1
            out.append('""')
            i = j + 1
        elif c == "@" and i + 1 < n and src[i + 1] in "\"'":  # @"verbatim"
            q = src[i + 1]
            j = src.find(q, i + 2)
            out.append('""')
            i = (n if j < 0 else j + 1)
        elif c == "$" and i + 1 < n and src[i + 1] == '"':  # $"template"
            j = i + 2
            while j < n:
                if src[j] == "\\":
                    j += 2
                    continue
                if src[j] == '"':
                    break
                j += 1
            out.append('""')
            i = j + 1
        else:
            out.append(c)
            i += 1
    return "".join(out)


def gml_files(root):
    for dirpath, _, files in os.walk(root):
        for f in files:
            if f.endswith(".gml"):
                yield os.path.join(dirpath, f)


def build_corpus(dirs):
    """words: every identifier appearing anywhere in the corpus.
    fn_defs: names DEFINED as top-level `function name` in the corpus —
    a mod defining one of these is an export collision (whole mod skipped)."""
    words, fn_defs = set(), set()
    for root in dirs:
        for path in gml_files(root):
            with open(path, encoding="utf-8", errors="replace") as fh:
                src = strip_comments_strings(fh.read())
            words.update(WORD.findall(src))
            for m in re.finditer(r"^\s*function\s+([A-Za-z_][A-Za-z0-9_]*)", src, re.M):
                fn_defs.add(m.group(1))
    return words, fn_defs


def analyze_mod(mod_dir):
    calls, globals_used, defined, locals_seen = {}, {}, set(), set()
    for path in gml_files(mod_dir):
        with open(path, encoding="utf-8", errors="replace") as fh:
            src = strip_comments_strings(fh.read())
        rel = os.path.relpath(path, mod_dir)
        for m in re.finditer(r"\bfunction\s+([A-Za-z_][A-Za-z0-9_]*)", src):
            defined.add(m.group(1))
        for m in re.finditer(r"\bvar\s+([A-Za-z_][A-Za-z0-9_]*(?:\s*,\s*[A-Za-z_][A-Za-z0-9_]*)*)", src):
            for name in re.split(r"\s*,\s*", m.group(1)):
                locals_seen.add(name)
        for lineno, line in enumerate(src.splitlines(), 1):
            for m in CALL.finditer(line):
                calls.setdefault(m.group(1), []).append(f"{rel}:{lineno}")
            for m in GLOBALREF.finditer(line):
                globals_used.setdefault(m.group(1), []).append(f"{rel}:{lineno}")
    return calls, globals_used, defined, locals_seen


def main():
    if len(sys.argv) < 2:
        print(__doc__.strip())
        sys.exit(2)

    mod_dir = sys.argv[1]
    roots = sys.argv[2:]
    if not roots:
        roots = [r for r in os.environ.get("FOM_CORPUS", "").split(os.pathsep) if r]
    if not roots:
        print("No corpus root given. Pass one on the command line or set FOM_CORPUS.\n")
        print(__doc__.strip())
        sys.exit(2)

    dirs = corpus_dirs(roots)
    missing = [d for d in dirs if not os.path.isdir(d)]
    if missing:
        for d in missing:
            print("corpus dir does not exist: %s" % d)
        sys.exit(2)

    corpus, corpus_fn_defs = build_corpus(dirs)
    calls, globals_used, defined, locals_seen = analyze_mod(mod_dir)

    unknown = []
    for name, sites in sorted(calls.items()):
        if name in KEYWORDS or name in defined or name in locals_seen:
            continue
        if name not in corpus:
            unknown.append((name, "call", sites[:3]))
    for name, sites in sorted(globals_used.items()):
        # our own state struct globals are mod-defined by convention (__ prefix)
        if name.startswith("__"):
            continue
        if name not in corpus:
            unknown.append((f"global.{name}", "global", sites[:3]))

    # Export collisions: we define a top-level function the engine/MMAPI also
    # defines (whole-mod skip), or whose name appears in the corpus at all
    # (possible host builtin — shadowing bricks the boot and NO other tool
    # detects it, momi/tools/checker/CHECKER.md:39-40).
    collisions, shadows = [], []
    for name in sorted(defined):
        if name in corpus_fn_defs:
            collisions.append(name)
        elif name in corpus:
            shadows.append(name)

    print(f"corpus words: {len(corpus)}   corpus fn defs: {len(corpus_fn_defs)}   "
          f"mod calls: {len(calls)}   mod-defined fns: {len(defined)}")
    failed = False
    if unknown:
        failed = True
        print(f"\nUNKNOWN SYMBOLS ({len(unknown)}) — not defined in mod, absent from game+MMAPI corpus:")
        for name, kind, sites in unknown:
            print(f"  {name:40s} [{kind}]  e.g. {', '.join(sites)}")
    if collisions:
        failed = True
        print(f"\nEXPORT COLLISIONS ({len(collisions)}) — mod defines a function the corpus also defines"
              " (SkipPass will drop the whole mod):")
        for name in collisions:
            print(f"  {name}")
    if shadows:
        failed = True
        print(f"\nPOSSIBLE BUILTIN SHADOWING ({len(shadows)}) — mod defines a name that appears in the"
              " corpus (if it is a host builtin, the game bricks at boot; rename it):")
        for name in shadows:
            print(f"  {name}")
    if failed:
        sys.exit(1)
    print("OK: every referenced symbol exists; no export collisions; no shadowing candidates.")


if __name__ == "__main__":
    main()

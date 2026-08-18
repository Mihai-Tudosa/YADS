#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""regen_gate.py -- prove `make_art.py` is still byte-identical.

`CLAUDE.md` states "a clean run is byte-identical" and, until this file
existed, nothing enforced it (art recon H13).  The contract matters most
exactly when it is hardest to eyeball: a refactor that moves constants and
helpers into `crates/_kit.py` for the Beta 1.3 chest twins must not shift a
single byte of the three shipped units' art.

WHAT IT DOES

  1. snapshots `art_preview.png` (make_art writes the contact sheet next to
     itself, not into the mod tree, so a gate run would otherwise clobber the
     committed copy);
  2. runs `python make_art.py <tempdir>` from the repo root, so the generator
     writes a complete fresh art tree somewhere harmless;
  3. restores the snapshot and reports separately whether the regenerated
     preview differed (informational -- the sheet legitimately changes when a
     family is added, the mod tree must not);
  4. byte-compares every produced file against the committed `yads/` tree and
     every committed file in the produced subtrees against the regeneration,
     so an EXTRA file and a DROPPED file are both differences, not silence;
  5. reports per-subtree identical / differing / missing / extra counts and
     exits non-zero on any difference.

WHICH SUBTREES ARE "OWNED".  Not a hand-kept list: the owned set is derived
from the run itself as the set of directories the generator actually wrote
into.  make_art creates nine directories and writes at least one file into
every one of them, so that derivation is exact and cannot go stale when the
generator grows a new output directory.

EXIT CODES
  0  clean -- every produced file byte-identical, no extras, no drops
  1  differences found, or make_art reported AUDIT PROBLEMS
  2  make_art.py failed to run (non-zero exit / crash)

Run:  python tools/regen_gate.py [--keep] [--quiet]
"""

import hashlib
import os
import shutil
import subprocess
import sys
import tempfile

HERE = os.path.dirname(os.path.abspath(__file__)).replace("\\", "/")
REPO = os.path.dirname(HERE)
MAKE_ART = REPO + "/make_art.py"
COMMITTED = REPO + "/yads"
PREVIEW = REPO + "/art_preview.png"


def sha(path):
    h = hashlib.sha256()
    with open(path, "rb") as fh:
        for chunk in iter(lambda: fh.read(65536), b""):
            h.update(chunk)
    return h.hexdigest()


def walk_rel(root):
    """Every file under `root`, as forward-slash paths relative to it."""
    out = []
    for dirpath, _dirnames, filenames in os.walk(root):
        for fn in filenames:
            full = os.path.join(dirpath, fn)
            rel = os.path.relpath(full, root).replace("\\", "/")
            out.append(rel)
    return sorted(out)


def run_generator(dest, quiet):
    """Run make_art.py into `dest`.  Returns (returncode, stdout)."""
    env = dict(os.environ)
    # Keep the run hermetic and quiet: no stray __pycache__ in the repo, and a
    # fixed hash seed so nothing that ever iterates a set can drift.
    env["PYTHONDONTWRITEBYTECODE"] = "1"
    env["PYTHONHASHSEED"] = "0"
    env.pop("FOM_MOD_DIR", None)      # argv[1] wins anyway; drop the ambiguity
    proc = subprocess.run([sys.executable, MAKE_ART, dest],
                          cwd=REPO, env=env,
                          stdout=subprocess.PIPE, stderr=subprocess.STDOUT)
    out = proc.stdout.decode("utf-8", "replace")
    if proc.returncode != 0 and not quiet:
        sys.stdout.write(out)
    return proc.returncode, out


def compare(produced_root, quiet):
    """Byte-compare the produced tree against the committed one.

    Returns (subtree_report, diffs) where subtree_report is a list of
    (subtree, identical, differing, missing, extra)."""
    produced = walk_rel(produced_root)
    owned = sorted({os.path.dirname(p) for p in produced})

    # Files the committed tree holds inside the owned subtrees.  Anything here
    # that the regeneration did not produce is a DROPPED file.
    committed_in_owned = []
    for sub in owned:
        d = os.path.join(COMMITTED, sub.replace("/", os.sep))
        if not os.path.isdir(d):
            continue
        for fn in sorted(os.listdir(d)):
            if os.path.isfile(os.path.join(d, fn)):
                committed_in_owned.append(sub + "/" + fn)

    prod_set = set(produced)
    comm_set = set(committed_in_owned)

    diffs = []
    per = {sub: [0, 0, 0, 0] for sub in owned}     # ident, differ, missing, extra

    for rel in produced:
        sub = os.path.dirname(rel)
        a = os.path.join(produced_root, rel.replace("/", os.sep))
        b = os.path.join(COMMITTED, rel.replace("/", os.sep))
        if not os.path.isfile(b):
            per[sub][3] += 1
            diffs.append(("EXTRA   ", rel,
                          "%d bytes, not in the committed tree"
                          % os.path.getsize(a)))
            continue
        ha, hb = sha(a), sha(b)
        if ha == hb:
            per[sub][0] += 1
        else:
            per[sub][1] += 1
            diffs.append(("DIFFERS ", rel,
                          "regen %d bytes %s / committed %d bytes %s"
                          % (os.path.getsize(a), ha[:12],
                             os.path.getsize(b), hb[:12])))

    for rel in sorted(comm_set - prod_set):
        sub = os.path.dirname(rel)
        per.setdefault(sub, [0, 0, 0, 0])[2] += 1
        diffs.append(("MISSING ", rel, "committed but NOT regenerated"))

    report = [(sub, per[sub][0], per[sub][1], per[sub][2], per[sub][3])
              for sub in sorted(per)]
    return report, diffs


def main(argv):
    keep = "--keep" in argv
    quiet = "--quiet" in argv

    if not os.path.isfile(MAKE_ART):
        print("regen_gate: no make_art.py at %s" % MAKE_ART)
        return 2
    if not os.path.isdir(COMMITTED):
        print("regen_gate: no committed tree at %s" % COMMITTED)
        return 2

    preview_before = None
    if os.path.isfile(PREVIEW):
        with open(PREVIEW, "rb") as fh:
            preview_before = fh.read()

    tmp = tempfile.mkdtemp(prefix="yads_regen_")
    dest = tmp + "/yads"
    try:
        rc, out = run_generator(dest, quiet)
        if rc != 0 and not os.path.isdir(dest):
            print("regen_gate: make_art.py exited %d and wrote nothing "
                  "-- CANNOT GATE" % rc)
            return 2
        # A non-zero exit with a tree present means make_art's own audit
        # failed.  Do NOT bail: the byte comparison is still the more useful
        # answer, and the audit lines are reported below either way.

        audit_lines = []
        keep_lines = False
        for line in out.splitlines():
            if line.startswith("AUDIT PROBLEMS"):
                keep_lines = True
            elif keep_lines and line.startswith("  "):
                audit_lines.append(line.strip())
            elif keep_lines:
                keep_lines = False

        preview_changed = None
        if preview_before is not None:
            with open(PREVIEW, "rb") as fh:
                preview_changed = (fh.read() != preview_before)
            with open(PREVIEW, "wb") as fh:      # restore, always
                fh.write(preview_before)

        report, diffs = compare(dest, quiet)

        total = [0, 0, 0, 0]
        print("")
        print("REGEN GATE -- make_art.py byte identity")
        print("committed tree : %s" % COMMITTED)
        print("regenerated to : %s" % dest)
        print("")
        print("%-62s %5s %5s %5s %5s" % ("SUBTREE (owned by make_art.py)",
                                         "SAME", "DIFF", "MISS", "XTRA"))
        print("-" * 86)
        for sub, i, d, m, x in report:
            for n, v in enumerate((i, d, m, x)):
                total[n] += v
            print("%-62s %5d %5d %5d %5d" % (sub, i, d, m, x))
        print("-" * 86)
        print("%-62s %5d %5d %5d %5d" % ("TOTAL", *total))
        print("")

        if diffs:
            print("DIFFERENCES (%d):" % len(diffs))
            for kind, rel, note in diffs:
                print("  %s %s" % (kind, rel))
                print("           %s" % note)
            print("")

        if preview_changed is not None:
            print("art_preview.png: %s (informational -- the contact sheet is "
                  "not part of the mod tree; committed copy restored)"
                  % ("CHANGED by this run" if preview_changed
                     else "identical"))

        if audit_lines:
            print("")
            print("make_art.py AUDIT PROBLEMS (%d) -- a clean regen has none:"
                  % len(audit_lines))
            for line in audit_lines:
                print("  " + line)

        print("")
        if diffs or audit_lines:
            print("RESULT: FAIL -- %d difference(s), %d audit problem(s)"
                  % (len(diffs), len(audit_lines)))
            return 1
        print("RESULT: PASS -- %d files byte-identical, 0 differing, "
              "0 missing, 0 extra" % total[0])
        return 0
    finally:
        if keep:
            print("(kept: %s)" % tmp)
        else:
            shutil.rmtree(tmp, ignore_errors=True)


if __name__ == "__main__":
    sys.exit(main(sys.argv[1:]))

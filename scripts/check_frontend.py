#!/usr/bin/env python3
"""Comprobaciones rápidas de frontend/index.html sin abrir un navegador:
sintaxis del <script> inline (via `node --check`), ids duplicados, y
balance de <div>/</div>. No sustituye a probarlo en el navegador, pero
detecta los errores más tontos antes de cada commit.

Uso:
    ./scripts/check_frontend.py
"""
import re
import subprocess
import sys
import tempfile
from pathlib import Path

FRONTEND_HTML = Path(__file__).resolve().parent.parent / "frontend" / "index.html"


def check_js_syntax(html):
    match = re.search(r"<script>(.*)</script>", html, re.S)
    if not match:
        print("  No encuentro un <script> inline que comprobar.", file=sys.stderr)
        return False
    with tempfile.NamedTemporaryFile("w", suffix=".js", delete=False) as f:
        f.write(match.group(1))
        path = f.name
    result = subprocess.run(["node", "--check", path], capture_output=True, text=True)
    if result.returncode != 0:
        print(result.stderr, file=sys.stderr)
        return False
    return True


def check_duplicate_ids(html):
    ids = re.findall(r'id="([^"]+)"', html)
    dupes = sorted({i for i in ids if ids.count(i) > 1})
    if dupes:
        print(f"  ids duplicados: {dupes}", file=sys.stderr)
        return False
    return True


def check_div_balance(html):
    opened = len(re.findall(r"<div[ >]", html))
    closed = len(re.findall(r"</div>", html))
    if opened != closed:
        print(f"  <div> abiertos: {opened}, </div> cerrados: {closed}", file=sys.stderr)
        return False
    return True


def main():
    html = FRONTEND_HTML.read_text(encoding="utf-8")
    checks = [
        ("Sintaxis JS", check_js_syntax),
        ("ids duplicados", check_duplicate_ids),
        ("Balance de <div>", check_div_balance),
    ]
    ok = True
    for name, check in checks:
        if check(html):
            print(f"OK - {name}")
        else:
            print(f"FALLO - {name}", file=sys.stderr)
            ok = False
    sys.exit(0 if ok else 1)


if __name__ == "__main__":
    main()

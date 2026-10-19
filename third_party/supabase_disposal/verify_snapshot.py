"""Read-only SDK snapshot audit. Use --upstream to recheck published archives."""

import hashlib
import io
import json
from pathlib import Path
import subprocess
import sys
import tarfile


def digest(content):
    return hashlib.sha256(content).hexdigest()


def download(url):
    # Use the platform's TLS trust store; never disable certificate checks.
    return subprocess.check_output(["curl", "--fail", "--silent", "--show-error", url])


root = Path(__file__).resolve().parent
manifest = json.loads((root / "PROVENANCE.json").read_text(encoding="utf-8"))
assert digest((root / "PATCH.diff").read_bytes()) == manifest["patch_sha256"]
changed = []
for package in manifest["packages"]:
    name = package["name"]
    folder = root / name
    originals = package["upstream_sha256"]
    patched = package["patched_sha256"]
    expected = dict(originals, **patched)
    runtime_files = {
        p.relative_to(folder).as_posix()
        for p in (folder / "lib").rglob("*")
        if p.is_file()
    } | {"pubspec.yaml", "LICENSE"}
    assert runtime_files == set(originals), f"Unexpected runtime footprint: {name}"
    for path, sha in expected.items():
        assert digest((folder / path).read_bytes()) == sha, f"Changed: {name}/{path}"
    for path in patched:
        assert patched[path] != originals[path], f"Empty patch: {name}/{path}"
        changed.append(f"{name}/{path}")
    if "--upstream" in sys.argv:
        archive_bytes = download(package["archive_url"])
        assert digest(archive_bytes) == package["archive_sha256"]
        archive = tarfile.open(fileobj=io.BytesIO(archive_bytes), mode="r:gz")
        for path, sha in originals.items():
            assert digest(archive.extractfile(path).read()) == sha
    print(f"{name} {package['version']}: {len(originals)} verified runtime/license/manifest files")

for path, sha in manifest["test_helpers_sha256"].items():
    assert digest((root.parents[1] / path).read_bytes()) == sha, f"Changed helper: {path}"
assert set(changed) == {
    "supabase/lib/src/supabase_client.dart",
    "supabase_flutter/lib/src/supabase.dart",
}, "Patch exceeded the two reviewed SDK implementation files"
print("Only two upstream files patched; three local test helpers verified.")

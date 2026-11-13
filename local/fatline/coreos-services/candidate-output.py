#!/usr/bin/env python3
"""Write immutable, content-addressed, non-secret qualification candidates."""
import hashlib
import json
import os
from pathlib import Path
import tempfile


def retain_candidate(directory: Path, candidate: dict, prefix: str) -> Path:
    payload = (json.dumps(candidate, sort_keys=True, indent=2) + "\n").encode()
    digest = hashlib.sha256(payload).hexdigest()
    directory.mkdir(parents=True, exist_ok=True)
    output = directory / f"{prefix}-{digest}.json"
    if output.exists():
        if output.is_symlink() or output.read_bytes() != payload:
            raise ValueError("Existing qualification candidate differs from content-addressed identity")
        return output
    fd, name = tempfile.mkstemp(prefix=f".{prefix}-", suffix=".tmp", dir=directory)
    try:
        with os.fdopen(fd, "wb") as stream:
            stream.write(payload)
            stream.flush()
            os.fsync(stream.fileno())
        os.chmod(name, 0o600)
        # Exclusive creation: do not replace a candidate produced by a parallel run.
        try:
            os.link(name, output)
        except FileExistsError:
            if output.is_symlink() or output.read_bytes() != payload:
                raise ValueError("Concurrent qualification candidate identity collision")
    finally:
        if os.path.exists(name):
            os.unlink(name)
    return output

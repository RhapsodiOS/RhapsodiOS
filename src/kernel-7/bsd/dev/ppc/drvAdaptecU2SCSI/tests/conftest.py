"""Inputs that live outside git.

The frozen case/contract JSON fixtures were removed from git history for size.
Set AU2_FIXTURES to a directory that holds them, either directly or in a
checkout-shaped tree (src/kernel-7/.../tests/...); they are hard-linked into
this directory for the session and removed afterwards. Tests whose fixtures or
generated evidence (tools/binrecon/out, never committed) are absent skip with
the missing path as the reason.
"""

import os
import shutil
import subprocess
from pathlib import Path

import pytest

TESTS = Path(__file__).resolve().parent
REPO = TESTS.parents[6]
OUT = REPO / "tools/binrecon/out"
STRIPPED = [
    "contracts.json", "layout-contracts.json", "reference-cases.json",
    "task5-cases.json", "task6-cases.json", "task7-cases.json", "task8-cases.json",
    "task9-cases.json", "task9-ack-cases.json", "task10-cases.json", "task10-sequences.json",
    "task11-cases.json", "task11-contracts.json", "task11-sequences.json",
    "task12-cases.json", "task12-context-cases.json", "task12-contracts.json",
    "task12-build-provenance/batch4-inputs.json",
    "task13-cases.json", "task13-context-cases.json", "task13-contracts.json",
    "task13-stack-cases.json", "task13-stack-mapping.json", "task13-getter.json",
    "task13-fix1-cases.json", "task13-fix1-contracts.json", "task13-fix1-alias.json",
    "task13-provenance/b9-inputs.json", "task13-provenance/b10-inputs.json",
]
_linked = []


def _fixture_root():
    root = os.environ.get("AU2_FIXTURES")
    if not root:
        return None
    nested = Path(root) / TESTS.relative_to(REPO)
    return nested if nested.is_dir() else Path(root)


def pytest_configure(config):
    root = _fixture_root()
    if root is None:
        return
    for name in STRIPPED:
        source, target = root / name, TESTS / name
        if source.is_file() and not target.exists():
            try:
                os.link(source, target)
            except OSError:
                shutil.copyfile(source, target)
            _linked.append(target)


def pytest_unconfigure(config):
    while _linked:
        _linked.pop().unlink(missing_ok=True)


def _absent_input(error):
    while error is not None:
        if isinstance(error, FileNotFoundError) and error.filename:
            path = Path(error.filename).resolve()
            if path.is_relative_to(TESTS) and path.relative_to(TESTS).as_posix() in STRIPPED:
                return f"frozen fixture {path.name} is not in git; set AU2_FIXTURES"
            if path.is_relative_to(OUT):
                return f"generated evidence {path.relative_to(REPO).as_posix()} is absent"
        if (isinstance(error, subprocess.CalledProcessError) and error.cmd[:2] == ["git", "show"] and
                any(error.cmd[2].endswith("/tests/" + name) for name in STRIPPED)):
            return f"frozen fixture {error.cmd[2]} was removed from git history"
        error = error.__cause__ or error.__context__
    return None


def _skip_absent():
    try:
        result = yield
        return result
    except (OSError, ValueError, subprocess.CalledProcessError) as error:
        reason = _absent_input(error)
        if reason:
            pytest.skip(reason)
        raise


@pytest.hookimpl(wrapper=True)
def pytest_runtest_setup(item):
    return (yield from _skip_absent())


@pytest.hookimpl(wrapper=True)
def pytest_runtest_call(item):
    return (yield from _skip_absent())

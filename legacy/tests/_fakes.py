"""Shared fake agents and queue helpers for threaded gameplay tests."""

from __future__ import annotations

import queue
import threading
import time


class FakeRun:
    def __init__(self, output):
        self.output = output


class FakeAgent:
    """Minimal stand-in for ``pydantic_ai.Agent`` (must expose ``model`` for debug logs)."""

    model = "stub-model"

    def __init__(self, outputs: list):
        self._outputs = list(outputs)

    def run_sync(self, *_args, **_kwargs):
        if not self._outputs:
            raise RuntimeError("fake agent ran out of scripted outputs")
        return FakeRun(self._outputs.pop(0))


def collect_until(q: queue.Queue, predicate, timeout: float = 5.0):
    deadline = time.monotonic() + timeout
    found = []
    while time.monotonic() < deadline:
        try:
            msg = q.get(timeout=0.1)
        except queue.Empty:
            continue
        found.append(msg)
        if predicate(msg):
            return found
    raise AssertionError(f"timeout waiting for message; got {found!r}")


def join_thread_or_stop(thr: threading.Thread, stop_event: threading.Event, *, join_timeout: float = 5.0) -> None:
    """Wait for a daemon gameplay thread to finish; avoid leaving zombies if the loop stalls."""
    thr.join(timeout=join_timeout)
    if thr.is_alive():
        stop_event.set()
        thr.join(timeout=2.0)
    assert not thr.is_alive(), "background thread still alive after join/stop"

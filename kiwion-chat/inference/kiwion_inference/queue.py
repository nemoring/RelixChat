"""FIFO admission queue with bounded waiting list.

`parallel` requests run at the same time (= llama.cpp slots). Up to `max_queue`
requests wait in FIFO order; anything beyond that is rejected immediately with
`Overloaded`, which the backend turns into the "tired kiwi" message.
"""
from __future__ import annotations

import asyncio
import itertools
import time
from collections import deque
from contextlib import asynccontextmanager


class Overloaded(Exception):
    pass


class QueueTimeout(Exception):
    pass


class AdmissionQueue:
    def __init__(self, parallel: int, max_queue: int, timeout: float):
        self.parallel = parallel
        self.max_queue = max_queue
        self.timeout = timeout
        self.active = 0
        self._waiting: deque[int] = deque()
        self._cond = asyncio.Condition()
        self._ids = itertools.count(1)
        self.total_rejected = 0
        self.total_served = 0
        self.total_wait_seconds = 0.0

    @property
    def waiting(self) -> int:
        return len(self._waiting)

    def can_admit(self) -> bool:
        return self.active < self.parallel or len(self._waiting) < self.max_queue

    def reserve(self) -> int:
        """Synchronously reserve a place (raises Overloaded). Returns a ticket id."""
        if not self.can_admit():
            self.total_rejected += 1
            raise Overloaded()
        ticket = next(self._ids)
        self._waiting.append(ticket)
        return ticket

    def position(self, ticket: int) -> int:
        try:
            return self._waiting.index(ticket) + 1
        except ValueError:
            return 0

    async def acquire(self, ticket: int, on_position=None) -> None:
        start = time.monotonic()
        deadline = start + self.timeout
        last_pos = None
        async with self._cond:
            try:
                while not (self.active < self.parallel and self._waiting and self._waiting[0] == ticket):
                    pos = self.position(ticket)
                    if on_position and pos != last_pos:
                        last_pos = pos
                        await on_position(pos)
                    remaining = deadline - time.monotonic()
                    if remaining <= 0:
                        raise QueueTimeout()
                    try:
                        await asyncio.wait_for(self._cond.wait(), timeout=min(remaining, 1.0))
                    except asyncio.TimeoutError:
                        pass
                self._waiting.popleft()
                self.active += 1
                self.total_wait_seconds += time.monotonic() - start
            except BaseException:
                if ticket in self._waiting:
                    self._waiting.remove(ticket)
                self._cond.notify_all()
                raise

    async def release(self) -> None:
        async with self._cond:
            self.active -= 1
            self.total_served += 1
            self._cond.notify_all()

    async def cancel(self, ticket: int) -> None:
        async with self._cond:
            if ticket in self._waiting:
                self._waiting.remove(ticket)
            self._cond.notify_all()

    @asynccontextmanager
    async def slot(self, ticket: int, on_position=None):
        await self.acquire(ticket, on_position)
        try:
            yield
        finally:
            await self.release()

    def stats(self) -> dict:
        return {
            "parallel": self.parallel,
            "active": self.active,
            "waiting": self.waiting,
            "max_queue": self.max_queue,
            "total_served": self.total_served,
            "total_rejected": self.total_rejected,
            "avg_wait_seconds": round(self.total_wait_seconds / self.total_served, 3) if self.total_served else 0.0,
        }

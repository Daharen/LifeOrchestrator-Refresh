#!/usr/bin/env python
"""Sample python worker (fixture)."""
import os
import json
from .helper import thing


def run(x):
    """Run the sample."""
    return x * 2


class Engine:
    def __init__(self, k):
        self.k = k

    def step(self, n):
        return self.k + n

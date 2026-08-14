#!/usr/bin/env python3
"""Fixture stand-in for ops/audit/doc-commit-gate.py (the fail-closed core-doc commit gate)."""
def refuse(violations):
    return bool(violations)

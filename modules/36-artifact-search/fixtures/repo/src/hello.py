#!/usr/bin/env python
"""A tiny source fixture. Exercises text chunking of code and symbol/exact search."""


def zorble_main():
    widget = build_widget()
    return frobnicate(widget)


def build_widget():
    # ZorbleWidget factory
    return {"ready": True, "flux": 21}


def frobnicate(widget):
    if not widget["ready"]:
        raise RuntimeError("E_FROBNICATE_FAILED")
    return widget["flux"] * 2


if __name__ == "__main__":
    print(zorble_main())

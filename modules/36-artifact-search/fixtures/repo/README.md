# Zorble Project

Zorble is a fixture project used by the artifact.search test harness. It exists only to exercise
Markdown-aware chunking, full-text retrieval, exact/literal retrieval, and provenance.

## Overview

The `ZorbleWidget` is the central component. It coordinates the frobnicator and the flux capacitor.
When it fails it raises the error string `E_FROBNICATE_FAILED`, which downstream tooling greps for.

## Architecture

The system has three layers: ingestion, indexing, and retrieval. Each layer is independently
testable. Decision `D-9999` records why the retrieval layer is deterministic.

### Retrieval layer

Retrieval is hybrid: a lexical index for exact strings and symbols, and a semantic index for
conceptually similar passages. The unique marker token `QUOKKA_MARKER_7` appears exactly once in
this repository, in this section, so an exact search must return this chunk and only this chunk.

## Example

```python
def frobnicate(widget):
    # a fenced code block: headings inside it must NOT split the chunk
    # ## Not A Heading
    if not widget.ready:
        raise RuntimeError("E_FROBNICATE_FAILED")
    return widget.flux * 2
```

## Closing

That is the whole of the Zorble overview.

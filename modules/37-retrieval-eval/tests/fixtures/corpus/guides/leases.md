# Resource leases

The resource lease module serializes access to the gpu, the git index, and each document.

## Acquire a lease

Acquire a lease in gpu then git then doc order before the work it guards.

## Release a lease

Release each lease in reverse order once the guarded work is done.

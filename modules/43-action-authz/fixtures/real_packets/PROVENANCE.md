# real_packets/ -- captured REAL #40 context.compile 0.7.0 outputs (integration fixtures)

These four files are authentic `lifeorch.context_packet/0.2` outputs produced by the committed **#40
context.compile 0.7.0** compiler over real #36/#37 retrieval, captured on 2026-08-05 from
`modules/40-context-compiler/runtime/artifacts/*/compile/context_packet.json` (identity.compiler_version =
`0.7.0`). Each carries `non_execution: true` and namespace `core-docs`.

They are committed here so `tests/integration.py` can prove, deterministically and without a live #40 run, that
the reference monitor DENYs every authentic packet at check **A06** while `non_execution` holds (contract s8.7
crit 9). They are read-only inputs; the suite never mutates them.

| file | packet_id | compiler_version | non_execution |
|---|---|---|---|
| m40_070_pkt_0.json | cpkt_1e0c6b40c9916edb42f5d773cf889640 | 0.7.0 | true |
| m40_070_pkt_1.json | cpkt_d9c0550a32b95cadc28060cea76189ea | 0.7.0 | true |
| m40_070_pkt_2.json | cpkt_b081a0c4d2f5851bd6a820a9198cda0b | 0.7.0 | true |
| m40_070_pkt_3.json | cpkt_994f6f30422809b8daf93f846e45e958 | 0.7.0 | true |

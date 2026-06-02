# Spine Routing — design note

> Phase A / Workstream 1 / Relay 4 — Spine URN↔PID routing wired onto the ra-backed `spine_ra_machine`. 2026-06-02 / DOE.

## Public API surface (4 functions)

```erlang
-spec spine:register(urn(), pid()) -> ok | {error, Reason :: term()}.
-spec spine:lookup(urn()) -> {ok, pid()} | {error, not_found | term()}.
-spec spine:lookup_urn(pid()) -> {ok, urn()} | {error, not_found | term()}.
-spec spine:deregister(urn()) -> ok | {error, term()}.

-type urn() :: binary().
```

W2 `spine_client` binds against this signature. Any subsequent change requires a coordination broadcast.

## URN type — builder-era binary string

URN is `binary()` per the builder-era convention captured in p11 Meta §1 + R4 §7. Examples: `<<"urn:dio:tenant:vivan-1">>`, `<<"urn:dio:organ:cortex">>`, `<<"urn:dio:test:r4-live">>`.

**Explicitly forward-cached (DO NOT implement at this relay):** the post-Graphheight `uGraph_concept` record-based URN swap. Per R4 §7 + Q1, the swap will replace the type-spec + carry binding-rewrite tooling at swap time. YAGNI applies — no abstraction layers introduced now in anticipation of the future swap.

## State machine wiring

Backing module: `spine_ra_machine` implementing the `ra_machine` behaviour. State shape post-R4:

```erlang
#{forward => #{URN => PID}, reverse => #{PID => URN}}
```

**Bidirectional invariant.** Every `register` operation adds entries to BOTH forward + reverse maps. If a URN is re-bound to a new PID, the prior PID's reverse entry is removed (and vice versa). This guarantees that no stale URN↔PID pair persists across re-registrations.

**Commands (R4 canonical set):**

| Command | Effect |
|---|---|
| `{register, URN, PID}` | Bidirectional add (removes any prior conflicting binding on either axis) |
| `{deregister, URN}` | Remove by URN (both forward + reverse) |
| `{deregister_pid, PID}` | Remove by PID (liveness path) |
| `{lookup, URN}` | Returns `{ok, PID}` or `{error, not_found}` |
| `{lookup_urn, PID}` | Returns `{ok, URN}` or `{error, not_found}` |

Plus R2-era legacy commands `{put, URN, PID}` / `{get, URN}` / `{delete, URN}` mapped to their R4 equivalents for forward log replay compatibility.

## PID liveness handling

**Architecture choice — per-node Spine-side monitor process.** Each substrate-L0 node runs a `spine_pid_monitor` gen_server (registered as `{local, spine_pid_monitor}` on each node). `spine:register/2` calls `spine_pid_monitor:track/1` after the ra command succeeds. The monitor `erlang:monitor/2`s the registered PID. On the `'DOWN'` message, it issues a `{deregister_pid, PID}` ra command via the local ServerId.

**Why per-node + cross-node:** in a 3-node distributed-Erlang substrate, `erlang:monitor/2` works across nodes — a process registered from N1 can be monitored by N1's spine_pid_monitor even if the PID lives on N1, N2, or N3. The DOWN-driven deregister then replicates via ra quorum so all 3 nodes see the cleanup.

**Alternative considered — caller-side monitoring** (the registering process erlang:monitors and issues the deregister): rejected as it puts liveness responsibility on every API caller. The Spine-side monitor centralizes the discipline.

**Liveness latency bound.** From PID death to deregister visible cluster-wide:
1. Erlang VM emits DOWN to monitor (µs–ms over distribution)
2. spine_pid_monitor invokes ra:process_command (sync ra round-trip, ~ms with single-host LAN topology)
3. ra applies the command on all 3 replicas + leader (ms scale)

Empirically observed at §4 step 3: ~800ms after kill, all 3 nodes' lookups return `{error, not_found}` — that's a conservative bound (the 800ms is the sleep my test used; actual replication probably completed well below that).

## W2 `spine_client` contract

The 4-function API above is the surface W2's `spine_client` will bind against. Module signatures + type-specs are the contract.

`spine_client` will likely wrap this API plus add:
- HTTP-shaped clients for cross-host scenarios (Phase B; out of scope here)
- Connection pooling / batching (if needed; not at Phase A)
- Telemetry (`concept_emit` integration per `organ-erlang-lib` MP-E-0 module #13)

Any API surface change requires coordination broadcast through EA + ESB-I + W2 author.

## Empirical verification at close (§4 ratifiable evidence)

| §4 step | Verdict | Anchor |
|---|---|---|
| 1. Round-trip register + lookup across all 3 nodes | ✅ PASS | spawn real PID on N1; register; `spine:lookup/1` returns `{ok, PID}` from N1+N2+N3; `spine:lookup_urn/1` returns `{ok, URN}` from N1+N2+N3 |
| 2. Replication under single-node loss | ✅ PASS | register; stop N3; lookup still works on N1+N2; restart N3 + ra:restart_server; N3 catches up to same binding |
| 3. Liveness auto-deregister | ✅ PASS | register real PID; exit PID via `erlang:exit/2`; ~800ms later all 3 nodes return `{error, not_found}` |
| 4. API surface stability (type-spec) | ✅ PASS | this document is the artifact |

## Coordination broadcast — API stability

This contract is locked at R4 close. Future workstreams binding against it:
- **W2 `organ-erlang-lib` `spine_client`** (EA's MP-E-0 canonical module #2)
- **W3+** per-organ skeletons calling Spine via `spine_client`
- **W5** three-process Vivan pattern (Cache Holder + User Proxy register their PIDs at boot)
- **W6 Codex** content substrate consumers (via spine_client)
- **W9 Vigil CV** scaffolds may register CV-test processes

Changes to the public API surface require explicit coordination via Mailbox to EA + ESB-I + W2 author, with at least a 1-week notice window for downstream consumers.

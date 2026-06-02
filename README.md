# AOS-substrate-l0-erlang — Phase A substrate Layer 0

> Workspace for the Coretex DIO Erlang substrate Layer 0 — the 3-node BEAM cluster hosting Spine `ra` Raft + Mnesia 3-node cluster on M4 Max. Foundation for the 28 organ-nodes + Codex + harness that sit atop.

## Provenance

- **Created:** 2026-06-02 by DOE per ea-m1-r1 (Phase 11 / Workstream 1 / Relay 1)
- **Canonical path ruling:** EA RFI-EA-1 reply 1232 R 2026-06-02 (option a: shape preserved; parent-name updated per Leon framing-correction below)

> *Note 2026-06-02 ~12:39 EDT — canonical path subsequently revised via Leon framing-correction. The DIO is the product being constructed; Coretex is the umbrella front-facing brand over all products (DIO + coretex-agentic-website + CTMSurface + future implants-as-plugins). EA's substantive ruling (option a — accept DOE-proposed path shape) preserved as time-honest per L2-08; parent-name parameter substituted: `AOS-products-dev/AOS-DIO/AOS-DIO-src/AOS-substrate-l0-erlang/`.*
- **Architecture anchors:** D8 EPMD-isolation + D33 Phase A topology + DOE 1935 R WS1 refinement 2

## Structure

```
AOS-substrate-l0-erlang/
├── config/                          # Per-node VM args
│   ├── substrate_l0_1.vm.args
│   ├── substrate_l0_2.vm.args
│   └── substrate_l0_3.vm.args
├── templates/                       # Reference templates (NOT executed here)
│   └── organ-node-no-epmd-baseline.vm.args
├── docs/                            # Operational documentation
└── .gitignore                       # excludes .erlang.cookie + build artifacts
```

## Node configuration

Three substrate-L0 BEAM nodes on M4 Max:

| Node sname | Distribution port | Role |
|---|---|---|
| `substrate_l0_1` | 9101 | Spine `ra` Raft member + Mnesia replica |
| `substrate_l0_2` | 9102 | Spine `ra` Raft member + Mnesia replica |
| `substrate_l0_3` | 9103 | Spine `ra` Raft member + Mnesia replica |

All 3 nodes:
- Run with `ERL_EPMD_ADDRESS=127.0.0.1` (localhost-only EPMD per DOE 1935 R WS1 refinement 2)
- Share `~/.erlang.cookie` file (single graphheight_sys user on M4 Max)
- Set `-kernel prevent_overlapping_partitions true` (canonical Erlang/OTP 25+ kernel flag)

## EPMD-isolation invariant (D8)

The 3 substrate-L0 nodes are the ONLY BEAM nodes registered in EPMD. Organ-nodes (28 organs + Codex + harness; spawned in W3+) run with `-no_epmd` + `-kernel start_distribution false` and NEVER register. The invariant is empirically asserted via Vigil CV (R5 scaffolding) — `epmd -names` MUST show exactly 3 substrate-L0 names + 0 organ-node names.

See `templates/organ-node-no-epmd-baseline.vm.args` for the canonical organ-node flag-set.

## Cookie discipline (per EA RFI-EA-3 refinement)

1. **First substrate-L0 node to boot** generates a 32-char base64-safe opaque random cookie via `openssl rand -base64 24 | tr -d "=+/" | head -c 32` if `~/.erlang.cookie` does not exist or is empty. Persists to `~/.erlang.cookie` mode 400.
2. **Subsequent substrate-L0 nodes** read the existing cookie. Per-node boot script verifies: exists + mode 400 + non-empty. Verification failure aborts boot with `cookie_verification_failure` error (no silent regeneration — would mismatch the cluster).
3. **Pre-flight cluster check:** all 3 nodes `net_adm:ping/1` each other; `pong` required; `pang` aborts (cookie mismatch OR EPMD misconfiguration).
4. **Rotation:** static throughout Phase A; rotate at Phase B activation.

## Launcher

`scr-bash-dio-substrate-l0-boot` (canonical path: `MDvault-DIO-artifacts/100-Scripts/03-Scripts-DIO/04-Scripts-DIO-erlang-substrate/scr-bash-dio-substrate-l0-boot/scr-bash-dio-substrate-l0-boot.sh`; PATH symlink to be installed).

Subcommands: `start <node>` / `stop <node>` / `status <node>` / `start-all` / `stop-all` / `status-all` / `verify-cluster`.

Idempotent: re-running with nodes already up emits `already-up` status + exit 0 (per §6 success criteria 4). Detection via `pgrep -f "beam.smp.*<sname>"` primary + `epmd -names` cross-check secondary (per L-EPMD-ghost lesson candidate; EPMD entries can persist as ghosts without live VMs).

## Verification status

| §4 step | Status | Notes |
|---|---|---|
| 1. All 3 nodes boot + inter-pingable | **PENDING** | requires Erlang/OTP install on M4 Max (CEO 0920 HALT note) |
| 2. EPMD-isolation pre-check (3 substrate-L0 / 0 organ) | **PENDING** | same |
| 3. Organ-node `-no_epmd` smoke test (throwaway) | **PENDING** | same |
| 4. Idempotency re-run | **PENDING** | same |

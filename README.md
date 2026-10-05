# sdlc-speckit-SRE

Field experiment: spec-driven development with [Spec Kit](https://github.com/github/spec-kit)
extended to "run it". The cycle does not stop at writing the feature but covers operability,
SLOs, deployment on Kubernetes, verification and postmortems. The underlying question: **at what
point in an application's design does the SRE come in**, when the code is an artifact derived from
the spec.

## The test bed

- **App**: a URL shortener in Go, written entirely with Spec Kit.
- **Infra**: the `dev` environment is a local kind cluster on the developer's machine;
  `test` and `prod` may be GKE clusters.
  The platform stays portable to GKE at any time (see
  [`platform/README.md`](platform/README.md)). The capacity
  reproduces the real infrastructure specified by the customer and is a **hard limit**: it is
  the application that adapts to the platform, not the other way around.
- **Roles**: Dev and SRE are the same person, but remain distinct roles; every principle and every
  artifact has a single owner (see the constitution).

## The platform

A single-node kind cluster, created with `platform/kind/up.ps1` and destroyed with
`platform/kind/down.ps1`. The ceiling is enforced in two places: `docker update` on the node
container (the real limit) and the kubelet's `systemReserved` (so the scheduler sees the same
capacity).

| Item (measured on 2026-10-05) | CPU | Memory |
|---|---|---|
| Node ceiling | 2 | 4 GiB |
| Allocatable | 1750m | ~3.3 GiB |
| Kubernetes system pods (requests) | 950m | 290 MiB |
| **Available for observability and application (requests)** | **800m** | **~3.0 GiB** |

The scarce resource is CPU: the system pods already reserve 54% of it. This envelope lives in the
constitution and is the SRE's first input to the design: every plan must declare the share it uses.

## Work order and SRE entry points

| # | Spec Kit step | Who | What the SRE does |
|---|---|---|---|
| 0 | `/speckit-constitution` | SRE + Dev | **First entry point.** Writes the operability principles (III-VIII) once: SLOs, bounded resources, observability, provenance, safe delivery, postmortems. Every feature inherits them. |
| 1 | `/speckit-specify` | Dev | Read-only. Checks that the `SC-xxx` Success Criteria are observable. |
| 2 | `/speckit-clarify` | Dev | If the feature is at risk, asks the operational questions: expected load, availability, data retention. |
| 3 | `/speckit-plan` | Dev | **Main SRE gate, the design moment.** `OC-xxx` constraints, SLOs, memory and CPU budget, probes, rollout and rollback. |
| 4 | `/speckit-tasks` | Dev | Checks that the operability tasks exist (metrics, manifests, runbook). |
| 5 | `/speckit-analyze` | Dev | Consistency across artifacts, including principles III-VII. |
| 6 | `/speckit-implement` | Dev | No role. |
| 7 | `/speckit-converge` | Dev | No role. |
| 8 | Production readiness, deploy on kind | SRE | **Gate before deploy.** |
| 9 | Run: observed SLOs, incidents | SRE | Postmortem: decides where the constraint should have been written and carries the fix upstream (step 0, 1 or 3). |

The gate at step 3 triggers only for features above the risk threshold: new service, new
datastore, load-sensitive path. The first URL shortener feature clears it, because it is a new
service.

Method: start from Spec Kit's **standard templates**, with only the constitution enriched, to see
where plain Spec Kit does not cover "run it". The preset and the `run` extension are designed
later, on the observed gaps.

## Status

- [x] Spec Kit initialized (Claude Code, Python scripts, `git` extension)
- [x] kind cluster with a 2 CPU / 4 GiB ceiling, envelope measured
- [x] Constitution v1.1.1: Platform Envelope, environments and portability
- [x] First feature 001: spec written (`/speckit-specify`)
- [x] Platform decision P-001 (exposure, mesh, observability, portability), accepted in [`platform/README.md`](platform/README.md)
- [ ] Feature 001: clarify, plan with SRE gate, tasks, analyze, implement
- [ ] First deploy on kind
- [ ] `sre` preset and `run` extension, designed on the observed gaps

## Structure

- [`.specify/memory/constitution.md`](.specify/memory/constitution.md): the project's principles,
  each with its owner (Dev or SRE).
- [`sre-spec-driven.md`](sre-spec-driven.md): starting notes on the SRE's role in spec-driven
  development.
- [`platform/`](platform/README.md): platform decisions and kind cluster (SRE owner).
- `.specify/`: Spec Kit configuration (templates, scripts, workflow, `git` extension).
- `.claude/skills/`: the `/speckit-*` commands for Claude Code.
- `specs/NNN-slug/`: one folder per feature (spec, plan, tasks), created by `/speckit-specify`.

## Prerequisites

- Go (latest stable), Docker, kind, kubectl
- [Spec Kit CLI](https://github.com/github/spec-kit): `uv tool install specify-cli`
- Claude Code, for the `/speckit-*` commands

## Branching

Spec Kit's own: one `NNN-slug` branch per feature, created by `/speckit-specify` through the
`git` extension, then merged into `main` with a pull request.

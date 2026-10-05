# SRE and spec-driven development

Brainstorming of October 5, 2026. Context: development is done with
[Spec Kit](https://github.com/github/spec-kit) and the code is an artifact derived from the spec.
Question: what is the SRE's role, and how do we reconcile what happens at runtime on Kubernetes
with the spec.

## The starting point

> **Recovery ≠ Remediation ≠ Root Cause Resolution**

Restart, scaling and rollback stabilize a service without resolving the cause. If the code is
derived from the spec, fixing it by hand after an incident amounts to modifying generated code:
at the next regeneration the defect comes back. The fix must go back up to the spec, the plan, the
tests or the constitution.

## Spec Kit, what it already offers

- Workflow: constitution → specify → clarify → plan → tasks → analyze → implement (→ converge).
- Per feature: branch `###-feature-name`, with `spec.md`, `plan.md`, `tasks.md`.
- `spec.md`: Functional Requirements `FR-001`, Success Criteria `SC-001`, measurable and
  technology-agnostic.
- `plan.md`, Technical Context: **Performance Goals**, **Constraints**, **Scale/Scope**. Free
  text, no IDs.
- "Constitution Check" gate in the plan.
- No traceability toward commits, deploys or runtime.

## The bridge between spec and runtime

- Every observable `SC-xxx` becomes an **SLO** labeled with the feature branch and the criterion
  ID. A violation on Kubernetes already carries the reference to the spec.
- Technical constraints (memory, latency) live in `plan.md` without IDs: this is the uncovered
  spot. The memory leak / `OOMKilled` case falls there.
- Provenance from the pod to the feature with standard metadata: OCI annotations
  (`org.opencontainers.image.revision`), SLSA attestation, OpenTelemetry attributes, Spec Kit
  branch.

## Where the SRE enters the flow

| Phase | The SRE's role |
|---|---|
| `constitution` | operability principles written once: every feature declares SLI/SLO, resource budgets, degraded behavior, minimum observability, no unbounded caches. Maximum leverage. |
| `specify` / `clarify` | makes the `SC-xxx` observable: threshold, window, SLI |
| `plan` | owner of Performance Goals, Constraints, Scale/Scope. The production readiness review moves here. |
| `analyze` | operational coverage: every SC has an SLO, every constraint has a test |
| post-deploy | incident command; postmortem with actions on spec, constitution or tests, not tickets on the code |

## Who does what: workflow by levels

The workflow is organized on Spec Kit's levels, not on people. Each level has a single owner;
whether dev and SRE coincide depends on the size of the team.

| Level | Artifact | Writes | Intervenes |
|---|---|---|---|
| project | `constitution` | SRE | dev approves |
| feature | `spec.md`, `plan.md` | dev | SRE only on observable `SC-xxx` and Constraints, and only for at-risk features |
| platform | SLO policy, error budget, manifests (limits, HPA) | SRE | values derived from the plan's Constraints |
| contract | error budget policy | dev and SRE together | the only artifact written jointly |
| post-incident | postmortem | SRE leads | the outcome lands at the right level |

In sequence:

1. **Once**: the SRE writes the operability principles in the constitution. Every feature
   inherits them, and the plan's Constitution Check applies them without the SRE reviewing every
   feature.
2. **Per feature**: the dev writes spec and plan. The SRE enters at `clarify` only if the feature
   exceeds a risk threshold (new service, new datastore, load spikes, critical path).
3. **At deploy**: the SRE translates `SC-xxx` into SLOs and Constraints into limits and HPA.
4. **After an incident**: the postmortem decides where the constraint should have been written.
   Recurring class of failures → constitution, valid for all future features. Specific case →
   the feature's spec or plan. Environment → platform.

The three organizational models:

- **Same person** (you build it, you run it): works in small teams. The constitution acts as
  "SRE in absentia": it carries the operational knowledge without the dev having to remember it
  at every feature.
- **They write every spec together**: does not scale, the SRE becomes the bottleneck exactly when
  generation accelerates. Only for at-risk features.
- **SRE downstream with their own specifications**: correct only at the platform level. If the
  SRE rewrites the feature's constraints elsewhere, two intents arise for the same thing and
  drift between plan and manifests is guaranteed.

## What changes in the job

- From reviewing the individual change to writing the rules that every generation respects.
- The error budget becomes the brake on the speed of change, which grows with spec-driven
  development.
- The postmortem changes its question: not "what broke" but **"where should it have been
  written"**: constitution, spec, plan, test or configuration.
- **Spec drift** becomes a natural responsibility of the SRE: it is the only role that sees
  together what is running and what the spec says.

## Where a runtime divergence comes from

| What happens | Where it is fixed |
|---|---|
| the spec says X, the runtime does not-X | implementation + the missing test |
| the spec is silent on what broke | spec or plan, then regenerate |
| spec and code consistent, the environment breaks | operational constraints / configuration |
| spec respected but wrong with respect to the real world | intent |

## Gaps observed in Spec Kit for "run it"

Log of the points where vanilla Spec Kit (1.1.1) does not cover SRE work, observed by using the
tool on feature 001. Each step of the cycle adds its own here. It is the basis for designing the
`sre` preset and the `run` extension: only what has a documented gap here gets built.

| ID | Step | Gap | How we covered it for now | Where it could live |
|---|---|---|---|---|
| G-001 | constitution, plan | No concept of environment: spec and plan do not distinguish `dev`, `test` and `prod`, yet envelope and SLOs may change from one environment to another. | Environments table in constitution v1.1.0; the design must fit in all the declared envelopes. | `sre` preset: environments section in the plan-template, with envelope and SLOs per environment |
| G-002 | specify | The Success Criteria guidelines push toward perceived, vague outcomes ("users see results instantly") and discourage latency thresholds; the SRE needs measurable thresholds and windows on the running service. | SC-001..SC-008 written with percentiles, thresholds and windows, measured at the service boundary. | `sre` preset: SC guidelines in the spec-template |
| G-003 | out of cycle | No level for platform decisions: everything is a feature (`specs/NNN-slug`), but the platform consumes envelope before any feature and is not a feature. | Decision P-001 in `platform/README.md`, referenced by the constitution. | to be decided: a "platform decision" artifact type or a dedicated SRE feature |

## Open

- How spec drift is measured: does the spec still describe the running code?
- What exactly `converge` does, and whether the extensions for bugs are core or community.

Closed:

- Where the Kubernetes manifests live: in the repo, next to the feature that produces them, as a
  neutral Kustomize base plus one overlay per environment (constitution v1.1.0, 2026-10-05). A
  separate repo would have opened a second drift, between plan and manifests.
- Who owns the non-functional fields of `plan.md`: the SRE. Principles III-VIII (operability,
  bounded resources, observability, provenance, safe delivery, postmortems) are theirs, so also
  the `OC-xxx` constraints, the SLOs and the resource budget that derive from them in the plan;
  the Dev writes them, the SRE approves them at the plan gate (constitution v1.0.0, 2026-10-05).
- Risk threshold that brings the SRE into a feature: a new service, a new datastore or a
  load-sensitive path. Above the threshold the SRE gate triggers at the plan; below it, the SRE
  intervenes only at the production readiness gate (constitution v1.0.0, 2026-10-05).

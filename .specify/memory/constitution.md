# sdlc-speckit-SRE Constitution

## Core Principles

Each principle has an owning role. Today Dev and SRE are the same person; the roles stay distinct
so that every artifact has exactly one owner.

### I. Spec-First, Code Is Derived (owner: Dev)

- The specification is the primary artifact; code is its materialization.
- Any behavioral change, incident fixes included, MUST start by amending the owning artifact
  (`spec.md` or `plan.md`) before the code changes.
- Hand-patching code without updating the owning artifact is forbidden.

Rationale: if code is regenerated from the spec, a fix applied only to code is lost on the next
generation and the defect returns.

### II. Test-First (owner: Dev, NON-NEGOTIABLE)

- Every functional requirement (`FR-xxx`) and success criterion (`SC-xxx`) MUST have at least one
  automated test, written and failing before the implementation.
- Tests use the Go standard `testing` package; red-green-refactor is enforced.

Rationale: the tests are what bind the derived code to the spec.

### III. Operability Is a Requirement (owner: SRE)

- Every observable success criterion MUST map to an SLI and an SLO with threshold and window,
  recorded in `plan.md`.
- Every non-functional constraint in `plan.md` MUST carry an ID (`OC-xxx`) and a measurable
  threshold.
- A feature is not done until its SLOs are defined and measurable on the running system.

Rationale: a constraint without an ID and a threshold cannot be traced from a runtime violation
back to the artifact that should have prevented it.

### IV. Bounded Resources (owner: SRE)

- No unbounded caches, queues, goroutines or buffers; every in-memory structure MUST declare its
  bound.
- Each feature MUST declare a memory and CPU budget in `plan.md`; Kubernetes requests and limits
  are derived from that budget, never chosen independently.

Rationale: unbounded growth is the most common way a correct feature fails at runtime, and limits
set apart from the plan create a second, drifting source of intent.

### V. Observability by Default (owner: SRE)

- OpenTelemetry for traces and metrics; RED metrics (rate, errors, duration) per endpoint;
  structured JSON logs.
- Every telemetry signal MUST carry `service.version` (the commit SHA) and the feature branch ID.

Rationale: a runtime signal that already names its version and feature does not need to be
correlated after the fact.

### VI. Provenance (owner: SRE)

- Container images MUST carry the OCI labels `org.opencontainers.image.revision` and
  `org.opencontainers.image.source`, plus the feature ID.
- Kubernetes Deployments MUST carry the same values as annotations.
- Any running pod MUST resolve to commit, feature and spec as recorded data, without guessing.

Rationale: tracing an incident to its spec is only reliable if every link of the chain is data.

### VII. Safe Delivery (owner: SRE)

- Every deployable service MUST expose readiness and liveness probes and shut down gracefully on
  SIGTERM.
- Every deployable change MUST document its rollout and rollback procedure.

Rationale: recovery has to be cheap and predictable so that it never substitutes for a fix.

### VIII. Incidents Flow Upstream (owner: SRE leads, Dev approves)

- Every incident MUST get a postmortem whose main output states where the violated constraint
  should have been written: constitution (recurring class of failure), spec or plan
  (feature-specific), test, or platform configuration.
- Mitigation (restart, scaling, rollback) MUST NOT close an incident; only a verified upstream fix
  does, checked against the original success criteria and SLOs.

Rationale: recovery, remediation and root cause resolution are different outcomes; only the last
one prevents recurrence.

### IX. Simplicity (owner: Dev)

- Go standard library first.
- Every new dependency MUST be justified in the Complexity Tracking section of `plan.md`.

Rationale: each dependency is code nobody specified.

## Technology and Runtime Constraints

- Language: Go, latest stable release.
- Runtime: Kubernetes. The `dev` environment is a local kind cluster on the developer's machine;
  `test` and `prod` may become GKE clusters (see Environments and Portability).
- Container images are built locally and loaded into kind in `dev`; other environments pull them
  from a registry.
- Kubernetes manifests are versioned in this repository next to the feature that produces them,
  as a neutral Kustomize base plus one overlay per environment.
- Metrics are Prometheus-compatible.

### Platform Envelope (owner: SRE, NON-NEGOTIABLE)

The capacity below is the real infrastructure available, as stated by the customer. It is a hard
limit, not a default to be raised when a feature needs more; the application design MUST fit
inside it. The cluster is created by `platform/kind/up.ps1` and the values were measured on
2026-10-05.

| Item | CPU | Memory |
|---|---|---|
| Node hard cap (Docker limit on the single kind node) | 2 | 4 GiB |
| Node allocatable (what the scheduler can place) | 1750m | ~3.3 GiB |
| Kubernetes system pods, requests | 950m | 290 MiB |
| **Left for observability stack and application, requests** | **800m** | **~3.0 GiB** |

- Every pod MUST declare CPU and memory requests and limits; the sum of requests of everything
  outside `kube-system` MUST NOT exceed the remaining envelope.
- CPU requests are the scarcest resource: the system pods already take 54% of allocatable.
- Each feature's budget (principle IV) is allocated from this envelope in `plan.md`, together
  with the share already taken by previous features and by the observability stack.
- A plan that does not fit MUST change the design, not the envelope.
- The envelope MUST be enforced as a `ResourceQuota` on the application and observability
  namespaces, so the sum rule is checked at admission and not only in review.
- Platform components are allocated first. The observability stack of platform decision P-001
  (`platform/README.md`) takes 450m CPU and ~1.1 GiB of requests, leaving **350m CPU and
  ~1.9 GiB of requests to applications** in `dev`.

### Environments and Portability (owner: SRE)

| Environment | Where | Envelope |
|---|---|---|
| `dev` | local kind cluster (`platform/kind/`) | the Platform Envelope above |
| `test` | GKE cluster, when created | agreed with the customer when created |
| `prod` | GKE cluster, when created | agreed with the customer when created |

- A feature design MUST fit every declared envelope; today only `dev` is declared.
- Porting to GKE MUST change configuration only, never spec or code.
- Manifests MUST be a neutral Kustomize base plus one overlay per environment. Exposure (NodePort
  in `dev`, managed Gateway API on GKE), image reference and collector exporters live only in
  overlays.
- The base MUST NOT contain kind-specific constructs: no `hostPath`, no node references, no
  explicit `storageClassName`.
- Applications MUST emit telemetry only via OTLP to the in-cluster OpenTelemetry Collector, never
  directly to a backend.
- Datastores MUST work identically on kind and GKE: a generic persistent volume, or an external
  service reached by address.

Rationale: portability that is not enforced from the first feature is lost by the time it is
needed; keeping every environment difference in overlays makes the port a configuration change.

## Development and Operations Workflow

- Spec Kit cycle: constitution, specify, clarify, plan, tasks, analyze, implement, converge.
- Each feature lives on its own `NNN-slug` branch and is merged to `main` through a pull request.
- SRE gate at plan time for features above the risk threshold: a new service, a new datastore, or
  a load-sensitive path. The gate checks principles III to VII against `plan.md`.
- Production-readiness gate before deploying to any environment: SLOs measurable, resource budget mapped to
  requests and limits, probes, provenance labels and annotations, rollback procedure documented.
- After deployment, observed SLOs are compared with the success criteria; an incident follows
  principle VIII.

## Governance

- This constitution supersedes all other practices in this repository.
- Ownership: principles III to VIII belong to the SRE role; I, II and IX to the Dev role.
  Amendments to a principle are proposed by its owner and approved by the other role.
- Amendments come from postmortems (principle VIII) or explicit decisions, and are recorded in the
  Sync Impact Report of the amending change.
- Versioning follows semantic versioning: MAJOR for removed or redefined principles, MINOR for new
  principles or materially expanded guidance, PATCH for clarifications.
- Compliance: the Constitution Check in every `plan.md` verifies principles I to IX; every pull
  request verifies that changed behavior has an amended owning artifact.

**Version**: 1.1.0 | **Ratified**: 2026-10-05 | **Last Amended**: 2026-10-05

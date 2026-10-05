# Platform

Platform level, SRE owner. This is where the decisions that apply to all features live, and that
consume the constitution's envelope before a feature asks for a share of it.

## Environments

| Environment | Where | Envelope | Status |
|---|---|---|---|
| `dev` | local kind cluster (`platform/kind/`) | 2 CPU / 4 GiB, hard limit (constitution) | active |
| `test` | GKE cluster | to be defined with the customer | possible at any time |
| `prod` | GKE cluster | to be defined with the customer | possible at any time |

`dev` is the environment where every feature is developed, deployed and run today. `test` and
`prod`, when they come into being, will be real GKE clusters, each with its own envelope and its
own overlay. A feature's design must fit in all the declared envelopes; as long as only `dev`
exists, the reference is its envelope.

## Decision P-001: exposure, mesh and observability stack

**Status**: accepted, 2026-10-05.

**Constraint**: requests available for observability and application: **800m CPU, ~3.0 GiB**.
CPU is the scarce resource; memory is not. Every component below is paid for in requests, not in
average usage, because the sum of the requests is what the scheduler compares with the
allocatable.

### Endpoint exposure: NodePort, no ingress controller

Endpoints reach the machine through kind's `extraPortMappings` to NodePorts, bound to
`127.0.0.1`. An ingress controller would cost 100m or more of requests to route a single
application service, that is one eighth of the envelope in exchange for nothing the test needs.
ingress-nginx was also retired from the Kubernetes project in 2026: a component without
maintenance is not adopted. If host or path routing is needed in the future, the Gateway API will
be evaluated with a dedicated feature that justifies its share. On GKE the Gateway API is managed
and costs no envelope (see Portability to GKE).

| Endpoint | NodePort | Host |
|---|---|---|
| URL shortener | 30080 | `127.0.0.1:30080` |
| Prometheus | 30090 | `127.0.0.1:30090` |
| Grafana | 30030 | `127.0.0.1:30030` |

Adding a port requires recreating the cluster: kind does not change the port mappings of an
existing cluster. Grafana's port was added by recreating the cluster on 2026-10-05, when it
contained only the system pods.

### Service mesh: none

Istio with the default profile asks for 500m CPU and 2 GiB of requests for istiod alone, plus a
sidecar per pod: by itself it exceeds the envelope. Linkerd costs less but adds a proxy per pod
and a three-component control plane, and since 2024 the open source project publishes only edge
releases. The typical benefit of a mesh (mTLS between services, golden metrics, retries) does not
exist here: there is a single service, with no east-west traffic, and the RED metrics already
come from OpenTelemetry (principle V). The mesh comes back up for discussion when there are at
least two services that talk to each other.

### Observability stack: all OTLP, a single collector

The application emits metrics, traces and logs via OpenTelemetry to an **OpenTelemetry
Collector** in the cluster; the collector also gathers the pod logs from the node's files. Every
backend receives OTLP natively, so no proprietary exporters are needed.

| Component | Role | CPU req | Mem req | Mem limit | Data limit |
|---|---|---|---|---|---|
| OTel Collector (contrib) | OTLP in, pod logs, routing | 100m | 128Mi | 256Mi | batch and memory limiter |
| Prometheus (OTLP receiver) | metrics, SLO rules and alerts | 150m | 512Mi | 1Gi | 3 days, 2 GiB |
| Loki, single binary, filesystem | logs | 100m | 256Mi | 512Mi | 3 days |
| Tempo, monolithic | traces | 50m | 128Mi | 256Mi | 24 hours |
| Grafana | SLO dashboards | 50m | 128Mi | 256Mi | none |
| **Observability total** | | **450m** | **~1.1 GiB** | | |
| **Left for the application** | | **350m** | **~1.9 GiB** | | |

Loki is included because the structured JSON logs of principle V must be queryable together with
metrics and traces during an incident; without a backend only `kubectl logs` would remain, which
loses everything when the pod restarts.

The node's disk is not limited by `docker update`: for this reason every backend declares a
retention and, where possible, a size cap (principle IV applies to the platform too).

The load generator used to verify the SCs runs on the host machine, outside the cluster, so it
consumes no envelope and measures the service from the user's point of view.

### Portability to GKE

Porting to GKE must remain possible at any time without touching the spec or the code: only the
environment configuration changes. Rules:

- **Base plus overlay.** Each feature's manifests are a neutral base (Deployment, `ClusterIP`
  Service, ConfigMap) with one overlay per environment (`dev` today, `test` and `prod` on GKE when
  needed), through Kustomize, already included in `kubectl` and therefore with no new
  dependencies (principle IX). The overlay holds only the environment differences: exposure,
  image reference, collector exporters.
- **Exposure only in the overlay.** In `dev` it is NodePort. On GKE it is the Gateway API with
  GKE's managed controller, which does not run in the cluster and therefore consumes no envelope.
- **Telemetry only OTLP.** The application talks only to the collector. On GKE it is enough to
  change the collector's exporters toward Managed Prometheus, Cloud Logging and Cloud Trace, or
  to keep the same stack: the application does not notice.
- **No kind-specific constructs in the base:** no `hostPath`, no references to nodes, no explicit
  `storageClassName` (each cluster's default class is used). Collecting pod logs from the node's
  files is an environment detail and lives in the overlay.
- **The envelope becomes a `ResourceQuota`.** The limit of 800m and ~3.0 GiB of requests is
  applied as a `ResourceQuota` on the application and observability namespaces. In `dev` it
  enforces the constitution's rule already at admission time, instead of only in review; on GKE
  each environment will have its own quota, equal to its envelope.
- **Images by reference.** In `dev` they are loaded with `kind load`; on GKE they come from
  Artifact Registry. Only the reference in the overlay changes, while the OCI provenance labels
  (principle VI) stay identical.

A constraint follows for the plan of 001: the chosen datastore must work the same on kind and on
GKE, that is on a generic persistent volume or as an external service reachable by address.

### Consequence for the application design

The plan of 001 starts from **350m CPU and ~1.9 GiB** of requests, not from 800m. With two
replicas at 100m a margin of 150m remains for rollouts and spikes. This is the number the plan's
SRE gate will verify.

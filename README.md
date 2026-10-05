# sdlc-speckit-SRE

Esperimento sul campo: sviluppo spec-driven con [Spec Kit](https://github.com/github/spec-kit)
esteso al "run it". Il ciclo non si ferma alla scrittura della funzionalità ma copre operabilità,
SLO, deploy su Kubernetes, verifica e postmortem. La domanda di fondo: **in quale momento del
design di un'applicazione entra in gioco l'SRE**, quando il codice è un artefatto derivato dalla
spec.

## Il banco di prova

- **App**: un URL shortener in Go, scritto interamente con Spec Kit.
- **Infra**: l'ambiente `dev` è un cluster kind locale sulla macchina dello sviluppatore;
  `test` e `prod` potranno essere cluster GKE.
  La piattaforma resta portabile su GKE in qualsiasi momento (vedi
  [`platform/README.md`](platform/README.md)). La capacità
  riproduce l'infrastruttura reale indicata dal cliente ed è un **limite invalicabile**: è
  l'applicazione ad adattarsi alla piattaforma, non il contrario.
- **Ruoli**: Dev e SRE sono la stessa persona, ma restano ruoli distinti; ogni principio e ogni
  artefatto ha un solo proprietario (vedi la constitution).

## La piattaforma

Un cluster kind a nodo singolo, creato con `platform/kind/up.ps1` e distrutto con
`platform/kind/down.ps1`. Il tetto è imposto in due punti: `docker update` sul container del nodo
(il limite reale) e `systemReserved` del kubelet (così lo scheduler vede la stessa capacità).

| Voce (misurata il 2026-10-05) | CPU | Memoria |
|---|---|---|
| Tetto del nodo | 2 | 4 GiB |
| Allocatable | 1750m | ~3,3 GiB |
| Pod di sistema Kubernetes (requests) | 950m | 290 MiB |
| **Disponibile per osservabilità e applicazione (requests)** | **800m** | **~3,0 GiB** |

La risorsa scarsa è la CPU: i pod di sistema ne prenotano già il 54%. Questo envelope sta nella
constitution ed è il primo input dell'SRE al design: ogni plan deve dichiarare la quota che usa.

## Ordine di lavoro e punti di ingresso dell'SRE

| # | Passo Spec Kit | Chi | Cosa fa l'SRE |
|---|---|---|---|
| 0 | `/speckit-constitution` | SRE + Dev | **Primo ingresso.** Scrive una volta i principi di operabilità (III-VIII): SLO, risorse limitate, osservabilità, provenance, safe delivery, postmortem. Ogni feature li eredita. |
| 1 | `/speckit-specify` | Dev | Legge soltanto. Verifica che i Success Criteria `SC-xxx` siano osservabili. |
| 2 | `/speckit-clarify` | Dev | Se la feature è a rischio, pone le domande operative: carico atteso, disponibilità, ritenzione dei dati. |
| 3 | `/speckit-plan` | Dev | **Gate SRE principale, il momento di design.** Vincoli `OC-xxx`, SLO, budget di memoria e CPU, probe, rollout e rollback. |
| 4 | `/speckit-tasks` | Dev | Verifica che esistano i task di operabilità (metriche, manifest, runbook). |
| 5 | `/speckit-analyze` | Dev | Coerenza fra artefatti, inclusi i principi III-VII. |
| 6 | `/speckit-implement` | Dev | Nessun ruolo. |
| 7 | `/speckit-converge` | Dev | Nessun ruolo. |
| 8 | Production readiness, deploy su kind | SRE | **Gate prima del deploy.** |
| 9 | Run: SLO osservati, incidenti | SRE | Postmortem: decide dove andava scritto il vincolo e riporta il fix a monte (passo 0, 1 o 3). |

Il gate al passo 3 scatta solo per le feature sopra la soglia di rischio: nuovo servizio, nuovo
datastore, percorso sensibile al carico. La prima feature dell'URL shortener la supera, perché è
un servizio nuovo.

Metodo: si parte dai **template standard** di Spec Kit, solo con la constitution arricchita, per
vedere dove Spec Kit puro non copre il "run it". Preset ed estensione `run` si disegnano dopo, sui
buchi osservati.

## Stato

- [x] Spec Kit inizializzato (Claude Code, script Python, estensione `git`)
- [x] Cluster kind con tetto 2 CPU / 4 GiB, envelope misurato
- [x] Constitution v1.0.0 con Platform Envelope, in review
- [x] Prima feature 001: spec scritta (`/speckit-specify`)
- [x] Decisione di piattaforma P-001 (esposizione, mesh, osservabilità, portabilità), accettata in [`platform/README.md`](platform/README.md)
- [ ] Feature 001: clarify, plan con gate SRE, tasks, analyze, implement
- [ ] Primo deploy su kind
- [ ] Preset `sre` ed estensione `run`, disegnati sui buchi osservati

## Struttura

- [`.specify/memory/constitution.md`](.specify/memory/constitution.md): i principi del progetto,
  ciascuno con il suo proprietario (Dev o SRE).
- [`sre-spec-driven.md`](sre-spec-driven.md): appunti di partenza sul ruolo dell'SRE in uno sviluppo
  spec-driven.
- [`platform/`](platform/README.md): decisioni di piattaforma e cluster kind (proprietario SRE).
- `.specify/`: configurazione Spec Kit (templates, scripts, workflow, estensione `git`).
- `.claude/skills/`: i comandi `/speckit-*` per Claude Code.
- `specs/NNN-slug/`: una cartella per feature (spec, plan, tasks), creata da `/speckit-specify`.

## Prerequisiti

- Go (ultima stabile), Docker, kind, kubectl
- [Spec Kit CLI](https://github.com/github/spec-kit): `uv tool install specify-cli`
- Claude Code, per i comandi `/speckit-*`

## Branching

Quello di Spec Kit: un branch `NNN-slug` per feature, creato da `/speckit-specify` tramite
l'estensione `git`, poi fuso su `main` con una pull request.

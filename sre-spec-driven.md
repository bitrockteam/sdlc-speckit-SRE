# SRE e sviluppo spec-driven

Brainstorming del 5 ottobre 2026. Contesto: lo sviluppo si fa con
[Spec Kit](https://github.com/github/spec-kit) e il codice è un artefatto derivato dalla spec.
Domanda: che ruolo ha l'SRE, e come si riconcilia ciò che accade a runtime su Kubernetes con la
spec.

## Il punto di partenza

> **Recovery ≠ Remediation ≠ Root Cause Resolution**

Restart, scaling e rollback stabilizzano un servizio senza risolvere la causa. Se il codice è
derivato dalla spec, correggerlo a mano dopo un incidente equivale a modificare codice generato:
alla rigenerazione successiva il difetto torna. La correzione deve risalire alla spec, al plan,
ai test o alla constitution.

## Spec Kit, cosa offre già

- Workflow: constitution → specify → clarify → plan → tasks → analyze → implement (→ converge).
- Per feature: branch `###-feature-name`, con `spec.md`, `plan.md`, `tasks.md`.
- `spec.md`: Functional Requirements `FR-001`, Success Criteria `SC-001`, misurabili e
  technology-agnostic.
- `plan.md`, Technical Context: **Performance Goals**, **Constraints**, **Scale/Scope**. Testo
  libero, senza ID.
- Gate "Constitution Check" nel plan.
- Nessuna tracciabilità verso commit, deploy o runtime.

## Il ponte fra spec e runtime

- Ogni `SC-xxx` osservabile diventa un **SLO** etichettato con branch della feature e ID del
  criterio. Una violazione su Kubernetes porta già il riferimento alla spec.
- I vincoli tecnici (memoria, latenza) stanno nel `plan.md` senza ID: è il punto scoperto. Il caso
  memory leak / `OOMKilled` cade lì.
- Provenance dal pod alla feature con metadati standard: OCI annotations
  (`org.opencontainers.image.revision`), attestation SLSA, attributi OpenTelemetry, branch Spec Kit.

## Dove entra l'SRE nel flusso

| Fase | Ruolo dell'SRE |
|---|---|
| `constitution` | principi di operabilità scritti una volta: ogni feature dichiara SLI/SLO, budget di risorse, comportamento in degrado, osservabilità minima, niente cache non limitate. Massima leva. |
| `specify` / `clarify` | rende i `SC-xxx` osservabili: soglia, finestra, SLI |
| `plan` | responsabile di Performance Goals, Constraints, Scale/Scope. La production readiness review si sposta qui. |
| `analyze` | copertura operativa: ogni SC ha un SLO, ogni vincolo ha un test |
| post-deploy | incident command; postmortem con azioni su spec, constitution o test, non ticket sul codice |

## Chi fa cosa: workflow per livelli

Il workflow si organizza sui livelli di Spec Kit, non sulle persone. Ogni livello ha un solo
proprietario; che dev e SRE coincidano dipende dalla dimensione del team.

| Livello | Artefatto | Scrive | Interviene |
|---|---|---|---|
| progetto | `constitution` | SRE | dev approva |
| feature | `spec.md`, `plan.md` | dev | SRE solo su `SC-xxx` osservabili e Constraints, e solo per feature a rischio |
| piattaforma | SLO policy, error budget, manifest (limits, HPA) | SRE | valori derivati dai Constraints del plan |
| contratto | error budget policy | dev e SRE insieme | unico artefatto scritto a quattro mani |
| post-incident | postmortem | SRE guida | l'esito atterra al livello giusto |

In sequenza:

1. **Una volta**: l'SRE scrive i principi di operabilità nella constitution. Ogni feature li
   eredita, e il Constitution Check del plan li applica senza che l'SRE riveda ogni feature.
2. **Per feature**: il dev scrive spec e plan. L'SRE entra in `clarify` solo se la feature supera
   una soglia di rischio (nuovo servizio, nuovo datastore, picchi di carico, percorso critico).
3. **Al deploy**: l'SRE traduce `SC-xxx` in SLO e Constraints in limits e HPA.
4. **Dopo un incidente**: il postmortem decide dove andava scritto il vincolo. Classe di guasti
   ricorrente → constitution, vale per tutte le feature future. Caso specifico → spec o plan
   della feature. Ambiente → piattaforma.

I tre modelli organizzativi:

- **Stessa persona** (you build it, you run it): funziona in team piccoli. La constitution fa da
  "SRE in absentia": porta il sapere operativo senza che il dev debba ricordarlo a ogni feature.
- **Scrivono insieme ogni spec**: non scala, l'SRE diventa il collo di bottiglia proprio quando
  la generazione accelera. Solo per le feature a rischio.
- **SRE a valle con specifiche sue**: corretto solo al livello piattaforma. Se l'SRE riscrive i
  vincoli della feature altrove, nascono due intenti per la stessa cosa e il drift fra plan e
  manifest è garantito.

## Cosa cambia nel mestiere

- Dalla revisione del singolo change alla scrittura delle regole che ogni generazione rispetta.
- L'error budget diventa il freno sulla velocità di cambiamento, che con lo sviluppo spec-driven
  cresce.
- Il postmortem cambia domanda: non "cosa si è rotto" ma **"dove andava scritto"**:
  constitution, spec, plan, test o configurazione.
- Lo **spec drift** diventa una responsabilità naturale dell'SRE: è l'unico ruolo che vede insieme
  cosa gira e cosa dice la spec.

## Da dove viene una divergenza a runtime

| Cosa succede | Dove si corregge |
|---|---|
| la spec dice X, il runtime fa non-X | implementazione + il test mancante |
| la spec tace su ciò che si è rotto | spec o plan, poi si rigenera |
| spec e codice coerenti, l'ambiente rompe | vincoli operativi / configurazione |
| spec rispettata ma sbagliata rispetto al mondo reale | intento |

## Buchi osservati in Spec Kit per il "run it"

Registro dei punti in cui Spec Kit vanilla (1.1.1) non copre il lavoro SRE, osservati usando lo
strumento sulla feature 001. Ogni passo del ciclo aggiunge qui i suoi. È la base per disegnare
il preset `sre` e l'estensione `run`: si costruisce solo ciò che qui ha un buco documentato.

| ID | Passo | Buco | Come l'abbiamo coperto per ora | Dove potrebbe vivere |
|---|---|---|---|---|
| G-001 | constitution, plan | Nessun concetto di ambiente: spec e plan non distinguono `dev`, `test` e `prod`, eppure envelope e SLO possono cambiare fra un ambiente e l'altro. | Tabella degli ambienti nella constitution v1.1.0; il design deve stare in tutti gli envelope dichiarati. | preset `sre`: sezione ambienti nel plan-template, con envelope e SLO per ambiente |
| G-002 | specify | Le linee guida dei Success Criteria spingono verso esiti percepiti e vaghi ("gli utenti vedono i risultati all'istante") e scoraggiano soglie di latenza; all'SRE servono soglie e finestre misurabili sul servizio in esecuzione. | SC-001..SC-008 scritti con percentili, soglie e finestre, misurati al confine del servizio. | preset `sre`: linee guida degli SC nello spec-template |
| G-003 | fuori ciclo | Nessun livello per le decisioni di piattaforma: tutto è feature (`specs/NNN-slug`), ma la piattaforma consuma envelope prima di ogni feature e non è una feature. | Decisione P-001 in `platform/README.md`, richiamata dalla constitution. | da decidere: un tipo di artefatto "platform decision" o una feature SRE dedicata |

## Aperto

- I manifest Kubernetes (limits, HPA, repliche) nascono da Spec Kit o vivono in un repo
  separato? Nel secondo caso c'è un secondo drift, fra plan e manifest.
- Chi possiede i campi non funzionali del `plan.md`: developer o SRE?
- Qual è la soglia di rischio che fa entrare l'SRE in una feature.
- Come si misura lo spec drift: la spec descrive ancora il codice in esecuzione?
- Cosa fa esattamente `converge`, e se le estensioni per i bug sono core o community.

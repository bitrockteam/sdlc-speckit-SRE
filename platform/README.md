# Piattaforma

Livello piattaforma, proprietario SRE. Qui stanno le decisioni che valgono per tutte le feature
e che consumano l'envelope della constitution prima che una feature ne chieda una quota.

## Ambienti

| Ambiente | Dove | Envelope | Stato |
|---|---|---|---|
| `dev` | cluster kind locale (`platform/kind/`) | 2 CPU / 4 GiB, invalicabile (constitution) | attivo |
| `test` | cluster GKE | da definire con il cliente | possibile in qualsiasi momento |
| `prod` | cluster GKE | da definire con il cliente | possibile in qualsiasi momento |

`dev` è l'ambiente in cui oggi si sviluppa, si fa il deploy e si fa il run di ogni feature.
`test` e `prod`, quando nasceranno, saranno cluster GKE veri, ciascuno con il proprio envelope e
il proprio overlay. Il design di una feature deve stare in tutti gli envelope dichiarati; finché
esiste solo `dev`, il riferimento è il suo.

## Decisione P-001: esposizione, mesh e stack di osservabilità

**Stato**: proposta, 2026-10-05, da confermare prima del plan di 001.

**Vincolo**: requests disponibili per osservabilità e applicazione: **800m CPU, ~3,0 GiB**. La
CPU è la risorsa scarsa; la memoria no. Ogni componente qui sotto si paga in requests, non in
uso medio, perché è la somma delle requests che lo scheduler confronta con l'allocatable.

### Esposizione degli endpoint: NodePort, niente ingress controller

Gli endpoint escono sulla macchina tramite `extraPortMappings` di kind verso NodePort, legati a
`127.0.0.1`. Un ingress controller costerebbe 100m o più di requests per instradare un solo
servizio applicativo, cioè un ottavo dell'envelope in cambio di nulla che serva al test.
ingress-nginx inoltre è stato ritirato dal progetto Kubernetes nel 2026: non si adotta un
componente senza manutenzione. Se in futuro servirà routing per host o path, si valuterà la
Gateway API con una feature dedicata che ne giustifichi la quota. Su GKE la Gateway API è
gestita e non costa envelope (vedi Portabilità).

| Endpoint | NodePort | Host |
|---|---|---|
| URL shortener | 30080 | `127.0.0.1:30080` |
| Prometheus | 30090 | `127.0.0.1:30090` |
| Grafana | 30030 | `127.0.0.1:30030` (da aggiungere al template) |

Aggiungere una porta richiede di ricreare il cluster: kind non modifica i port mapping di un
cluster esistente. Oggi il cluster contiene solo i pod di sistema, quindi il costo è nullo.

### Service mesh: nessuna

Istio con il profilo di default chiede per il solo istiod 500m CPU e 2 GiB di requests, più un
sidecar per pod: da solo supera l'envelope. Linkerd costa meno ma aggiunge un proxy per pod e
un control plane di tre componenti, e dal 2024 il progetto open source pubblica solo release
edge. Il beneficio tipico di una mesh (mTLS fra servizi, metriche golden, retry) qui non esiste:
c'è un solo servizio, senza traffico est-ovest, e le metriche RED arrivano già da OpenTelemetry
(principio V). La mesh torna in discussione quando ci saranno almeno due servizi che si parlano.

### Stack di osservabilità: tutto OTLP, un solo collector

L'applicazione emette metriche, trace e log via OpenTelemetry verso un **OpenTelemetry
Collector** nel cluster; il collector raccoglie anche i log dei pod dai file del nodo. Ogni
backend riceve OTLP nativamente, quindi non servono exporter proprietari.

| Componente | Ruolo | CPU req | Mem req | Mem limit | Limite dati |
|---|---|---|---|---|---|
| OTel Collector (contrib) | OTLP in, log dei pod, smistamento | 100m | 128Mi | 256Mi | batch e memory limiter |
| Prometheus (OTLP receiver) | metriche, regole SLO e alert | 150m | 512Mi | 1Gi | 3 giorni, 2 GiB |
| Loki, single binary, filesystem | log | 100m | 256Mi | 512Mi | 3 giorni |
| Tempo, monolitico | trace | 50m | 128Mi | 256Mi | 24 ore |
| Grafana | dashboard SLO | 50m | 128Mi | 256Mi | nessuno |
| **Totale osservabilità** | | **450m** | **~1,1 GiB** | | |
| **Resta all'applicazione** | | **350m** | **~1,9 GiB** | | |

Loki entra perché i log strutturati JSON del principio V devono essere interrogabili insieme a
metriche e trace durante un incidente; senza un backend resterebbero solo `kubectl logs`, che
perde tutto al riavvio del pod.

Il disco del nodo non è limitato da `docker update`: per questo ogni backend dichiara una
retention e, dove possibile, un tetto di dimensione (principio IV vale anche per la
piattaforma).

Il generatore di carico per verificare gli SC gira sulla macchina host, fuori dal cluster, così
non consuma envelope e misura il servizio dal punto di vista dell'utente.

### Portabilità verso GKE

Il porting su GKE deve restare possibile in qualsiasi momento senza toccare spec né codice:
cambia solo la configurazione d'ambiente. Regole:

- **Base più overlay.** I manifest di ogni feature sono una base neutra (Deployment, Service
  `ClusterIP`, ConfigMap) con un overlay per ambiente (`dev` oggi, `test` e `prod` su GKE quando serviranno), tramite
  Kustomize, già incluso in `kubectl` e quindi senza nuove dipendenze (principio IX).
  Nell'overlay vanno solo le differenze d'ambiente: esposizione, riferimento all'immagine,
  exporter del collector.
- **Esposizione solo nell'overlay.** In `dev` è NodePort. Su GKE è la Gateway API con il
  controller gestito di GKE, che non gira nel cluster e quindi non consuma envelope.
- **Telemetria solo OTLP.** L'applicazione parla soltanto con il collector. Su GKE basta
  cambiare gli exporter del collector verso Managed Prometheus, Cloud Logging e Cloud Trace,
  oppure tenere lo stesso stack: l'applicazione non se ne accorge.
- **Niente costrutti specifici di kind nella base:** nessun `hostPath`, nessun riferimento a
  nodi, nessuna `storageClassName` esplicita (si usa la classe di default di ciascun cluster).
  La raccolta dei log dei pod dai file del nodo è un dettaglio d'ambiente e sta nell'overlay.
- **L'envelope diventa una `ResourceQuota`.** Il limite di 800m e ~3,0 GiB di requests si
  applica come `ResourceQuota` sui namespace dell'applicazione e dell'osservabilità. In `dev` fa
  rispettare la regola della constitution già in fase di ammissione, invece che solo in review;
  su GKE ogni ambiente avrà la propria quota, pari al suo envelope.
- **Immagini per riferimento.** In `dev` si caricano con `kind load`; su GKE vengono da Artifact
  Registry. Cambia solo il riferimento nell'overlay, mentre le label OCI di provenance
  (principio VI) restano identiche.

Ne segue un vincolo per il plan di 001: il datastore scelto deve funzionare uguale su kind e su
GKE, cioè su un volume persistente generico o come servizio esterno raggiungibile per indirizzo.

### Conseguenza per il design dell'applicazione

Il plan di 001 parte da **350m CPU e ~1,9 GiB** di requests, non da 800m. Con due repliche a
100m resta un margine di 150m per rollout e picchi. È questo il numero che il gate SRE del plan
verificherà.

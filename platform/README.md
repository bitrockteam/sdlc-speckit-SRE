# Piattaforma

Livello piattaforma, proprietario SRE. Qui stanno le decisioni che valgono per tutte le feature
e che consumano l'envelope della constitution prima che una feature ne chieda una quota.

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
Gateway API con una feature dedicata che ne giustifichi la quota.

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

### Conseguenza per il design dell'applicazione

Il plan di 001 parte da **350m CPU e ~1,9 GiB** di requests, non da 800m. Con due repliche a
100m resta un margine di 150m per rollout e picchi. È questo il numero che il gate SRE del plan
verificherà.

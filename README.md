# sdlc-speckit-SRE

Esperimento sul campo: sviluppo spec-driven con [Spec Kit](https://github.com/github/spec-kit)
esteso al "run it", in modo che il ciclo non si fermi alla scrittura della funzionalità ma copra
operabilità, SLO, deploy su Kubernetes, verifica e postmortem.

- [sre-spec-driven.md](sre-spec-driven.md): appunti di partenza sul ruolo dell'SRE in uno sviluppo
  spec-driven.
- `.specify/`: configurazione Spec Kit (templates, scripts, workflow, estensione `git`).
- `.claude/skills/`: i comandi `/speckit-*` per Claude Code.

Branching: quello di Spec Kit, un branch `NNN-slug` per feature creato da `/speckit-specify`.

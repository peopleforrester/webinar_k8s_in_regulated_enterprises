# Task Tracker - CNCF Companion Toolkit Buildout

> Persistent task list for the repo restructure from security-only demo to broad CNCF toolkit.
> This file survives context clears. Keep it updated as work progresses.

## Status Legend
- [ ] Not started
- [~] In progress
- [x] Completed

---

## Phase 1: Repo Restructure
- [x] Restructure repo from security demo to broad CNCF companion toolkit (`64e0a79`)
- [x] Add navigational README hub, tool template, and supporting docs (`c0d3094`)
- [x] Polish existing tool READMEs with standardized template format (`6548c6c`)

## Phase 2: Tier 1 Tools
- [x] Helm - README, values, manifests (`e51c334`)
- [x] Kustomize - README, values, manifests (`e51c334`)
- [x] Prometheus - README, values, manifests (`e51c334`)
- [x] Grafana - README, values, manifests (`e51c334`)
- [x] OPA Gatekeeper - README, values, manifests (`e51c334`)

## Phase 3: Tier 2 Tools
- [x] ArgoCD - README, values, manifests (`9221260`)
- [x] Istio - README, values, manifests (`9221260`)
- [x] External Secrets - README, values, manifests (`9221260`)
- [x] GitOps scenario content (`9221260`)

## Phase 4: Tier 3 Tools
- [x] Crossplane - README, values, manifests (`76bd654`)
- [x] Harbor - README, values, manifests (`76bd654`)
- [x] Karpenter - README, values, manifests (`76bd654`)
- [x] Longhorn - README, values, manifests (`76bd654`)
- [x] Commit Tier 3 content (`76bd654`)
- [x] Push all local commits to origin/staging (6 commits pushed)

## Phase 5: Validation & Push
- [ ] Validate all YAML with yamllint
- [ ] Validate all shell scripts with bash -n
- [ ] Push staging to remote
- [ ] Merge staging → main (after validation)

---

## Blockers / Notes
- 5 commits sitting unpushed on local staging branch
- 4 Tier 3 tools are written but not committed
- Azure infra is destroyed — no live cluster validation possible

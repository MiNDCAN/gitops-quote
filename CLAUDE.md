# CLAUDE.md

Guidance for Claude Code (claude.ai/code) working in this repository.

## What this repo is

GitOps source of truth for **QuotePlus production customer environments** - one dedicated AKS
cluster per customer, each its own namespace set, each ArgoCD-managed from this repo. RIFAST
Systems LLC is the first customer (2026-10-23). This is deliberately a **separate repo from
`gitops-quote-mrea`** (QuotePlus's pre-existing stage environment) and from `gitops-mrea` (a
different product entirely, MREA AP Automation - do not copy patterns from there; see
`gitops-quote-mrea/CLAUDE.md` for why that repo makes the same statement about ProfitPlus).

Infrastructure (AKS, VNet, Key Vault, Workload Identity, storage accounts) for each customer lives
in the sibling repo `QUOTE_AZURE_INFRA`, under `terraform/tenants/<customer>-prod/`.

## Layout — one customer per folder, not one repo per customer

As more production customers are onboarded, each gets a new folder here:
`values/tenants/<customer>-prod/` for every chart's real values, matching the `terraform/tenants/`
grouping in `QUOTE_AZURE_INFRA`. There is no shared values layer across customers - each dedicated
cluster is fully self-contained, so platform-level charts (namespaces, external-secrets) live
alongside the per-service tenant files in that same customer folder, not in a separate
`values/shared/` the way `gitops-quote-mrea` might eventually need one for a true multi-environment
split. A new customer means: a new `values/tenants/<customer>-prod/` folder, a new pair of
ApplicationSets (or new generator-list elements, if/when this repo switches to a matrix), and a new
`projects/quoteplus-<customer>-prod-project.yaml` AppProject - never reusing another customer's
project or destination list (tenant isolation).

## gitops-quote branching — `main` vs `production`

Two long-lived branches, not just `main`:

- **`main`** is where non-prod tenant work lands by default - future staging/UAT slots, chart
  template changes, anything not yet meant to go live for a real customer.
- **`production`** is what every real customer's ArgoCD Applications actually track
  (`targetRevision: production` in every ApplicationSet template here). Promoting a change to an
  actual customer's live environment is a deliberate merge from `main` to `production`, not just
  landing on the default branch.

This is a real gate `gitops-quote-mrea` doesn't have (it only ever had one environment, so its
`main` ArgoCD-syncs directly) - don't carry that single-branch habit over here. A typo pointing an
ApplicationSet at `main` instead of `production` would silently have a real customer's Applications
tracking unreviewed work.

`quoteplus-rifast-apps`'s ApplicationSet has automated sync enabled from day one (unlike
`gitops-quote-mrea`'s stage repo, which started manual-only). The `main`→`production` merge is the
deliberate human gate here, not a second manual `argocd app sync` on top of it - confirm this is
actually the intended policy before relying on it; it was not independently re-confirmed with the
customer-facing stakeholder beyond the general branching decision.

## Secrets — Key Vault + Workload Identity, not committed plaintext

Unlike `gitops-quote-mrea` (which commits real secret values directly as a documented, explicit
stage-only shortcut - see that repo's own CLAUDE.md "Secrets" section), this repo holds real paying
customers' production infrastructure and is public. **No secret value is committed here.**

Every service chart's `secrets:` map stays empty in this repo's tenant values files. Instead:
- `workloadIdentity.enabled: true` in the tenant values (the field already exists in every chart,
  inherited from `gitops-quote-mrea`'s original - later abandoned - design intent).
- `externalSecret.enabled: true` + `externalSecret.data: {k8sSecretKey: keyVaultSecretName, ...}`
  materializes the same-named Secret (`<release>-secrets`) from that customer's own Key Vault via
  `charts/quoteplus-external-secrets`'s per-namespace `SecretStore`.
- The underlying real values are populated into each customer's own Key Vault directly
  (`az keyvault secret set`), never written to this repo.

One exception: `charts/quoteplus-temporal`'s Secret has no `deployment.yaml` of its own to label
with workload identity (all pods are the upstream `temporalio/helm-charts` subchart's) - only the
`externalSecret` block applies there. It also has a known sequencing risk: the plaintext version in
`gitops-quote-mrea` was a Helm `pre-install,pre-upgrade` hook specifically to beat the upstream
schema Job's own hook (also pre-install) - Helm hook ordering only controls when the `ExternalSecret`
object itself applies, not when ESO's controller finishes reconciling it into an actual Secret
(that happens async). Confirm the Secret exists (`kubectl get secret quoteplus-temporal-secrets`)
before the first sync of a new customer's Temporal release, don't assume hook ordering alone covers
it.

## Naming

Every object this repo creates is `quoteplus`-prefixed, same reasoning as `gitops-quote-mrea`: this
hub (`mindcan-common`) runs the MREA and ProfitPlus fleets too, and will run multiple QuotePlus
production customers side by side - cluster-singleton ArgoCD object names (`AppProject`,
`ApplicationSet`) must additionally be customer-scoped (`quoteplus-<customer>-prod`), not just
product-scoped, or two customers' bootstraps collide.

**Root apps are named after the repo's account scope, not any customer.** `quoteplus-
gitops-quote-mindcan-projects-root` and `quoteplus-gitops-quote-mindcan-applicationsets-root` - the
`gitops-quote-mindcan` segment identifies this repo (everything under the Mindcan Azure account:
every current/future customer, plus any Mindcan-internal prod/non-prod clusters added here later),
distinct from `gitops-quote-mrea`'s separate Azure account/subscription. **Do not name these after
the first customer** (e.g. "rifast") - a single pair of root apps bootstraps the *entire*
`projects/`/`apps/applicationsets/` folders for every customer this repo will ever hold, so a
customer-scoped name becomes actively misleading the moment a second customer is added.

This naming exists because of a real incident (2026-10-28): both this repo and `gitops-quote-mrea`
independently used the bare names `quoteplus-projects-root`/`quoteplus-applicationsets-root` for
their root apps. Applying this repo's version to the shared `mindcan-common` hub silently
overwrote `gitops-quote-mrea`'s root app (`kubectl apply` reported `configured`, not `created` -
easy to miss). With `automated: {prune: true}` already on that root app, it immediately deleted the
live `quoteplus-stage` AppProject, which cascaded into 9 stage Applications going
`Unknown`/`InvalidSpecError` until the root app was reverted and the Applications force-refreshed.
No live workloads were affected (AppProject deletion doesn't touch deployed pods, only ArgoCD's own
validation of them) and the whole thing recovered in about a minute, but it's a sharp reminder:
**check `kubectl get application -n argocd <name>` for an existing object before applying anything
new to the shared hub**, especially anything with `prune: true`.

## Cluster naming/sizing convention

Matches the org's existing AKS node pool pattern (confirmed 2026-10-23, same shape every ProfitPlus
production customer cluster in this subscription already uses):
- System pool: `systempool`, `Standard_D2ads_v5`, autoscaling 1-2.
- App pool: `apppool`, `Standard_D4as_v6`, autoscaling 2-4.

Changing either the default (system) node pool's name or VM size forces a full AKS cluster
replacement (`azurerm` provider constraint - not something a chart/values change can avoid). Only
safe to do before anything is deployed to that customer's cluster.

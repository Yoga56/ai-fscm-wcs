# AI-Enabled CFO Daily Brief

A liquidity cockpit for the CFO, built on **core FI only — no FSCM**. Every morning it turns open
items, clearing history, bank cash and the payment-run proposal into a ranked, ready-to-act brief:

**E**xplain why a number moved · **P**redict pay dates and the cash low point · **R**ank risks by
impact × probability · **A**dvise on trade-offs and opportunities · **D**raft the letter or approval.

- **Backend:** RAP (ABAP for Cloud Development), OData V4 — `backend/src`
- **Frontend:** freestyle SAPUI5 — `app/cfobrief`
- **AI:** Gemini through the BTP destination shared with `ABAP_CLEAN_CORE_ANALYSIS`

The illustrative numbers from the slides (cash $22M, run $12M, low point $9.5M on day 9, ABC $4M
likely late …) ship as a demo company and are pinned by tests on both sides —
see [`docs/scenario.md`](docs/scenario.md).

---

## Rules the design follows

1. **The engine computes the numbers; the AI writes the words.** Cash paths, probabilities, scores,
   deposit income and discount rates are deterministic ABAP. Gemini gets them as pre-formatted facts
   and may only rephrase. `ZCL_CFO_FACT_GUARD` rejects any answer that quotes a figure not in the
   facts, and the rule text stays (`Engine = RULE`, reason in `ErrorText`).
2. **Draft + route, never execute.** Actions create drafts: a collection notice, an exception list
   for the payment-run owner, a deferral or priority approval, a deposit proposal. People edit,
   route and approve them. Nothing posts documents, sets payment blocks or releases a run.
3. **Clean core.** Released CDS views only; what is not released (the F110 proposal, bank statement
   items) is simulated or pluggable — [`docs/data-sources.md`](docs/data-sources.md).
4. **Names never leave the system.** Customers and suppliers are pseudonymised before the AI call.
5. **Two data modes.** `LIVE` reads the ledger, `DEMO` reads the seeded slide scenario.

## Architecture

```
Freestyle SAPUI5 (app/cfobrief)                   Cockpit · What-if · Drafts · Copilot · Inbox view
        │  OData V4  /sap/opu/odata4/sap/zui_cfo_brief_o4/…
ZUI_CFO_BRIEF  ─ ZC_CFO_Brief ─┬─ ZC_CFO_RunwayDay      projections (+ DCL ZC_CFO_BRIEF)
                               ├─ ZC_CFO_Risk
                               ├─ ZC_CFO_TradeOff
                               └─ ZC_CFO_ActionDraft
ZR_CFO_Brief (managed, no draft)                   BDEF + ZBP_R_CFO_BRIEF
  static generateBrief · refreshAi · simulate · askCopilot · proposeRunExceptions
  Risk~draftCollectionNotice · TradeOff~proposeDecision
  ActionDraft~submitForApproval / approve / reject   (+ additional save → approval e-mail)
        │
ZCL_CFO_DATA_LOADER ── ZIF_CFO_DATA_SOURCE ─┬─ ZCL_CFO_SOURCE_LIVE → ZI_CFO_OpenItem / ClearingHist / PoSpend, I_JournalEntryItem
        │                                   └─ ZCL_CFO_SOURCE_DEMO → ZTCFO_DEMO_* (ZCL_CFO_DEMO_SEED)
ZCL_CFO_BRIEF_BUILDER
   ├─ P  ZCL_CFO_PAYDATE_PREDICTOR, ZCL_CFO_RUNWAY          scheduled / stressed / expected path
   ├─ E  ZCL_CFO_VARIANCE                                   overdue deltas, plant spend, supplier z-score
   ├─ R  ZCL_CFO_RISK_RANKER                                exposure × probability × floor weight
   └─ A  ZCL_CFO_TRADEOFF                                   defer · prioritise · deposit · early pay
ZCL_CFO_AI_ADVISOR ── ZCL_CFO_PROMPT_BUILDER, ZCL_CFO_PSEUDONYMIZER, ZCL_CFO_FACT_GUARD
        └─ ZIF_CFO_LLM ── ZCL_CFO_GEMINI_ADAPTER ── ZCL_CC_GEMINI_CLIENT (shared)
D  ZCL_CFO_DRAFTER (templates, polished by the advisor)
ZCL_CFO_MAILER (brief + approval mails) · ZCL_CFO_BRIEF_JOB (08:00 application job)
```

## The rules in one table

| Step | Rule |
|---|---|
| Pay-date model | per customer: share of cleared invoices paid late and their average delay; portfolio figures below 5 invoices |
| Scheduled path | receipts on promise / due date (overdue: today + 2 working days); payables in the first weekly run *R* with *R* + 7 ≥ due date; planned flows from `ZTCFO_PLANFLOW` |
| Stressed path | receipts with P(late) ≥ 0.5 arrive their average delay later |
| Explain | overdue AR/AP vs the previous brief; "held deliberately" when most overdue AP is payment-blocked; plant spend vs the three prior 30-day windows (≥ 10 %) |
| Rank | `score = exposure × P × floor weight` (2 if the item alone breaks the floor, 0.5 for blocked invoices); off-pattern when z ≥ 3 |
| Defer | in the run at the stressed low point, defer the lowest (late fee + revenue at risk) per dollar; never a `ZTCFO_CRIT` level-H item |
| Prioritise | level-H payables due in the window but not in this run: approve by *next run − proposal lead − approval lead* |
| Deposit | free scheduled cash after the low point for the deposit term, in $0.5M lots; *held* while the stressed path disagrees |
| Early pay | `d/(100−d) × 365/(net − discount days)`; affordable only if the floor holds until the original pay date |

## Corrections to the original framework

- `BSID`/`BSIK` → `I_OperationalAcctgDocItem`; `FEBAN` is a transaction, not a table.
- The sample `approveF110Run` subtracted the run from a low point that already contains it — the
  floor check here is simply *low point (with run) < floor*.
- Writing `REGUP` from the app would break clean core and "draft + route": the app produces an
  exception list for the payment-run owner instead.
- Slide date: 4 Aug 2026 is a Tuesday, so the approval deadline is **Fri 7 Aug**, not 8 Aug.
  All deadlines are computed from working days.
- Arithmetic checks: $3M × 4.2 % × 5/365 = $1,726 ("≈ $1,700"); 2/10 net 30 = 37.2 % p.a. ("≈ 37 %").

## Run the UI locally (no backend)

```bash
cd app/cfobrief
npm install
npm run start-mock        # http://localhost:8080/index.html
npm test                  # engine rules = slide numbers
npm run lint              # UI5 linter
```

The mock server serves `webapp/localService/metadata.xml` (generated from the CDS sources by
`tools/gen_metadata.py`) and runs every action — `simulate`, drafts, routing, approval — with
`mock/engine`, the JavaScript twin of the ABAP engine. The copilot answers with rules locally.

## Install the backend (ADT)

**Via abapGit (recommended):** `backend/src/` is a flat, abapGit-managed folder (one file per
object, `.abapgit.xml` included). In ADT's abapGit client, link this repository to a new or
existing package and set **Starting folder** to `/backend/src/`, then pull. All 62 objects come in
at once, already in dependency order (abapGit resolves that itself).

> abapGit does **not** pull the shared Gemini client (`ZCX_CC_ERROR`, `ZCL_CC_JSON`,
> `ZCL_CC_GEMINI_CLIENT`) — those live in the sibling `ABAP_CLEAN_CORE_ANALYSIS` package/repo.
> Either pull that repo into the same system first (own package, with a dependency), or copy the
> three classes in and rename them to `ZCL_CFO_*` — see [docs/setup.md §0](docs/setup.md).

**Via manual copy-paste:** files are named like the sibling project — the extension says which ADT
editor the content goes into. Create them in this order:

1. **Shared client** — see [docs/setup.md §0](docs/setup.md)
2. **Tables** — `backend/src/*.tabl.asddls` (`ZTCFO_CONFIG`, `_PLANFLOW`, `_CRIT`, `_DEMO_ITEM`, `_DEMO_MISC`, `_BRIEF`, `_RUNWAY`, `_RISK`, `_TRADEOFF`, `_ACTION`)
3. **Types and helpers** — `ZIF_CFO_TYPES`, `ZCL_CFO_CALENDAR`, `ZCL_CFO_FORMAT`
4. **Source views** — `ZI_CFO_OpenItem`, `ZI_CFO_ClearingHist`, `ZI_CFO_PoSpend` (check the field list in [docs/data-sources.md](docs/data-sources.md))
5. **Data access** — `ZIF_CFO_DATA_SOURCE`, `ZCL_CFO_SOURCE_DEMO`, `ZCL_CFO_SOURCE_LIVE`, `ZCL_CFO_DATA_LOADER`, `ZCL_CFO_DEMO_SEED`
6. **Engine** — `ZCL_CFO_PAYDATE_PREDICTOR`, `ZCL_CFO_RUNWAY`, `ZCL_CFO_VARIANCE`, `ZCL_CFO_RISK_RANKER`, `ZCL_CFO_TRADEOFF`, `ZCL_CFO_BRIEF_BUILDER`
7. **AI and drafts** — `ZIF_CFO_LLM`, `ZCL_CFO_GEMINI_ADAPTER`, `ZCL_CFO_PSEUDONYMIZER`, `ZCL_CFO_FACT_GUARD`, `ZCL_CFO_PROMPT_BUILDER`, `ZCL_CFO_AI_ADVISOR`, `ZCL_CFO_DRAFTER`, `ZCL_CFO_MAILER`
8. **Abstract entities** — `ZD_CFO_GenParam`, `ZD_CFO_SimParam`, `ZD_CFO_SimDay`, `ZD_CFO_AskParam`, `ZD_CFO_Answer`, `ZD_CFO_DecisionParam`
9. **BO views** — `ZR_CFO_RunwayDay`, `ZR_CFO_Risk`, `ZR_CFO_TradeOff`, `ZR_CFO_ActionDraft`, `ZR_CFO_Brief`, then the `ZC_*` projections
10. **Access control** — authorization object `ZCFO_BRF` ([setup §1](docs/setup.md)), DCLs `ZR_CFO_BRIEF`, `ZC_CFO_BRIEF`
11. **Behavior** — BDEF `ZR_CFO_Brief` → behavior pool `ZBP_R_CFO_BRIEF` (`.clas.abap` + `.locals_imp.abap`) → projection BDEF `ZC_CFO_Brief`
12. **Service** — `ZUI_CFO_BRIEF`, binding `ZUI_CFO_BRIEF_O4` (OData V4 - UI), publish
13. **Job** — `ZCL_CFO_BRIEF_JOB` + catalog entry, template, log object ([setup §4](docs/setup.md))
14. **Tests** — paste `*.testclasses.abap` into the *Test Classes* tab of `ZCL_CFO_BRIEF_BUILDER` and `ZCL_CFO_AI_ADVISOR`
15. Run `ZCL_CFO_DEMO_SEED`, then `ZCL_CFO_SMOKE_TEST`

## Repository layout

| Path | Content |
|---|---|
| `backend/src/` | one flat abapGit-managed folder — tables (`*.tabl.asddls`), source and BO CDS views (`*.ddls.asddls`), access control (`*.dcls.asdcls`), behavior definitions and pool (`*.bdef.asbdef`, `*.clas.abap`), engine/AI/drafts/mail/seed classes (`*.clas.abap`), service definition (`*.srvd.srvdsrv`), application job (`*.clas.abap`) — plus `.abapgit.xml` |
| `app/cfobrief/webapp` | UI5 app: `view/Cockpit`, `view/Inbox`, `fragment/ActionDraft`, `model/BriefService` |
| `app/cfobrief/mock` | JS twin of the engine, mock data and action handlers |
| `app/cfobrief/test` | engine tests (Node test runner) |
| `tools/gen_metadata.py` | builds the mock `$metadata` from the CDS sources |
| `docs/` | setup, data sources, scenario |

## Limits worth knowing

- The ABAP was written and reviewed without a system at hand. The JS engine, mock server and UI
  were run and tested; the ABAP objects still need a first activation in ADT — expect small syntax
  fixes, and check the released field names listed in `docs/data-sources.md`.
- The payment run is simulated from open items until a tier-2 wrapper for `REGUH`/`REGUP` is plugged in.
- Working days are Mon–Fri; swap `ZCL_CFO_CALENDAR=>IS_WORKING_DAY` for the factory calendar to honour holidays.
- `simulate` recomputes from today's data; "Brief as generated" in the chart is the stored snapshot.
- The pay-date model is empirical (share late, mean delay). `ZIF_CFO_LLM`/the predictor are the
  seams for an SAP AI Core model later.

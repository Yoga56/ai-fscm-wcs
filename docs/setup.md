# Setup — backend, AI destination, mail, job, launchpad

## 0. Prerequisite: the shared Gemini client

The brief reuses three classes from `../ABAP_CLEAN_CORE_ANALYSIS/src/lib`:
`ZCX_CC_ERROR`, `ZCL_CC_JSON`, `ZCL_CC_GEMINI_CLIENT`. Create them first (or keep that package in
the same system and add a package dependency). Configure the `GEMINI_AI` destination exactly as in
[`ABAP_CLEAN_CORE_ANALYSIS/docs/setup.md`](../../ABAP_CLEAN_CORE_ANALYSIS/docs/setup.md) — the key
lives on the destination, never in ABAP.

Another destination or model per company code: set `ZTCFO_CONFIG-DESTINATION` / `-MODEL`.
Switch the AI off: `ZTCFO_CONFIG-AI_ENABLED = ' '` (the app then shows `Rule engine`).

> **Data protection.** The prompt contains amounts, dates and invoice references — never
> customer or supplier names (they become `CUSTOMER_1`, `SUPPLIER_2` …). Clear the remaining
> content with your data-protection officer before pointing a live company code at the model.

## 1. Authorization object `ZCFO_BRF`

ADT → *New → Authorization Field* (if needed) and *Authorization Object* `ZCFO_BRF`:

| Field | Meaning |
|---|---|
| `BUKRS` | company code |
| `ACTVT` | `01` generate / refresh AI · `02` draft, edit, route · `03` display, simulate, ask · `06` delete briefs · `43` approve / reject drafts |

Add it to the IAM app of the UI (step 6) with the activities each business role needs. A typical
split: treasury analyst 01/02/03, CFO 03/43, payment-run owner 03.

Set `ZTCFO_CONFIG-FOUR_EYES = 'X'` in production so an author cannot approve their own draft.

## 2. Configuration for a live company code

`ZTCFO_CONFIG` has one row per company code. The demo seed writes company code `1000`; for a live
company code use a small console class (F9), for example:

```abap
DATA(ls) = VALUE ztcfo_config(
  company_code = '1010'  data_mode = 'LIVE'  currency = 'EUR'  liquidity_floor = '5000000'
  horizon_days = 30  run_weekday = 4  proposal_lead_bd = 1  approval_lead_bd = 3
  collection_lag_bd = 2  ap_window_days = 14  bank_gl_from = '0011001000'  bank_gl_to = '0011009999'
  stress_threshold = '0.50'  min_history = 5  history_days = 365  zscore_threshold = 3
  spend_threshold_pct = 10  factoring_lead_bd = 3  factoring_advance_pct = '97.50'
  deposit_rate_pct = '3.100'  deposit_days = 5  late_fee_rate_pct = '3.000'  deferral_days = 7
  four_eyes = abap_true  ai_enabled = abap_true  destination = 'GEMINI_AI'  model = 'gemini-2.5-pro'
  sender_email = 'brief@company.com'  recipient_email = 'cfo@company.com'
  approver_email = 'treasury-approvals@company.com' ).
MODIFY ztcfo_config FROM @ls.
```

Maintain `ZTCFO_PLANFLOW` (payroll, tax, fees by date) and `ZTCFO_CRIT` (which purchase orders or
suppliers keep a production line running) the same way, or build a *Custom Business
Configuration* on top of them.

## 3. E-mail

Outbound mail from ABAP Cloud needs the communication arrangement for scenario **SAP_COM_0548**
(Mail Server Integration) with your SMTP server. Then:

- the job sends the daily brief to `RECIPIENT_EMAIL`;
- routing a draft sends an approval request to `APPROVER_EMAIL` (from the RAP additional save —
  a mail failure never blocks the routing, it only adds a warning).

## 4. Application job (08:00 daily)

1. ADT → *New → Application Job Catalog Entry* `ZCFO_BRIEF_JOB_CAT`, class `ZCL_CFO_BRIEF_JOB`.
2. *Application Job Template* `ZCFO_BRIEF_JOB_TMPL` on that catalog entry (parameters
   `P_BUKRS`, `P_MAIL`).
3. *Application Log Object* `ZCFO_BRIEF` with subobject `JOB`.
4. Fiori app *Application Jobs* → new job from the template → recurrence daily at 08:00.

The job user needs `ZCFO_BRF` (ACTVT 01) and G/L display authorization for the bank accounts.

## 5. Service binding

Create service binding `ZUI_CFO_BRIEF_O4` — type **OData V4 - UI** — on service definition
`ZUI_CFO_BRIEF` and publish it. The service URL becomes
`/sap/opu/odata4/sap/zui_cfo_brief_o4/srvd/sap/zui_cfo_brief/0001/`, which is what
`webapp/manifest.json` expects.

Then replace the generated mock metadata with the real one:

```bash
curl -u USER "https://<host>/sap/opu/odata4/sap/zui_cfo_brief_o4/srvd/sap/zui_cfo_brief/0001/\$metadata" -o app/cfobrief/webapp/localService/metadata.xml
```

## 6. UI deployment and launchpad

1. Set system URL, client, package and transport in `app/cfobrief/ui5-deploy.yaml`.
2. `npm run deploy` in `app/cfobrief` (builds and uploads BSP `ZCFO_BRIEF`).
3. ADT → *IAM App* (type *External App*, or the generated UI5 app) for `cfo.brief`, add service
   `ZUI_CFO_BRIEF_O4` and authorization object `ZCFO_BRF`; add the app to a business catalog
   and a business role.
4. Launchpad tile: semantic object `CFOBrief`, action `display`.

## 7. Smoke test order

1. `ZCL_CFO_DEMO_SEED` (F9) — writes the demo company.
2. `ZCL_CFO_SMOKE_TEST` (F9) — rule engine on the slide scenario, then with the database and Gemini.
   `Engine : HYBRID gemini-2.5-pro` means the destination works; `RULE` + `Warning` tells you why not.
3. ABAP Unit on the package (Ctrl+Shift+F10) — `ltcl_builder`, `ltcl_helpers`, `ltcl_advisor`.
4. Preview the service binding, or point `app/cfobrief/ui5.yaml` at the system and `npm start`.

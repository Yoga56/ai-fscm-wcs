# Setup — backend, AI destination, mail, job, launchpad

## 0. Gemini connection

The Gemini client ships in this repo (`ZCL_CFO_GEMINI_CLIENT`, `ZCL_CFO_JSON`, `ZCX_CFO_ERROR` —
loosely copied from the Clean Core Analyzer classes).

**S/4HANA Cloud Public Edition has no BTP destination service** — outbound HTTP is configured as a
**communication arrangement**. `ZCL_CFO_GEMINI_CLIENT` defaults to that (mode `COMM`) and reuses
the arrangement already set up for the Clean Core Analyzer package, since it calls the same Gemini
endpoint: scenario `ZCA_CCORE_OUT`, outbound service `ZCA_CCORE_REST`.

**Where the API key lives:** a custom communication system for a non-SAP REST endpoint like this
has no "additional properties"/header slot the way a BTP destination does — its authentication
methods are Basic, Certificate or OAuth2, none of which fit a plain API-key header. So the key has
to be sent by the client itself. Set it in `ZTCFO_CONFIG-AI_API_KEY`; `ZCL_CFO_GEMINI_ADAPTER`
passes it to the client, which sends it as the `x-goog-api-key` header. This is the same approach
the Clean Core Analyzer's own client uses (its `ZCATB_CFG-API_KEY` field, maintained through its
Settings app) — the key sits in a table rather than a transport, but it is a secret in ABAP, so
restrict change/display authority on `ZTCFO_CONFIG` (`S_TABU_DIS`/`S_TABU_NAM`) to admins.

**Setting it up:**
1. Confirm the arrangement is active: *Communication Arrangements* → `ZCA_CCORE_OUT` → its
   `ZCA_CCORE_REST` service should point at `https://generativelanguage.googleapis.com`. If you
   used different names, set `ZTCFO_CONFIG-COMM_SCENARIO` / `-COMM_SERVICE`; `ZCL_CFO_DEMO_SEED`
   writes `ZCA_CCORE_OUT` / `ZCA_CCORE_REST` when both are empty.
2. Get an API key from Google AI Studio and put it in `ZTCFO_CONFIG-AI_API_KEY` for company code
   `1000` (a quick way: `UPDATE ztcfo_config SET ai_api_key = '<key>' WHERE company_code = '1000'.`
   in an ADT console, or edit the row through SE16-equivalent table maintenance).
3. Run `ZCL_CFO_SMOKE_TEST` — `Engine : HYBRID gemini-2.5-pro` means it works.

**On SAP BTP ABAP Environment** (not S/4HANA Cloud), a plain BTP destination works instead: pass
`iv_mode = zcl_cfo_gemini_client=>mode-destination` and set `ZTCFO_CONFIG-DESTINATION`, then follow
[`ABAP_CLEAN_CORE_ANALYSIS/docs/setup.md`](../../ABAP_CLEAN_CORE_ANALYSIS/docs/setup.md) §Variant A
to create the destination itself.

Another model chain per company code: set `ZTCFO_CONFIG-MODELS` (comma separated, tried strictly
left to right; a 404 unknown model, 429 quota, or 5xx moves on to the next one - a blocked prompt
or a bad key does not).
Switch the AI off: `ZTCFO_CONFIG-AI_ENABLED = ' '` (the app then shows `Rule engine`).

> **Data protection.** The prompt contains amounts, dates and invoice references — never
> customer or supplier names (they become `CUSTOMER_1`, `SUPPLIER_2` …). Clear the remaining
> content with your data-protection officer before pointing a live company code at the model.

## 1. Authorization object `ZCFO_BRF`

ADT → *New → Authorization Field* `ZCOCD` (data element `BUKRS`; the standard field `BUKRS` is not
permitted in ABAP Cloud), then *Authorization Object* `ZCFO_BRF`:

| Field | Meaning |
|---|---|
| `ZCOCD` | company code |
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
  four_eyes = abap_true  ai_enabled = abap_true  destination = 'GEMINI_AI'
  models = 'gemini-3.8-flash,gemini-3.7-flash,gemini-3.6-flash,gemini-3.5-flash'
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

Create service binding `ZUI_CFO_BRIEF` — type **OData V4 - UI** — on service definition
`ZUI_CFO_BRIEF` and publish it. The service URL becomes
`/sap/opu/odata4/sap/zui_cfo_brief/srvd/sap/zui_cfo_brief/0001/`, which is what
`webapp/manifest.json` expects.

Then replace the generated mock metadata with the real one:

```bash
curl -u USER "https://<host>/sap/opu/odata4/sap/zui_cfo_brief/srvd/sap/zui_cfo_brief/0001/\$metadata" -o app/cfobrief/webapp/localService/metadata.xml
```

## 6. UI deployment (SAP Business Application Studio) and launchpad

Until this step the freestyle app exists only as source in this repo - nothing has been deployed
to the system yet. `npm start` against `ui5.yaml` (§7 step 4) runs it from your Mac for testing;
this step puts it in the ABAP system as a real Fiori app.

1. In the BTP cockpit, open **Business Application Studio** and create a dev space of type
   **SAP Fiori** (this is the type with the Fiori deployment tools built in; *Full Stack Cloud
   Application* also works). Wait for it to start.
2. In its terminal: `git clone --branch ui https://github.com/Yoga56/ai-fscm-wcs.git`, then
   `cd ai-fscm-wcs/app/cfobrief && npm install`. Use the **`ui`** branch, not `main` - `main` is
   what abapGit pulls into ADT and deliberately has no `app/` folder at all (a non-ABAP folder
   there breaks the abapGit link); `ui` carries the same ABAP source plus `app/` and `docs/`.
3. `app/cfobrief/ui5-deploy.yaml` already points at `my402244-api.s4hana.cloud.sap`, client `080`,
   package `ZAI_FSCM_` - change these if you'd rather use a dedicated UI package. Leave
   `transport` empty; the deploy step below prompts for one.
4. Deploy: right-click `ui5-deploy.yaml` → **Deploy Application** (or `npm run deploy` in the
   terminal). First deploy asks you to log on to the system (a browser tab opens, same
   reentrance-ticket sign-in as `npm start`) and to pick or create a transport request. This
   creates BSP application `ZCFO_BRIEF`.
5. ADT → *IAM App* for `cfo.brief` (this may already exist as `ZCFO_BRIEF_EXT` if the deploy step
   or a Fiori generator created one) → **Services** tab, add the UI5 app itself alongside
   `ZUI_CFO_BRIEF` → **Authorizations** tab, confirm `ZCFO_BRF` is there → publish, add to the
   business catalog and business role from §1.
6. Launchpad tile (**Maintain Launchpad Tiles / App Descriptor Item**): semantic object `CFOBrief`,
   action `display`, pointing at BSP `ZCFO_BRIEF`; add the tile to the same business role's
   launchpad space.

## 7. Smoke test order

1. `ZCL_CFO_DEMO_SEED` (F9) — writes the demo company.
2. `ZCL_CFO_SMOKE_TEST` (F9) — rule engine on the slide scenario, then with the database and Gemini.
   `Engine : HYBRID <model>` means it worked (the model shown is whichever one in the fallback
   chain actually answered); `RULE` + `Warning` tells you why not.
3. ABAP Unit on the package (Ctrl+Shift+F10) — `ltcl_builder`, `ltcl_helpers`, `ltcl_advisor`.
4. Preview the service binding, or point `app/cfobrief/ui5.yaml` at the system and `npm start`.

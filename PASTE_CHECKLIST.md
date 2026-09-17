# Manual paste checklist — empty-stub objects

These objects were pre-created as empty stubs before the repo was linked, so
abapGit's pull will never overwrite their source — only their metadata. For
each row below: open the object in ADT, select all its source, delete, paste
the full content of the matching local file, save, activate.

Do this **after** you pull (so the metadata/description on each object is
current), working top to bottom (interfaces first, since the classes need
them to activate).

## Interfaces (3) — do these first

- [ ] `ZIF_CFO_TYPES` ← `zif_cfo_types.intf.abap`
- [ ] `ZIF_CFO_DATA_SOURCE` ← `zif_cfo_data_source.intf.abap`
- [ ] `ZIF_CFO_LLM` ← `zif_cfo_llm.intf.abap`

## Access Controls / DCLS (2)

- [ ] `ZC_CFO_BRIEF` (role) ← `zc_cfo_brief.dcls.asdcls`
- [ ] `ZR_CFO_BRIEF` (role) ← `zr_cfo_brief.dcls.asdcls`

## Classes (20)

- [ ] `ZCL_CFO_AI_ADVISOR` ← `zcl_cfo_ai_advisor.clas.abap`
- [ ] `ZCL_CFO_BRIEF_BUILDER` ← `zcl_cfo_brief_builder.clas.abap`
- [ ] `ZCL_CFO_BRIEF_JOB` ← `zcl_cfo_brief_job.clas.abap`
- [ ] `ZCL_CFO_CALENDAR` ← `zcl_cfo_calendar.clas.abap`
- [ ] `ZCL_CFO_DATA_LOADER` ← `zcl_cfo_data_loader.clas.abap`
- [ ] `ZCL_CFO_DEMO_SEED` ← `zcl_cfo_demo_seed.clas.abap`
- [ ] `ZCL_CFO_DRAFTER` ← `zcl_cfo_drafter.clas.abap`
- [ ] `ZCL_CFO_FACT_GUARD` ← `zcl_cfo_fact_guard.clas.abap`
- [ ] `ZCL_CFO_FORMAT` ← `zcl_cfo_format.clas.abap`
- [ ] `ZCL_CFO_GEMINI_ADAPTER` ← `zcl_cfo_gemini_adapter.clas.abap`
- [ ] `ZCL_CFO_MAILER` ← `zcl_cfo_mailer.clas.abap`
- [ ] `ZCL_CFO_PAYDATE_PREDICTOR` ← `zcl_cfo_paydate_predictor.clas.abap`
- [ ] `ZCL_CFO_PROMPT_BUILDER` ← `zcl_cfo_prompt_builder.clas.abap`
- [ ] `ZCL_CFO_PSEUDONYMIZER` ← `zcl_cfo_pseudonymizer.clas.abap`
- [ ] `ZCL_CFO_RISK_RANKER` ← `zcl_cfo_risk_ranker.clas.abap`
- [ ] `ZCL_CFO_RUNWAY` ← `zcl_cfo_runway.clas.abap`
- [ ] `ZCL_CFO_SMOKE_TEST` ← `zcl_cfo_smoke_test.clas.abap`
- [ ] `ZCL_CFO_SOURCE_DEMO` ← `zcl_cfo_source_demo.clas.abap`
- [ ] `ZCL_CFO_SOURCE_LIVE` ← `zcl_cfo_source_live.clas.abap`
- [ ] `ZCL_CFO_TRADEOFF` ← `zcl_cfo_tradeoff.clas.abap`
- [ ] `ZCL_CFO_VARIANCE` ← `zcl_cfo_variance.clas.abap`

## No action needed

- `ZBP_R_CFO_BRIEF` — main class is meant to be minimal (`ABSTRACT FINAL FOR
  BEHAVIOR OF`); its real handler logic is in the separate **Local Types**
  tab, which survived intact.
- `ZCX_CFO_ERROR`, `ZCL_CFO_JSON`, `ZCL_CFO_GEMINI_CLIENT` — brand new,
  vendored copies of the sibling project's shared classes. They don't exist
  in your system yet, so the pull should create them fresh with full content
  (nothing pre-existing to block it). If any of these three come in empty
  too, treat them the same way as the rest of this list, using the matching
  local file.

## Why this happened

Some objects in `ZAI_FSCM_` were created as empty placeholders before the
repo was linked (visible as `create private` with empty sections when you
open one). abapGit's pull always updates an object's description/metadata,
but never overwrites the source of an object that already exists — so these
stayed empty through every pull. The most recent **Push** from ADT then
faithfully copied that emptiness back to GitHub, which is why this file
exists: to get the real code back into both places.

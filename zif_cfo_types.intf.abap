"! <p class="shorttext synchronized">CFO Daily Brief - shared types and constants</p>
"! <p>Amounts inside the engine are DECFLOAT34 in company-code currency and are
"! only rounded when they are persisted. Receivables carry a positive amount,
"! payables a negative one once they become cash flows.</p>
INTERFACE zif_cfo_types PUBLIC.

  TYPES amount    TYPE decfloat34.
  TYPES doc_id    TYPE c LENGTH 20.
  TYPES tt_doc_id TYPE STANDARD TABLE OF doc_id WITH EMPTY KEY.
  TYPES tt_date   TYPE STANDARD TABLE OF d WITH EMPTY KEY.

  CONSTANTS: BEGIN OF account_type,
               customer TYPE c LENGTH 1 VALUE 'D',
               supplier TYPE c LENGTH 1 VALUE 'K',
             END OF account_type.

  CONSTANTS: BEGIN OF flow_kind,
               receivable TYPE c LENGTH 3 VALUE 'AR',
               payable    TYPE c LENGTH 3 VALUE 'AP',
               planned    TYPE c LENGTH 3 VALUE 'OTH',
               factoring  TYPE c LENGTH 3 VALUE 'FAC',
             END OF flow_kind.

  "! Payment block that still lets an item into the run (invoice verification).
  CONSTANTS c_block_price_variance TYPE c LENGTH 1 VALUE 'R'.

  CONSTANTS: BEGIN OF data_mode,
               live TYPE c LENGTH 4 VALUE 'LIVE',
               demo TYPE c LENGTH 4 VALUE 'DEMO',
             END OF data_mode.

  CONSTANTS: BEGIN OF engine,
               hybrid TYPE c LENGTH 6 VALUE 'HYBRID',
               rule   TYPE c LENGTH 6 VALUE 'RULE',
               seed   TYPE c LENGTH 6 VALUE 'SEED',
             END OF engine.

  CONSTANTS: BEGIN OF risk_type,
               ar_late       TYPE c LENGTH 20 VALUE 'AR_LATE',
               ap_offpattern TYPE c LENGTH 20 VALUE 'AP_OFFPATTERN',
               ap_blocked    TYPE c LENGTH 20 VALUE 'AP_BLOCKED',
               spend_spike   TYPE c LENGTH 20 VALUE 'SPEND_SPIKE',
             END OF risk_type.

  CONSTANTS: BEGIN OF advice_kind,
               defer      TYPE c LENGTH 12 VALUE 'DEFER',
               prioritize TYPE c LENGTH 12 VALUE 'PRIORITIZE',
               deposit    TYPE c LENGTH 12 VALUE 'DEPOSIT',
               early_pay  TYPE c LENGTH 12 VALUE 'EARLYPAY',
             END OF advice_kind.

  CONSTANTS: BEGIN OF action_type,
               collection_notice TYPE c LENGTH 20 VALUE 'COLLECTION_NOTICE',
               run_exceptions    TYPE c LENGTH 20 VALUE 'RUN_EXCEPTIONS',
               defer             TYPE c LENGTH 20 VALUE 'DEFER',
               prioritize        TYPE c LENGTH 20 VALUE 'PRIORITIZE',
               deposit           TYPE c LENGTH 20 VALUE 'DEPOSIT',
               early_pay         TYPE c LENGTH 20 VALUE 'EARLYPAY',
             END OF action_type.

  CONSTANTS: BEGIN OF action_status,
               draft    TYPE c LENGTH 10 VALUE 'DRAFT',
               routed   TYPE c LENGTH 10 VALUE 'ROUTED',
               approved TYPE c LENGTH 10 VALUE 'APPROVED',
               rejected TYPE c LENGTH 10 VALUE 'REJECTED',
             END OF action_status.

  CONSTANTS: BEGIN OF advice_status,
               ready   TYPE c LENGTH 10 VALUE 'READY',
               held    TYPE c LENGTH 10 VALUE 'HELD',
               blocked TYPE c LENGTH 10 VALUE 'BLOCKED',
             END OF advice_status.

  "! Authorization object: BUKRS + ACTVT
  CONSTANTS c_auth_object TYPE c LENGTH 10 VALUE 'ZCFO_BRF'.
  CONSTANTS: BEGIN OF activity,
               generate TYPE c LENGTH 2 VALUE '01',
               change   TYPE c LENGTH 2 VALUE '02',
               display  TYPE c LENGTH 2 VALUE '03',
               delete   TYPE c LENGTH 2 VALUE '06',
               approve  TYPE c LENGTH 2 VALUE '43',
             END OF activity.

  TYPES ty_config TYPE ztcfo_config.
  TYPES ty_crit   TYPE ztcfo_crit.
  TYPES tt_crit   TYPE STANDARD TABLE OF ty_crit WITH EMPTY KEY.

  " ------------------------------------------------------------ input -----
  TYPES: BEGIN OF ty_open_item,
           doc_id         TYPE doc_id,
           account_type   TYPE c LENGTH 1,
           partner        TYPE c LENGTH 10,
           partner_name   TYPE c LENGTH 80,
           amount         TYPE amount,
           net_due_date   TYPE d,
           promised_date  TYPE d,
           payment_block  TYPE c LENGTH 1,
           block_reason   TYPE c LENGTH 40,
           discount_pct   TYPE decfloat34,
           discount_date  TYPE d,
           purchase_order TYPE c LENGTH 10,
           plant          TYPE c LENGTH 4,
           item_text      TYPE c LENGTH 80,
         END OF ty_open_item,
         tt_open_item TYPE STANDARD TABLE OF ty_open_item WITH EMPTY KEY.

  TYPES: BEGIN OF ty_history,
           account_type  TYPE c LENGTH 1,
           partner       TYPE c LENGTH 10,
           amount        TYPE amount,
           net_due_date  TYPE d,
           clearing_date TYPE d,
           days_late     TYPE i,
         END OF ty_history,
         tt_history TYPE STANDARD TABLE OF ty_history WITH EMPTY KEY.

  TYPES: BEGIN OF ty_planned,
           flow_date   TYPE d,
           amount      TYPE amount,
           description TYPE c LENGTH 80,
         END OF ty_planned,
         tt_planned TYPE STANDARD TABLE OF ty_planned WITH EMPTY KEY.

  TYPES: BEGIN OF ty_spend,
           plant     TYPE c LENGTH 4,
           window_no TYPE i,
           amount    TYPE amount,
         END OF ty_spend,
         tt_spend TYPE STANDARD TABLE OF ty_spend WITH EMPTY KEY.

  TYPES: BEGIN OF ty_input,
           key_date        TYPE d,
           config          TYPE ty_config,
           opening_cash    TYPE amount,
           prev_ar_overdue TYPE amount,
           prev_ap_overdue TYPE amount,
           items           TYPE tt_open_item,
           history         TYPE tt_history,
           planned         TYPE tt_planned,
           spend           TYPE tt_spend,
           crit            TYPE tt_crit,
         END OF ty_input.

  "! What-if toggles (all optional).
  TYPES: BEGIN OF ty_sim,
           late_ids       TYPE tt_doc_id,
           held_ids       TYPE tt_doc_id,
           factor_ids     TYPE tt_doc_id,
           run_delay_days TYPE i,
           floor_override TYPE amount,
         END OF ty_sim.

  " ----------------------------------------------------------- engine -----
  TYPES: BEGIN OF ty_behaviour,
           partner   TYPE c LENGTH 10,
           n         TYPE i,
           late      TYPE i,
           late_days TYPE i,
           p_late    TYPE decfloat34,
           mean_late TYPE i,
           fallback  TYPE abap_bool,
         END OF ty_behaviour,
         tt_behaviour TYPE HASHED TABLE OF ty_behaviour WITH UNIQUE KEY partner.

  TYPES: BEGIN OF ty_flow,
           doc_id         TYPE doc_id,
           kind           TYPE c LENGTH 3,
           partner        TYPE c LENGTH 10,
           partner_name   TYPE c LENGTH 80,
           amount         TYPE amount,
           due_date       TYPE d,
           sched_date     TYPE d,
           stress_date    TYPE d,
           run_date       TYPE d,
           in_current_run TYPE abap_bool,
           held           TYPE abap_bool,
           stressed       TYPE abap_bool,
           p_late         TYPE decfloat34,
           mean_late      TYPE i,
           hist_n         TYPE i,
           payment_block  TYPE c LENGTH 1,
           discount_pct   TYPE decfloat34,
           discount_date  TYPE d,
           purchase_order TYPE c LENGTH 10,
           item_text      TYPE c LENGTH 80,
         END OF ty_flow,
         tt_flow TYPE STANDARD TABLE OF ty_flow WITH EMPTY KEY.

  TYPES: BEGIN OF ty_day,
           day_index         TYPE i,
           calendar_date     TYPE d,
           inflow            TYPE amount,
           outflow           TYPE amount,
           closing_scheduled TYPE amount,
           closing_stressed  TYPE amount,
           closing_expected  TYPE amount,
           floor_amount      TYPE amount,
           floor_delta       TYPE amount,
           is_weekend        TYPE abap_bool,
           is_run_day        TYPE abap_bool,
           is_low_point      TYPE abap_bool,
         END OF ty_day,
         tt_day TYPE STANDARD TABLE OF ty_day WITH EMPTY KEY.

  "! Path selector for ZCL_CFO_RUNWAY=>low
  CONSTANTS: BEGIN OF path,
               scheduled TYPE c LENGTH 1 VALUE 'S',
               stressed  TYPE c LENGTH 1 VALUE 'X',
               expected  TYPE c LENGTH 1 VALUE 'E',
             END OF path.

  TYPES: BEGIN OF ty_explain,
           code       TYPE c LENGTH 12,
           change_pct TYPE decfloat34,
           text       TYPE string,
         END OF ty_explain,
         tt_explain TYPE STANDARD TABLE OF ty_explain WITH EMPTY KEY.

  TYPES: BEGIN OF ty_risk,
           risk_id             TYPE c LENGTH 4,
           risk_rank           TYPE i,
           risk_type           TYPE c LENGTH 20,
           epard               TYPE c LENGTH 5,
           reference           TYPE c LENGTH 200,
           partner_name        TYPE c LENGTH 120,
           title               TYPE string,
           detail              TYPE string,
           exposure            TYPE amount,
           probability         TYPE decfloat34,
           floor_weight        TYPE decfloat34,
           score               TYPE amount,
           criticality         TYPE i,
           recommendation      TYPE c LENGTH 30,
           recommendation_text TYPE string,
           ai_note             TYPE string,
           due_by              TYPE d,
           status              TYPE c LENGTH 10,
         END OF ty_risk,
         tt_risk TYPE STANDARD TABLE OF ty_risk WITH EMPTY KEY.

  TYPES: BEGIN OF ty_advice,
           advice_id        TYPE c LENGTH 4,
           seq              TYPE i,
           kind             TYPE c LENGTH 12,
           title            TYPE string,
           question         TYPE string,
           defer_item       TYPE doc_id,
           defer_name       TYPE c LENGTH 80,
           defer_partner    TYPE c LENGTH 80,
           defer_amount     TYPE amount,
           defer_note       TYPE string,
           defer_cost       TYPE amount,
           pay_item         TYPE doc_id,
           pay_name         TYPE c LENGTH 80,
           pay_partner      TYPE c LENGTH 80,
           pay_amount       TYPE amount,
           pay_note         TYPE string,
           shortfall_before TYPE amount,
           shortfall_after  TYPE amount,
           amount           TYPE amount,
           income           TYPE amount,
           annualized_pct   TYPE decfloat34,
           recommendation   TYPE string,
           detail           TYPE string,
           caveat           TYPE string,
           confidence       TYPE c LENGTH 4,
           confidence_note  TYPE string,
           status           TYPE c LENGTH 10,
           action_date      TYPE d,
           ai_note          TYPE string,
         END OF ty_advice,
         tt_advice TYPE STANDARD TABLE OF ty_advice WITH EMPTY KEY.

  TYPES: BEGIN OF ty_brief,
           company_code       TYPE c LENGTH 4,
           brief_date         TYPE d,
           data_mode          TYPE c LENGTH 4,
           currency           TYPE c LENGTH 5,
           horizon_days       TYPE i,
           cash_today         TYPE amount,
           liquidity_floor    TYPE amount,
           run_date           TYPE d,
           next_run_date      TYPE d,
           run_total          TYPE amount,
           run_invoice_count  TYPE i,
           run_vendor_count   TYPE i,
           cash_after_run     TYPE amount,
           run_holds_floor    TYPE abap_bool,
           low_point          TYPE amount,
           low_point_day      TYPE i,
           low_point_date     TYPE d,
           stressed_low_point TYPE amount,
           stressed_low_day   TYPE i,
           headroom           TYPE amount,
           floor_breach       TYPE abap_bool,
           scheduled_breach   TYPE abap_bool,
           ar_total           TYPE amount,
           ar_overdue         TYPE amount,
           ar_overdue_chg_pct TYPE decfloat34,
           ap_total           TYPE amount,
           ap_due_window      TYPE amount,
           ap_overdue         TYPE amount,
           ap_overdue_chg_pct TYPE decfloat34,
           review_count       TYPE i,
           headline           TYPE string,
           narrative          TYPE string,
           explain_text       TYPE string,
           engine             TYPE c LENGTH 6,
           model_used         TYPE c LENGTH 60,
           error_text         TYPE string,
         END OF ty_brief.

  TYPES: BEGIN OF ty_result,
           brief    TYPE ty_brief,
           days     TYPE tt_day,
           risks    TYPE tt_risk,
           advice   TYPE tt_advice,
           explains TYPE tt_explain,
           flows    TYPE tt_flow,
           runs     TYPE tt_date,
         END OF ty_result.

  TYPES: BEGIN OF ty_draft,
           action_type   TYPE c LENGTH 20,
           recipient     TYPE c LENGTH 120,
           subject       TYPE string,
           body          TYPE string,
           internal_note TYPE string,
           amount        TYPE amount,
           engine        TYPE c LENGTH 6,
         END OF ty_draft.

ENDINTERFACE.

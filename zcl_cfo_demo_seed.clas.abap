"! <p class="shorttext synchronized">CFO Brief - DEMO scenario (the slide story)</p>
"! <p>Run with F9 in ADT. Resets company code 1000 to the illustrative scenario from
"! the slides: cash $22M, run $12M (180 invoices / 47 vendors), low point $9.5M on
"! day 9, floor $8M, ABC $4M likely late, XYZ $3M off-pattern, raw-material PO $6M.</p>
"! <p>The anchor date is the most recent Tuesday, so the weekly run lands on
"! Thursday as on the slides. Mirrors app/cfobrief/mock/engine/scenario.js row for row.</p>
"! <p>SCENARIO returns the same data in memory - the unit tests use it, so they do not
"! depend on table contents.</p>
CLASS zcl_cfo_demo_seed DEFINITION
  PUBLIC
  FINAL
  CREATE PUBLIC.

  PUBLIC SECTION.

    INTERFACES if_oo_adt_classrun.

    CONSTANTS c_company  TYPE c LENGTH 4 VALUE '1000'.
    CONSTANTS c_currency TYPE c LENGTH 5 VALUE 'USD'.
    CONSTANTS c_slide_anchor TYPE d VALUE '20260804'.

    "! Writes the scenario for the anchor (default: most recent Tuesday). Returns the anchor.
    CLASS-METHODS deploy
      IMPORTING iv_anchor        TYPE d OPTIONAL
      RETURNING VALUE(rv_anchor) TYPE d.

    "! The scenario as engine input, without touching the database.
    CLASS-METHODS scenario
      IMPORTING iv_anchor       TYPE d DEFAULT c_slide_anchor
      RETURNING VALUE(rs_input) TYPE zif_cfo_types=>ty_input.

    CLASS-METHODS default_anchor
      RETURNING VALUE(rv_anchor) TYPE d.

  PRIVATE SECTION.

    TYPES tt_item     TYPE STANDARD TABLE OF ztcfo_demo_item WITH EMPTY KEY.
    TYPES tt_misc     TYPE STANDARD TABLE OF ztcfo_demo_misc WITH EMPTY KEY.
    TYPES tt_planflow TYPE STANDARD TABLE OF ztcfo_planflow WITH EMPTY KEY.
    TYPES tt_crit     TYPE STANDARD TABLE OF ztcfo_crit WITH EMPTY KEY.

    TYPES: BEGIN OF ty_rows,
             config   TYPE ztcfo_config,
             items    TYPE tt_item,
             misc     TYPE tt_misc,
             planflow TYPE tt_planflow,
             crit     TYPE tt_crit,
             prev_ar  TYPE zif_cfo_types=>amount,
             prev_ap  TYPE zif_cfo_types=>amount,
           END OF ty_rows.

    CONSTANTS c_million TYPE i VALUE 1000000.

    CLASS-METHODS rows
      IMPORTING iv_anchor      TYPE d
      RETURNING VALUE(rs_rows) TYPE ty_rows.

    CLASS-METHODS config
      IMPORTING iv_anchor        TYPE d
      RETURNING VALUE(rs_config) TYPE ztcfo_config.

    CLASS-METHODS open_items
      IMPORTING iv_anchor TYPE d
      CHANGING  ct_items  TYPE tt_item.

    CLASS-METHODS history
      IMPORTING iv_anchor TYPE d
      CHANGING  ct_items  TYPE tt_item.

    CLASS-METHODS add_history
      IMPORTING iv_anchor       TYPE d
                iv_account_type TYPE c
                iv_partner      TYPE c
                iv_amounts      TYPE string
                iv_days_late    TYPE string
      CHANGING  ct_items        TYPE tt_item.

    CLASS-METHODS item
      IMPORTING iv_anchor       TYPE d
                iv_doc_id       TYPE clike
                iv_account_type TYPE c
                iv_partner      TYPE clike
                iv_name         TYPE clike
                iv_amount       TYPE zif_cfo_types=>amount
                iv_due          TYPE i
                iv_promised     TYPE i OPTIONAL
                iv_block        TYPE c OPTIONAL
                iv_block_reason TYPE clike OPTIONAL
                iv_disc_pct     TYPE decfloat34 OPTIONAL
                iv_disc_day     TYPE i OPTIONAL
                iv_po           TYPE clike OPTIONAL
                iv_text         TYPE clike OPTIONAL
      RETURNING VALUE(rs_item)  TYPE ztcfo_demo_item.

ENDCLASS.


CLASS zcl_cfo_demo_seed IMPLEMENTATION.

  METHOD if_oo_adt_classrun~main.
    DATA(lv_anchor) = deploy( ).
    out->write( |Demo scenario deployed for company code { c_company }, brief date | &&
                |{ zcl_cfo_calendar=>short_text( lv_anchor ) } ({ zcl_cfo_calendar=>iso( lv_anchor ) }).| ).

    " Save one brief right away, through the BO (same call as the daily job), so the
    " service has something to show. This runs the authorization check for ZCFO_BRF.
    MODIFY ENTITIES OF zr_cfo_brief
      ENTITY Brief
        EXECUTE generateBrief
        FROM VALUE #( ( %cid = 'SEED' %param-CompanyCode = c_company %param-BriefDate = lv_anchor ) )
      RESULT DATA(lt_result)
      FAILED DATA(ls_failed)
      REPORTED DATA(ls_reported).

    LOOP AT ls_reported-brief INTO DATA(ls_msg).
      IF ls_msg-%msg IS BOUND.
        out->write( |Message       : { ls_msg-%msg->if_message~get_text( ) }| ).
      ENDIF.
    ENDLOOP.

    IF ls_failed-brief IS NOT INITIAL OR lt_result IS INITIAL.
      ROLLBACK ENTITIES.
      out->write( `Brief NOT generated. If the message above is about authorization, assign a ` &&
                  `business role that grants ZCFO_BRF (activity 01, company code 1000) and run again.` ).
      RETURN.
    ENDIF.

    COMMIT ENTITIES
      RESPONSE OF zr_cfo_brief
      FAILED DATA(ls_commit_failed)
      REPORTED DATA(ls_commit_reported).

    IF ls_commit_failed-brief IS NOT INITIAL.
      LOOP AT ls_commit_reported-brief INTO DATA(ls_late_msg).
        IF ls_late_msg-%msg IS BOUND.
          out->write( |Message       : { ls_late_msg-%msg->if_message~get_text( ) }| ).
        ENDIF.
      ENDLOOP.
      out->write( `Brief could not be saved.` ).
      RETURN.
    ENDIF.

    DATA(ls_brief) = lt_result[ 1 ]-%param.
    out->write( |Brief saved   : { ls_brief-Headline } (engine { ls_brief-Engine })| ).
    out->write( `Next: open the service preview (entity Brief) or the app. You only see rows ` &&
                `if your business role grants ZCFO_BRF for company code 1000.` ).
  ENDMETHOD.


  METHOD default_anchor.
    rv_anchor = zcl_cfo_calendar=>today( ).
    WHILE zcl_cfo_calendar=>weekday( rv_anchor ) <> 2.
      rv_anchor = rv_anchor - 1.
    ENDWHILE.
  ENDMETHOD.


  METHOD deploy.

    rv_anchor = COND #( WHEN iv_anchor IS NOT INITIAL THEN iv_anchor ELSE default_anchor( ) ).
    DATA(ls_rows) = rows( rv_anchor ).

    " keep what an admin configured (mail, destination, bank accounts)
    SELECT SINGLE FROM ztcfo_config FIELDS *
      WHERE company_code = @c_company
      INTO @DATA(ls_existing).
    IF sy-subrc = 0.
      ls_rows-config-destination     = ls_existing-destination.
      ls_rows-config-model           = ls_existing-model.
      IF ls_existing-dest_instance IS NOT INITIAL.
        ls_rows-config-dest_instance = ls_existing-dest_instance.
      ENDIF.
      ls_rows-config-sender_email    = ls_existing-sender_email.
      ls_rows-config-recipient_email = ls_existing-recipient_email.
      ls_rows-config-approver_email  = ls_existing-approver_email.
      ls_rows-config-bank_gl_from    = ls_existing-bank_gl_from.
      ls_rows-config-bank_gl_to      = ls_existing-bank_gl_to.
      ls_rows-config-ai_enabled      = ls_existing-ai_enabled.
    ENDIF.
    MODIFY ztcfo_config FROM @ls_rows-config.

    " reset the demo company: seeded data and every brief built on it
    DELETE FROM ztcfo_demo_item WHERE company_code = @c_company.
    DELETE FROM ztcfo_demo_misc WHERE company_code = @c_company.
    DELETE FROM ztcfo_planflow  WHERE company_code = @c_company.
    DELETE FROM ztcfo_crit      WHERE company_code = @c_company.
    DELETE FROM ztcfo_runway   WHERE brief_uuid IN ( SELECT brief_uuid FROM ztcfo_brief WHERE company_code = @c_company ).
    DELETE FROM ztcfo_risk     WHERE brief_uuid IN ( SELECT brief_uuid FROM ztcfo_brief WHERE company_code = @c_company ).
    DELETE FROM ztcfo_tradeoff WHERE brief_uuid IN ( SELECT brief_uuid FROM ztcfo_brief WHERE company_code = @c_company ).
    DELETE FROM ztcfo_action   WHERE brief_uuid IN ( SELECT brief_uuid FROM ztcfo_brief WHERE company_code = @c_company ).
    DELETE FROM ztcfo_brief    WHERE company_code = @c_company.

    INSERT ztcfo_demo_item FROM TABLE @ls_rows-items.
    INSERT ztcfo_demo_misc FROM TABLE @ls_rows-misc.
    INSERT ztcfo_planflow  FROM TABLE @ls_rows-planflow.
    INSERT ztcfo_crit      FROM TABLE @ls_rows-crit.

    " yesterday's baseline, so "AR overdue up 12%" has something to compare with
    TRY.
        DATA(ls_prev) = VALUE ztcfo_brief(
          brief_uuid      = cl_system_uuid=>create_uuid_x16_static( )
          company_code    = c_company
          brief_date      = rv_anchor - 1
          data_mode       = zif_cfo_types=>data_mode-demo
          currency        = c_currency
          ar_overdue      = ls_rows-prev_ar
          ap_overdue      = ls_rows-prev_ap
          headline        = `Baseline from the demo seed`
          engine          = zif_cfo_types=>engine-seed ).
        GET TIME STAMP FIELD ls_prev-created_at.
        ls_prev-generated_at          = ls_prev-created_at.
        ls_prev-last_changed_at       = ls_prev-created_at.
        ls_prev-local_last_changed_at = ls_prev-created_at.
        ls_prev-created_by            = cl_abap_context_info=>get_user_technical_name( ).
        ls_prev-last_changed_by       = ls_prev-created_by.
        INSERT ztcfo_brief FROM @ls_prev.
      CATCH cx_uuid_error.
        " no baseline - the variance lines then show 0%
    ENDTRY.

  ENDMETHOD.


  METHOD scenario.

    DATA(ls_rows) = rows( iv_anchor ).

    rs_input-key_date        = iv_anchor.
    rs_input-config          = ls_rows-config.
    rs_input-prev_ar_overdue = ls_rows-prev_ar.
    rs_input-prev_ap_overdue = ls_rows-prev_ap.
    rs_input-crit            = ls_rows-crit.

    LOOP AT ls_rows-misc INTO DATA(ls_misc).
      IF ls_misc-record_type = 'BANK'.
        rs_input-opening_cash = ls_misc-amount.
      ELSE.
        APPEND VALUE #( plant = ls_misc-object_id window_no = ls_misc-window_no amount = ls_misc-amount )
          TO rs_input-spend.
      ENDIF.
    ENDLOOP.

    LOOP AT ls_rows-items INTO DATA(ls_item).
      IF ls_item-clearing_date IS INITIAL.
        APPEND CORRESPONDING #( ls_item ) TO rs_input-items.
      ELSE.
        APPEND VALUE #( account_type  = ls_item-account_type
                        partner       = ls_item-partner
                        amount        = ls_item-amount
                        net_due_date  = ls_item-net_due_date
                        clearing_date = ls_item-clearing_date
                        days_late     = ls_item-clearing_date - ls_item-net_due_date ) TO rs_input-history.
      ENDIF.
    ENDLOOP.

    rs_input-planned = VALUE #( FOR ls_flow IN ls_rows-planflow
                                ( flow_date   = ls_flow-flow_date
                                  amount      = ls_flow-amount
                                  description = ls_flow-description ) ).

  ENDMETHOD.


  METHOD rows.

    rs_rows-config  = config( iv_anchor ).
    rs_rows-prev_ar = 8040000.
    rs_rows-prev_ap = 2000000.

    open_items( EXPORTING iv_anchor = iv_anchor CHANGING ct_items = rs_rows-items ).
    history(    EXPORTING iv_anchor = iv_anchor CHANGING ct_items = rs_rows-items ).

    " bank and plant spend
    rs_rows-misc = VALUE #( company_code = c_company currency = c_currency
      ( record_type = 'BANK'  object_id = ''     window_no = 0 amount = 22 * c_million )
      ( record_type = 'SPEND' object_id = '1000' window_no = 0 amount = '13100000' )
      ( record_type = 'SPEND' object_id = '1000' window_no = 1 amount = '11400000' )
      ( record_type = 'SPEND' object_id = '1000' window_no = 2 amount = '10800000' )
      ( record_type = 'SPEND' object_id = '1000' window_no = 3 amount = '11100000' )
      ( record_type = 'SPEND' object_id = '2000' window_no = 0 amount = '6200000' )
      ( record_type = 'SPEND' object_id = '2000' window_no = 1 amount = '6000000' )
      ( record_type = 'SPEND' object_id = '2000' window_no = 2 amount = '6300000' )
      ( record_type = 'SPEND' object_id = '2000' window_no = 3 amount = '6300000' ) ).

    " payroll / tax / fees: day offset and amount in USD
    TYPES: BEGIN OF ty_plan,
             day    TYPE i,
             amount TYPE zif_cfo_types=>amount,
           END OF ty_plan.
    DATA lt_plan TYPE STANDARD TABLE OF ty_plan WITH EMPTY KEY.
    lt_plan = VALUE #(
      ( day = 1  amount = -600000 )  ( day = 2  amount = -500000 )  ( day = 3  amount = -600000 )
      ( day = 6  amount = -800000 )  ( day = 7  amount = -600000 )  ( day = 8  amount = -500000 )
      ( day = 10 amount = -300000 )  ( day = 13 amount = -500000 )  ( day = 14 amount = -200000 )
      ( day = 15 amount = -400000 )  ( day = 17 amount = -400000 )  ( day = 20 amount = -600000 )
      ( day = 21 amount = -500000 )  ( day = 22 amount = -300000 )  ( day = 24 amount = -400000 )
      ( day = 27 amount = -600000 )  ( day = 28 amount = -1000000 ) ( day = 29 amount = -300000 ) ).
    rs_rows-planflow = VALUE #( FOR ls_plan IN lt_plan INDEX INTO lv_i
                                ( company_code = c_company
                                  flow_date    = iv_anchor + ls_plan-day
                                  flow_no      = lv_i
                                  currency     = c_currency
                                  amount       = ls_plan-amount
                                  category     = 'PAYROLL'
                                  description  = 'Payroll / tax / fees' ) ).

    rs_rows-crit = VALUE #( company_code = c_company object_type = 'PO' currency = c_currency
      ( object_id = '4500001001' crit_level = 'H' prod_line = 'LINE 2' revenue_at_risk = 30 * c_million
        note = 'Feeds Line 2 - non-payment risks a production stop' )
      ( object_id = '4500001002' crit_level = 'L' prod_line = ''       revenue_at_risk = 0
        note = 'Routine restock; a few days late costs a small fee' ) ).

  ENDMETHOD.


  METHOD config.
    rs_config = VALUE #(
      company_code          = c_company
      data_mode             = zif_cfo_types=>data_mode-demo
      demo_anchor_date      = iv_anchor
      currency              = c_currency
      liquidity_floor       = 8 * c_million
      horizon_days          = 30
      run_weekday           = 4
      proposal_lead_bd      = 1
      approval_lead_bd      = 3
      collection_lag_bd     = 2
      ap_window_days        = 14
      stress_threshold      = '0.50'
      min_history           = 5
      history_days          = 365
      zscore_threshold      = 3
      spend_threshold_pct   = 10
      factoring_lead_bd     = 3
      factoring_advance_pct = '97.50'
      deposit_rate_pct      = '4.200'
      deposit_days          = 5
      late_fee_rate_pct     = '3.000'
      deferral_days         = 7
      four_eyes             = abap_false
      ai_enabled            = abap_true
      destination           = 'GEMINI_AI'
      dest_instance         = 'CFO_BRIEF'
      model                 = 'gemini-2.5-pro' ).
  ENDMETHOD.


  METHOD open_items.

    DATA lv_sum_d TYPE zif_cfo_types=>amount.
    DATA lv_sum_k TYPE zif_cfo_types=>amount.

    " ---- receivables ----------------------------------------------------
    APPEND item( iv_anchor = iv_anchor iv_doc_id = 'AR-ABC-0001' iv_account_type = 'D' iv_partner = 'C100001'
                 iv_name = 'ABC Industries' iv_amount = 4 * c_million iv_due = -12 iv_promised = 6 ) TO ct_items.
    APPEND item( iv_anchor = iv_anchor iv_doc_id = 'AR-NWT-0001' iv_account_type = 'D' iv_partner = 'C100002'
                 iv_name = 'Northwind Traders' iv_amount = 2 * c_million iv_due = -5 iv_promised = 14 ) TO ct_items.
    APPEND item( iv_anchor = iv_anchor iv_doc_id = 'AR-CON-0001' iv_account_type = 'D' iv_partner = 'C100003'
                 iv_name = 'Contoso Retail' iv_amount = 1500000 iv_due = -3 iv_promised = 10 ) TO ct_items.
    APPEND item( iv_anchor = iv_anchor iv_doc_id = 'AR-FAB-0001' iv_account_type = 'D' iv_partner = 'C100004'
                 iv_name = 'Fabrikam Inc' iv_amount = 1500000 iv_due = -4 iv_promised = 13 ) TO ct_items.
    APPEND item( iv_anchor = iv_anchor iv_doc_id = 'AR-GLX-0001' iv_account_type = 'D' iv_partner = 'C100005'
                 iv_name = 'Globex Corp' iv_amount = 2500000 iv_due = 9 ) TO ct_items.

    " other customers: day:amount (thousand USD)
    CONSTANTS lc_various TYPE string VALUE
      `1:600,2:500,3:400,6:500,7:600,8:500,9:1500,10:300,13:200,14:2000,15:800,16:900,` &
      `17:1200,20:2000,21:1100,22:700,23:800,24:1500,27:2200,28:900,29:1000,30:1200`.
    SPLIT lc_various AT ',' INTO TABLE DATA(lt_various).
    LOOP AT lt_various INTO DATA(lv_pair).
      SPLIT lv_pair AT ':' INTO DATA(lv_day) DATA(lv_thousand).
      APPEND item( iv_anchor = iv_anchor iv_doc_id = |AR-OTH-{ sy-tabix WIDTH = 4 ALIGN = RIGHT PAD = '0' }|
                   iv_account_type = 'D' iv_partner = 'C199999' iv_name = 'Other customers'
                   iv_amount = CONV i( lv_thousand ) * 1000 iv_due = CONV #( lv_day ) ) TO ct_items.
    ENDLOOP.

    " ---- payables in this week's run --------------------------------------
    APPEND item( iv_anchor = iv_anchor iv_doc_id = 'AP-XYZ-0001' iv_account_type = 'K' iv_partner = 'V200001'
                 iv_name = 'XYZ Components' iv_amount = 3 * c_million iv_due = 5 ) TO ct_items.
    APPEND item( iv_anchor = iv_anchor iv_doc_id = 'AP-ACM-0001' iv_account_type = 'K' iv_partner = 'V200002'
                 iv_name = 'Acme Metals' iv_amount = 900000 iv_due = 3
                 iv_block = 'R' iv_block_reason = 'Price variance' ) TO ct_items.
    APPEND item( iv_anchor = iv_anchor iv_doc_id = 'AP-BTP-0001' iv_account_type = 'K' iv_partner = 'V200003'
                 iv_name = 'Beta Plastics' iv_amount = 600000 iv_due = 4
                 iv_block = 'R' iv_block_reason = 'Price variance' ) TO ct_items.

    DO 177 TIMES.
      DATA(lv_n)      = sy-index.
      DATA(lv_vendor) = |V21{ ( lv_n MOD 44 ) + 1 WIDTH = 4 ALIGN = RIGHT PAD = '0' }|.
      APPEND item( iv_anchor = iv_anchor iv_doc_id = |AP-RUN-{ lv_n WIDTH = 4 ALIGN = RIGHT PAD = '0' }|
                   iv_account_type = 'K' iv_partner = lv_vendor iv_name = |Supplier { lv_vendor }|
                   iv_amount = COND #( WHEN lv_n = 177 THEN 42880 ELSE 42370 )
                   iv_due = lv_n MOD 10 ) TO ct_items.
    ENDDO.

    " ---- payables in later runs -------------------------------------------
    APPEND item( iv_anchor = iv_anchor iv_doc_id = 'AP-RAW-0001' iv_account_type = 'K' iv_partner = 'V200004'
                 iv_name = 'Kappa Chemicals' iv_amount = 6 * c_million iv_due = 12
                 iv_po = '4500001001' iv_text = 'Raw material - resin for Line 2' ) TO ct_items.
    APPEND item( iv_anchor = iv_anchor iv_doc_id = 'AP-SPR-0001' iv_account_type = 'K' iv_partner = 'V200005'
                 iv_name = 'Sigma Spares' iv_amount = 2 * c_million iv_due = 15
                 iv_po = '4500001002' iv_text = 'Spare-part restock' ) TO ct_items.
    APPEND item( iv_anchor = iv_anchor iv_doc_id = 'AP-THF-0001' iv_account_type = 'K' iv_partner = 'V200006'
                 iv_name = 'Theta Freight' iv_amount = 2 * c_million iv_due = 17 ) TO ct_items.
    APPEND item( iv_anchor = iv_anchor iv_doc_id = 'AP-IOP-0001' iv_account_type = 'K' iv_partner = 'V200007'
                 iv_name = 'Iota Packaging' iv_amount = 1500000 iv_due = 20 ) TO ct_items.
    APPEND item( iv_anchor = iv_anchor iv_doc_id = 'AP-LAE-0001' iv_account_type = 'K' iv_partner = 'V200008'
                 iv_name = 'Lambda Energy' iv_amount = 1 * c_million iv_due = 22 ) TO ct_items.
    APPEND item( iv_anchor = iv_anchor iv_doc_id = 'AP-DLT-0001' iv_account_type = 'K' iv_partner = 'V200009'
                 iv_name = 'Delta Chemicals' iv_amount = 1 * c_million iv_due = 28
                 iv_disc_pct = 2 iv_disc_day = 8 iv_text = 'Terms 2/10 net 30' ) TO ct_items.
    APPEND item( iv_anchor = iv_anchor iv_doc_id = 'AP-EPS-0001' iv_account_type = 'K' iv_partner = 'V200011'
                 iv_name = 'Epsilon Steel' iv_amount = 2500000 iv_due = 25 ) TO ct_items.
    APPEND item( iv_anchor = iv_anchor iv_doc_id = 'AP-ZET-0001' iv_account_type = 'K' iv_partner = 'V200012'
                 iv_name = 'Zeta Services' iv_amount = 1500000 iv_due = 29 ) TO ct_items.
    APPEND item( iv_anchor = iv_anchor iv_doc_id = 'AP-ETA-0001' iv_account_type = 'K' iv_partner = 'V200013'
                 iv_name = 'Eta Tooling' iv_amount = 2 * c_million iv_due = 31 ) TO ct_items.
    APPEND item( iv_anchor = iv_anchor iv_doc_id = 'AP-ETA-0002' iv_account_type = 'K' iv_partner = 'V200013'
                 iv_name = 'Eta Tooling' iv_amount = 2 * c_million iv_due = 35 ) TO ct_items.
    " held on purpose - overdue, not in any run
    APPEND item( iv_anchor = iv_anchor iv_doc_id = 'AP-OMG-0001' iv_account_type = 'K' iv_partner = 'V200010'
                 iv_name = 'Omega Logistics' iv_amount = 1900000 iv_due = -20
                 iv_block = 'A' iv_block_reason = 'Dispute - held' ) TO ct_items.

    " ---- balancing rows beyond the horizon: totals AR $85M / AP $100M -----
    LOOP AT ct_items INTO DATA(ls_item).
      IF ls_item-account_type = 'D'.
        lv_sum_d += ls_item-amount.
      ELSE.
        lv_sum_k += ls_item-amount.
      ENDIF.
    ENDLOOP.
    APPEND item( iv_anchor = iv_anchor iv_doc_id = 'AR-OTH-9999' iv_account_type = 'D' iv_partner = 'C199999'
                 iv_name = 'Other customers' iv_amount = 85 * c_million - lv_sum_d iv_due = 45 ) TO ct_items.
    APPEND item( iv_anchor = iv_anchor iv_doc_id = 'AP-OTH-9999' iv_account_type = 'K' iv_partner = 'V299999'
                 iv_name = 'Other suppliers' iv_amount = 100 * c_million - lv_sum_k iv_due = 60 ) TO ct_items.

  ENDMETHOD.


  METHOD history.
    " amounts in thousand USD, days late per invoice
    add_history( EXPORTING iv_anchor = iv_anchor iv_account_type = 'D' iv_partner = 'C100001'
                           iv_amounts   = `1000,2000,1500,3000,2500,1200,2200,1800`
                           iv_days_late = `12,0,8,10,0,7,9,8`
                 CHANGING  ct_items = ct_items ).
    add_history( EXPORTING iv_anchor = iv_anchor iv_account_type = 'D' iv_partner = 'C100002'
                           iv_amounts   = `1000,1000,1000,1000,1000,1000,1000,1000`
                           iv_days_late = `0,0,5,0,0,18,0,0`
                 CHANGING  ct_items = ct_items ).
    add_history( EXPORTING iv_anchor = iv_anchor iv_account_type = 'D' iv_partner = 'C100003'
                           iv_amounts   = `1000,1000,1000,1000,1000`
                           iv_days_late = `0,0,4,0,0`
                 CHANGING  ct_items = ct_items ).
    add_history( EXPORTING iv_anchor = iv_anchor iv_account_type = 'D' iv_partner = 'C100004'
                           iv_amounts   = `1000,1000,1000,1000,1000,1000,1000,1000,1000,1000`
                           iv_days_late = `0,3,0,0,6,0,0,2,0,0`
                 CHANGING  ct_items = ct_items ).
    add_history( EXPORTING iv_anchor = iv_anchor iv_account_type = 'D' iv_partner = 'C100005'
                           iv_amounts   = `2000,2000,2000,2000,2000,2000,2000,2000,2000,2000`
                           iv_days_late = `0,0,0,0,0,0,0,0,0,1`
                 CHANGING  ct_items = ct_items ).
    add_history( EXPORTING iv_anchor = iv_anchor iv_account_type = 'D' iv_partner = 'C199999'
                           iv_amounts   = `500,500,500,500,500,500,500,500,500,500,500,500,500,500,500,500,500,500,500,500`
                           iv_days_late = `0,0,2,0,0,0,0,3,0,0,0,0,0,0,1,0,0,0,0,0`
                 CHANGING  ct_items = ct_items ).
    add_history( EXPORTING iv_anchor = iv_anchor iv_account_type = 'K' iv_partner = 'V200001'
                           iv_amounts   = `200,300,400,500,600,400`
                           iv_days_late = `0,0,0,0,0,0`
                 CHANGING  ct_items = ct_items ).
    add_history( EXPORTING iv_anchor = iv_anchor iv_account_type = 'K' iv_partner = 'V200004'
                           iv_amounts   = `5500,6000,6500,6000,5800,6200`
                           iv_days_late = `0,0,0,0,0,0`
                 CHANGING  ct_items = ct_items ).
    add_history( EXPORTING iv_anchor = iv_anchor iv_account_type = 'K' iv_partner = 'V200005'
                           iv_amounts   = `1800,2200,2000,1900,2100,2000`
                           iv_days_late = `0,0,0,0,0,0`
                 CHANGING  ct_items = ct_items ).
  ENDMETHOD.


  METHOD add_history.
    SPLIT iv_amounts   AT ',' INTO TABLE DATA(lt_amounts).
    SPLIT iv_days_late AT ',' INTO TABLE DATA(lt_late).

    LOOP AT lt_amounts INTO DATA(lv_amount).
      DATA(lv_index) = sy-tabix.
      DATA(ls_item)  = item( iv_anchor       = iv_anchor
                             iv_doc_id       = |H-{ iv_partner }-{ lv_index WIDTH = 2 ALIGN = RIGHT PAD = '0' }|
                             iv_account_type = iv_account_type
                             iv_partner      = iv_partner
                             iv_name         = iv_partner
                             iv_amount       = CONV i( lv_amount ) * 1000
                             iv_due          = -200 + ( lv_index - 1 ) * 22 ).
      ls_item-clearing_date = ls_item-net_due_date + CONV i( lt_late[ lv_index ] ).
      APPEND ls_item TO ct_items.
    ENDLOOP.
  ENDMETHOD.


  METHOD item.
    rs_item = VALUE #(
      company_code   = c_company
      doc_id         = iv_doc_id
      account_type   = iv_account_type
      partner        = iv_partner
      partner_name   = iv_name
      currency       = c_currency
      amount         = iv_amount
      net_due_date   = iv_anchor + iv_due
      promised_date  = COND #( WHEN iv_promised IS SUPPLIED THEN iv_anchor + iv_promised )
      payment_block  = iv_block
      block_reason   = iv_block_reason
      discount_pct   = iv_disc_pct
      discount_date  = COND #( WHEN iv_disc_day IS SUPPLIED THEN iv_anchor + iv_disc_day )
      purchase_order = iv_po
      plant          = COND #( WHEN iv_po IS NOT INITIAL THEN '1000' )
      item_text      = iv_text ).
  ENDMETHOD.

ENDCLASS.

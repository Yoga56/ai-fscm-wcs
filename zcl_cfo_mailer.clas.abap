"! <p class="shorttext synchronized">CFO Brief - e-mail: the daily brief and approval requests</p>
"! <p>Uses the released CL_BCS_MAIL_MESSAGE (outbound mail needs communication
"! scenario SAP_COM_0548 - see docs/setup.md). Reads the persisted brief directly
"! from its tables, so it works from the job and from the RAP saver alike.</p>
CLASS zcl_cfo_mailer DEFINITION
  PUBLIC
  FINAL
  CREATE PUBLIC.

  PUBLIC SECTION.

    "! The 08:00 brief to the configured recipient.
    CLASS-METHODS send_brief
      IMPORTING iv_brief_uuid TYPE sysuuid_x16
      RAISING   zcx_cfo_error.

    "! "Please approve" mail when an action draft is routed.
    CLASS-METHODS send_approval_request
      IMPORTING is_config   TYPE zif_cfo_types=>ty_config
                iv_headline TYPE clike
                iv_type     TYPE clike
                iv_subject  TYPE clike
                iv_body     TYPE clike
                iv_note     TYPE clike OPTIONAL
                iv_author   TYPE clike OPTIONAL
      RAISING   zcx_cfo_error.

    "! HTML of the daily brief (also used by the smoke test for a preview).
    CLASS-METHODS brief_html
      IMPORTING iv_brief_uuid  TYPE sysuuid_x16
      EXPORTING ev_subject     TYPE string
                es_config      TYPE zif_cfo_types=>ty_config
      RETURNING VALUE(rv_html) TYPE string
      RAISING   zcx_cfo_error.

    CLASS-METHODS html
      IMPORTING iv_text        TYPE clike
      RETURNING VALUE(rv_html) TYPE string.

  PRIVATE SECTION.

    CONSTANTS c_ink   TYPE string VALUE `#1a1f4d`.
    CONSTANTS c_muted TYPE string VALUE `#5b6072`.
    CONSTANTS c_red   TYPE string VALUE `#b3261e`.
    CONSTANTS c_green TYPE string VALUE `#1b6e3a`.

    CLASS-METHODS send
      IMPORTING iv_sender    TYPE clike
                iv_recipient TYPE clike
                iv_subject   TYPE clike
                iv_html      TYPE string
      RAISING   zcx_cfo_error.

    CLASS-METHODS section
      IMPORTING iv_title       TYPE clike
      RETURNING VALUE(rv_html) TYPE string.

    CLASS-METHODS line
      IMPORTING iv_html        TYPE string
      RETURNING VALUE(rv_html) TYPE string.

    CLASS-METHODS text_to_html
      IMPORTING iv_text        TYPE clike
      RETURNING VALUE(rv_html) TYPE string.

ENDCLASS.


CLASS zcl_cfo_mailer IMPLEMENTATION.

  METHOD send_brief.
    DATA lv_subject TYPE string.
    DATA ls_config  TYPE zif_cfo_types=>ty_config.

    DATA(lv_html) = brief_html( EXPORTING iv_brief_uuid = iv_brief_uuid
                                IMPORTING ev_subject    = lv_subject
                                          es_config     = ls_config ).
    IF ls_config-recipient_email IS INITIAL.
      zcx_cfo_error=>raise( |No recipient e-mail configured for company code { ls_config-company_code }| ).
    ENDIF.
    send( iv_sender    = ls_config-sender_email
          iv_recipient = ls_config-recipient_email
          iv_subject   = lv_subject
          iv_html      = lv_html ).
  ENDMETHOD.


  METHOD send_approval_request.
    IF is_config-approver_email IS INITIAL.
      zcx_cfo_error=>raise( |No approver e-mail configured for company code { is_config-company_code }| ).
    ENDIF.

    DATA(lv_html) =
      |<div style="font-family:Arial,Helvetica,sans-serif;color:{ c_ink };max-width:640px">| &&
      |<p style="color:{ c_muted };margin:0 0 4px">Approval requested · { html( iv_type ) }| &&
      |{ COND string( WHEN iv_author IS NOT INITIAL THEN | · drafted by { html( iv_author ) }| ) }</p>| &&
      |<h2 style="margin:0 0 12px">{ html( iv_subject ) }</h2>| &&
      |<div style="border-left:3px solid { c_ink };padding:8px 12px;background:#f3f4fb">{ text_to_html( iv_body ) }</div>| &&
      COND string( WHEN iv_note IS NOT INITIAL
                   THEN |<p style="color:{ c_muted }"><b>Note:</b> { html( iv_note ) }</p>| ) &&
      |<p style="color:{ c_muted }">Context: { html( iv_headline ) }</p>| &&
      |<p>Open the CFO Daily Brief app to approve or reject. Approving records the decision only — | &&
      |the owning team executes it in its own application.</p></div>|.

    send( iv_sender    = is_config-sender_email
          iv_recipient = is_config-approver_email
          iv_subject   = |Approval needed: { iv_subject }|
          iv_html      = lv_html ).
  ENDMETHOD.


  METHOD brief_html.

    SELECT SINGLE FROM ztcfo_brief FIELDS *
      WHERE brief_uuid = @iv_brief_uuid
      INTO @DATA(ls_b).
    IF sy-subrc <> 0.
      zcx_cfo_error=>raise( `Brief not found` ).
    ENDIF.

    es_config = zcl_cfo_data_loader=>read_config( ls_b-company_code ).

    SELECT FROM ztcfo_risk FIELDS *
      WHERE brief_uuid = @iv_brief_uuid
      ORDER BY risk_rank
      INTO TABLE @DATA(lt_risks).
    SELECT FROM ztcfo_tradeoff FIELDS *
      WHERE brief_uuid = @iv_brief_uuid
      ORDER BY seq
      INTO TABLE @DATA(lt_advice).

    DATA(lv_cur) = ls_b-currency.
    ev_subject   = |Finance Daily Brief { zcl_cfo_calendar=>short_text( ls_b-brief_date ) } — { ls_b-headline }|.

    rv_html =
      |<div style="font-family:Arial,Helvetica,sans-serif;color:{ c_ink };max-width:680px;line-height:1.45">| &&
      |<p style="margin:0;color:{ c_muted };font-size:12px">Finance Daily Brief · { zcl_cfo_calendar=>short_text( ls_b-brief_date ) }| &&
      | · company code { ls_b-company_code } · { ls_b-engine }</p>| &&
      |<h2 style="margin:6px 0 10px;border-bottom:3px solid { c_ink };padding-bottom:8px">{ html( ls_b-headline ) }</h2>| &&
      |<p>{ html( ls_b-narrative ) }</p>| &&
      section( `Cash &amp; this week's run` ) &&
      line( |Cash <b>{ zcl_cfo_format=>money( iv_amount = ls_b-cash_today iv_currency = lv_cur ) }</b> today → proposal | &&
            |<b>{ zcl_cfo_format=>money( iv_amount = ls_b-run_total iv_currency = lv_cur ) }</b> | &&
            |({ zcl_cfo_calendar=>short_text( ls_b-run_date ) } · { ls_b-run_invoice_count } inv / { ls_b-run_vendor_count } vendors) → | &&
            |<b>{ zcl_cfo_format=>money( iv_amount = ls_b-cash_after_run iv_currency = lv_cur ) }</b> after the run.| ) &&
      line( |Low-point <b>{ zcl_cfo_format=>money( iv_amount = ls_b-low_point iv_currency = lv_cur ) } on Day { ls_b-low_point_day }</b> | &&
            |(floor { zcl_cfo_format=>money( iv_amount = ls_b-liquidity_floor iv_currency = lv_cur ) }). | &&
            |If the at-risk receipts are late → <b style="color:| &&
            |{ COND string( WHEN ls_b-floor_breach = abap_true THEN c_red ELSE c_green ) }">| &&
            |{ zcl_cfo_format=>money( iv_amount = ls_b-stressed_low_point iv_currency = lv_cur ) }| &&
            |{ COND string( WHEN ls_b-floor_breach = abap_true THEN ` — below floor` ) }</b>.| ).

    " exceptions inside this week's run
    DATA(lv_items) = VALUE string( ).
    DATA(lv_no)    = 0.
    LOOP AT lt_risks INTO DATA(ls_risk)
         WHERE risk_type = zif_cfo_types=>risk_type-ap_offpattern
            OR risk_type = zif_cfo_types=>risk_type-ap_blocked.
      lv_no += 1.
      lv_items = lv_items && line( |<b>{ lv_no }&nbsp; { html( ls_risk-title ) }</b> — { html( ls_risk-recommendation_text ) }| ).
    ENDLOOP.
    IF lv_items IS NOT INITIAL.
      rv_html = rv_html && section( |Review before { zcl_cfo_calendar=>short_text( ls_b-run_date ) } · exceptions inside the run| ) && lv_items.
    ENDIF.

    " approvals needed for the next run
    CLEAR lv_items.
    LOOP AT lt_advice INTO DATA(ls_adv) WHERE kind = zif_cfo_types=>advice_kind-prioritize.
      lv_no += 1.
      lv_items = lv_items && line( |<b>{ lv_no }&nbsp; { html( ls_adv-title ) }</b> — { html( ls_adv-question ) } | &&
                                   |<b>{ html( ls_adv-recommendation ) }</b>| ).
    ENDLOOP.
    IF lv_items IS NOT INITIAL.
      rv_html = rv_html && section( `Before the next run` ) && lv_items.
    ENDIF.

    " cash and collections
    CLEAR lv_items.
    LOOP AT lt_risks INTO ls_risk WHERE risk_type = zif_cfo_types=>risk_type-ar_late.
      lv_items = lv_items && line( |• { html( ls_risk-title ) } — <b>{ html( ls_risk-recommendation_text ) }</b>| ).
    ENDLOOP.
    LOOP AT lt_advice INTO ls_adv WHERE kind = zif_cfo_types=>advice_kind-deposit
                                     OR kind = zif_cfo_types=>advice_kind-early_pay
                                     OR kind = zif_cfo_types=>advice_kind-defer.
      lv_items = lv_items && line( |• { html( ls_adv-recommendation ) } | &&
                                   |<span style="color:{ c_muted }">{ html( ls_adv-detail ) }</span>| &&
                                   COND string( WHEN ls_adv-income > 0
                                                THEN | <b style="color:{ c_green }">≈ | &&
                                                     |{ zcl_cfo_format=>money( iv_amount = ls_adv-income iv_currency = lv_cur ) }</b>| ) ).
    ENDLOOP.
    IF lv_items IS NOT INITIAL.
      rv_html = rv_html && section( `Cash &amp; collections` ) && lv_items.
    ENDIF.

    IF ls_b-explain_text IS NOT INITIAL.
      rv_html = rv_html && section( `What moved` ) && line( text_to_html( ls_b-explain_text ) ).
    ENDIF.

    rv_html = rv_html &&
      |<p style="margin-top:18px;padding:10px;background:#eceefb;font-size:12px;color:{ c_muted }">| &&
      |Built on the payment-run proposal. It surfaces cash impact and the few exceptions — not every invoice. | &&
      |Finance runs the proposal; the CFO clears the exceptions. Figures are computed by the rule engine; | &&
      |AI wording is checked against them.</p></div>|.

  ENDMETHOD.


  METHOD send.

    IF iv_recipient IS INITIAL.
      zcx_cfo_error=>raise( `No recipient` ).
    ENDIF.

    TRY.
        DATA(lo_mail) = cl_bcs_mail_message=>create_instance( ).
        IF iv_sender IS NOT INITIAL.
          lo_mail->set_sender( CONV #( iv_sender ) ).
        ENDIF.

        SPLIT condense( CONV string( iv_recipient ) ) AT ',' INTO TABLE DATA(lt_to).
        LOOP AT lt_to INTO DATA(lv_to).
          lo_mail->add_recipient( CONV #( condense( lv_to ) ) ).
        ENDLOOP.

        lo_mail->set_subject( CONV #( iv_subject ) ).
        lo_mail->set_main( cl_bcs_mail_textpart=>create_instance( iv_content      = iv_html
                                                                  iv_content_type = `text/html` ) ).
        lo_mail->send( ).

      CATCH cx_bcs_mail INTO DATA(lx_mail).
        zcx_cfo_error=>raise( text = |E-mail could not be sent: { lx_mail->get_text( ) }| previous = lx_mail ).
    ENDTRY.

  ENDMETHOD.


  METHOD section.
    rv_html = |<p style="margin:16px 0 4px;font-size:12px;letter-spacing:.12em;text-transform:uppercase;| &&
              |font-weight:bold;color:{ c_muted }">{ iv_title }</p>|.
  ENDMETHOD.


  METHOD line.
    rv_html = |<p style="margin:4px 0">{ iv_html }</p>|.
  ENDMETHOD.


  METHOD text_to_html.
    rv_html = replace( val  = html( iv_text )
                       sub  = cl_abap_char_utilities=>newline
                       with = `<br>`
                       occ  = 0 ).
  ENDMETHOD.


  METHOD html.
    rv_html = escape( val = CONV string( iv_text ) format = cl_abap_format=>e_xml_text ).
    rv_html = replace( val = rv_html sub = `"` with = `&quot;` occ = 0 ).
  ENDMETHOD.

ENDCLASS.

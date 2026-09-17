"! <p class="shorttext synchronized">CFO Brief - P: customer pay-date behaviour</p>
"! <p>Empirical model on clearing history: share of invoices paid after the net
"! due date and the average delay of the late ones (rounded up to whole days).
"! Partners with fewer than MIN_HISTORY cleared items get the portfolio figures.
"! Swap this class for an SAP AI Core model later - the contract stays the same.</p>
CLASS zcl_cfo_paydate_predictor DEFINITION
  PUBLIC
  FINAL
  CREATE PUBLIC.

  PUBLIC SECTION.

    METHODS constructor
      IMPORTING it_history     TYPE zif_cfo_types=>tt_history
                iv_min_history TYPE i.

    METHODS behaviour
      IMPORTING iv_partner          TYPE clike
      RETURNING VALUE(rs_behaviour) TYPE zif_cfo_types=>ty_behaviour.

    METHODS portfolio
      RETURNING VALUE(rs_behaviour) TYPE zif_cfo_types=>ty_behaviour.

  PRIVATE SECTION.

    DATA mt_stats       TYPE zif_cfo_types=>tt_behaviour.
    DATA ms_portfolio   TYPE zif_cfo_types=>ty_behaviour.
    DATA mv_min_history TYPE i.

    "! Share of late invoices and their average delay from the raw counters.
    CLASS-METHODS finish
      IMPORTING is_counts           TYPE zif_cfo_types=>ty_behaviour
      RETURNING VALUE(rs_behaviour) TYPE zif_cfo_types=>ty_behaviour.

ENDCLASS.


CLASS zcl_cfo_paydate_predictor IMPLEMENTATION.

  METHOD constructor.

    mv_min_history = iv_min_history.

    LOOP AT it_history INTO DATA(ls_hist)
         WHERE account_type = zif_cfo_types=>account_type-customer.

      ASSIGN mt_stats[ partner = ls_hist-partner ] TO FIELD-SYMBOL(<ls_stat>).
      IF sy-subrc <> 0.
        INSERT VALUE #( partner = ls_hist-partner ) INTO TABLE mt_stats ASSIGNING <ls_stat>.
      ENDIF.

      <ls_stat>-n    += 1.
      ms_portfolio-n += 1.
      IF ls_hist-days_late > 0.
        <ls_stat>-late         += 1.
        <ls_stat>-late_days    += ls_hist-days_late.
        ms_portfolio-late      += 1.
        ms_portfolio-late_days += ls_hist-days_late.
      ENDIF.
    ENDLOOP.

    " key fields of a hashed table are write-protected - update the figures one by one
    LOOP AT mt_stats ASSIGNING <ls_stat>.
      DATA(ls_done) = finish( <ls_stat> ).
      <ls_stat>-p_late    = ls_done-p_late.
      <ls_stat>-mean_late = ls_done-mean_late.
    ENDLOOP.
    ms_portfolio = finish( ms_portfolio ).

  ENDMETHOD.


  METHOD finish.
    rs_behaviour = is_counts.
    IF rs_behaviour-n > 0.
      rs_behaviour-p_late = round( val = CONV decfloat34( rs_behaviour-late ) / rs_behaviour-n dec = 2 ).
    ENDIF.
    IF rs_behaviour-late > 0.
      rs_behaviour-mean_late = ceil( CONV decfloat34( rs_behaviour-late_days ) / rs_behaviour-late ).
    ENDIF.
  ENDMETHOD.


  METHOD behaviour.
    ASSIGN mt_stats[ partner = iv_partner ] TO FIELD-SYMBOL(<ls_stat>).
    IF sy-subrc = 0 AND <ls_stat>-n >= mv_min_history.
      rs_behaviour = <ls_stat>.
      RETURN.
    ENDIF.

    rs_behaviour          = ms_portfolio.
    rs_behaviour-partner  = iv_partner.
    rs_behaviour-n        = COND #( WHEN <ls_stat> IS ASSIGNED THEN <ls_stat>-n ELSE 0 ).
    rs_behaviour-fallback = abap_true.
  ENDMETHOD.


  METHOD portfolio.
    rs_behaviour = ms_portfolio.
  ENDMETHOD.

ENDCLASS.

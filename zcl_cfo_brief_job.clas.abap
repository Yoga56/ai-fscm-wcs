"! <p class="shorttext synchronized">CFO Brief - application job: generate at 08:00 and e-mail</p>
"! <p>Create the job catalog entry ZCFO_BRIEF_JOB_CAT and template ZCFO_BRIEF_JOB_TMPL
"! for this class in ADT (see docs/setup.md), then schedule the template daily in
"! "Application Jobs". The job user needs ZCFO_BRF with ACTVT 01 for the company code.</p>
CLASS zcl_cfo_brief_job DEFINITION
  PUBLIC
  FINAL
  CREATE PUBLIC.

  PUBLIC SECTION.
    INTERFACES if_apj_dt_exec_object.
    INTERFACES if_apj_rt_exec_object.

  PRIVATE SECTION.
    CONSTANTS: BEGIN OF param,
                 company TYPE c LENGTH 8 VALUE 'P_BUKRS',
                 mail    TYPE c LENGTH 8 VALUE 'P_MAIL',
               END OF param.

    CLASS-METHODS log
      IMPORTING iv_text     TYPE clike
                iv_severity TYPE c DEFAULT if_bali_constants=>c_severity_status.
ENDCLASS.


CLASS zcl_cfo_brief_job IMPLEMENTATION.

  METHOD if_apj_dt_exec_object~get_parameters.
    et_parameter_def = VALUE #(
      ( selname = param-company kind = if_apj_dt_exec_object=>parameter datatype = 'C' length = 4
        param_text = 'Company code' changeable_ind = abap_true mandatory_ind = abap_true )
      ( selname = param-mail kind = if_apj_dt_exec_object=>parameter datatype = 'C' length = 1
        param_text = 'Send the brief by e-mail' changeable_ind = abap_true checkbox_ind = abap_true ) ).

    et_parameter_val = VALUE #(
      ( selname = param-company kind = if_apj_dt_exec_object=>parameter sign = 'I' option = 'EQ' low = '1000' )
      ( selname = param-mail    kind = if_apj_dt_exec_object=>parameter sign = 'I' option = 'EQ' low = abap_true ) ).
  ENDMETHOD.


  METHOD if_apj_rt_exec_object~execute.

    DATA lt_companies TYPE STANDARD TABLE OF ztcfo_config-company_code WITH EMPTY KEY.
    DATA lv_mail      TYPE abap_bool.

    LOOP AT it_parameters INTO DATA(ls_param).
      CASE ls_param-selname.
        WHEN param-company.
          APPEND CONV ztcfo_config-company_code( ls_param-low ) TO lt_companies.
        WHEN param-mail.
          lv_mail = xsdbool( ls_param-low IS NOT INITIAL ).
      ENDCASE.
    ENDLOOP.

    LOOP AT lt_companies INTO DATA(lv_company).

      MODIFY ENTITIES OF zr_cfo_brief
        ENTITY Brief
          EXECUTE generateBrief
          FROM VALUE #( ( %cid = 'JOB' %param-CompanyCode = lv_company ) )
        RESULT DATA(lt_result)
        FAILED DATA(ls_failed)
        REPORTED DATA(ls_reported).

      LOOP AT ls_reported-brief INTO DATA(ls_msg).
        IF ls_msg-%msg IS NOT BOUND.
          CONTINUE.
        ENDIF.
        log( iv_text     = ls_msg-%msg->if_message~get_text( )
             iv_severity = COND #( WHEN ls_failed-brief IS INITIAL THEN if_bali_constants=>c_severity_status
                                   ELSE if_bali_constants=>c_severity_error ) ).
      ENDLOOP.

      IF ls_failed-brief IS NOT INITIAL OR lt_result IS INITIAL.
        ROLLBACK ENTITIES.
        CONTINUE.
      ENDIF.

      COMMIT ENTITIES
        RESPONSE OF zr_cfo_brief
        FAILED DATA(ls_commit_failed)
        REPORTED DATA(ls_commit_reported).

      IF ls_commit_failed-brief IS NOT INITIAL.
        log( iv_text = |Brief for { lv_company } could not be saved| iv_severity = if_bali_constants=>c_severity_error ).
        CONTINUE.
      ENDIF.

      IF lv_mail = abap_true.
        TRY.
            zcl_cfo_mailer=>send_brief( lt_result[ 1 ]-%param-BriefUuid ).
            " flushes the mail queue (no business data is changed)
            COMMIT ENTITIES.
            log( |Brief for { lv_company } sent| ).
          CATCH zcx_cfo_error INTO DATA(lx_error).
            log( iv_text = lx_error->text iv_severity = if_bali_constants=>c_severity_warning ).
        ENDTRY.
      ENDIF.

      CLEAR: lt_result, ls_failed, ls_reported, ls_commit_failed, ls_commit_reported.
    ENDLOOP.

  ENDMETHOD.


  METHOD log.
    " application log object ZCFO_BRIEF / subobject JOB (create in ADT, see docs/setup.md)
    TRY.
        DATA(lo_log) = cl_bali_log=>create_with_header(
                         cl_bali_header_setter=>create( object    = 'ZCFO_BRIEF'
                                                        subobject = 'JOB' ) ).
        lo_log->add_item( cl_bali_free_text_setter=>create( severity = iv_severity
                                                            text     = CONV #( iv_text ) ) ).
        cl_bali_log_db=>get_instance( )->save_log( log                        = lo_log
                                                   assign_to_current_appl_job = abap_true ).
      CATCH cx_bali_runtime.
        " logging must never break the job
    ENDTRY.
  ENDMETHOD.

ENDCLASS.

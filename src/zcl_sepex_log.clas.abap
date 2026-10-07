"! Separação Express - Application Log (objeto ZSEPEX, subobjeto EXPRESS)
"! Um log por chamada (remessa ou execução de job). Gravado no SLG1.
CLASS zcl_sepex_log DEFINITION
  PUBLIC
  FINAL
  CREATE PUBLIC.

  PUBLIC SECTION.
    METHODS constructor
      IMPORTING
        !iv_extnumber TYPE balnrext OPTIONAL.

    "! Mensagem da classe ZSEPEX
    METHODS add_msg
      IMPORTING
        !iv_msgty TYPE symsgty DEFAULT 'S'
        !iv_msgno TYPE symsgno
        !iv_msgv1 TYPE any OPTIONAL
        !iv_msgv2 TYPE any OPTIONAL
        !iv_msgv3 TYPE any OPTIONAL
        !iv_msgv4 TYPE any OPTIONAL.

    "! Mensagem a partir de SY-MSG*
    METHODS add_sy
      IMPORTING
        !iv_msgty TYPE symsgty OPTIONAL.

    "! Linha BAPIRET2
    METHODS add_bapiret
      IMPORTING
        !is_return TYPE bapiret2.

    "! Exceção ZCX_SEPEX
    METHODS add_excecao
      IMPORTING
        !ix_erro TYPE REF TO zcx_sepex.

    "! Todas as mensagens acumuladas, como BAPIRET2 (p/ T_RETURN)
    METHODS get_return
      RETURNING
        VALUE(rt_return) TYPE bapiret2_t.

    "! Grava o log no banco (SLG1)
    METHODS salvar.

  PROTECTED SECTION.
  PRIVATE SECTION.
    DATA mv_handle TYPE balloghndl.
    DATA mt_return TYPE bapiret2_t.
ENDCLASS.


CLASS zcl_sepex_log IMPLEMENTATION.

  METHOD constructor.
    DATA ls_log TYPE bal_s_log.

    ls_log-object    = zif_sepex_const=>gc_bal-object.
    ls_log-subobject = zif_sepex_const=>gc_bal-subobject.
    ls_log-aluser    = sy-uname.
    ls_log-alprog    = sy-repid.
    ls_log-extnumber = iv_extnumber.

    CALL FUNCTION 'BAL_LOG_CREATE'
      EXPORTING
        i_s_log      = ls_log
      IMPORTING
        e_log_handle = mv_handle
      EXCEPTIONS
        OTHERS       = 1.
    IF sy-subrc <> 0.
      CLEAR mv_handle.
    ENDIF.
  ENDMETHOD.

  METHOD add_msg.
    DATA: ls_msg    TYPE bal_s_msg,
          ls_return TYPE bapiret2.

    ls_msg-msgty = iv_msgty.
    ls_msg-msgid = zif_sepex_const=>gc_msgid.
    ls_msg-msgno = iv_msgno.
    IF iv_msgv1 IS SUPPLIED.
      WRITE iv_msgv1 TO ls_msg-msgv1 LEFT-JUSTIFIED.
    ENDIF.
    IF iv_msgv2 IS SUPPLIED.
      WRITE iv_msgv2 TO ls_msg-msgv2 LEFT-JUSTIFIED.
    ENDIF.
    IF iv_msgv3 IS SUPPLIED.
      WRITE iv_msgv3 TO ls_msg-msgv3 LEFT-JUSTIFIED.
    ENDIF.
    IF iv_msgv4 IS SUPPLIED.
      WRITE iv_msgv4 TO ls_msg-msgv4 LEFT-JUSTIFIED.
    ENDIF.

    ls_return-type       = ls_msg-msgty.
    ls_return-id         = ls_msg-msgid.
    ls_return-number     = ls_msg-msgno.
    ls_return-message_v1 = ls_msg-msgv1.
    ls_return-message_v2 = ls_msg-msgv2.
    ls_return-message_v3 = ls_msg-msgv3.
    ls_return-message_v4 = ls_msg-msgv4.
    MESSAGE ID ls_msg-msgid TYPE 'S' NUMBER ls_msg-msgno
      WITH ls_msg-msgv1 ls_msg-msgv2 ls_msg-msgv3 ls_msg-msgv4
      INTO ls_return-message.
    APPEND ls_return TO mt_return.

    IF mv_handle IS NOT INITIAL.
      CALL FUNCTION 'BAL_LOG_MSG_ADD'
        EXPORTING
          i_log_handle = mv_handle
          i_s_msg      = ls_msg
        EXCEPTIONS
          OTHERS       = 1.
    ENDIF.
  ENDMETHOD.

  METHOD add_sy.
    DATA ls_return TYPE bapiret2.

    ls_return-type       = iv_msgty.
    IF ls_return-type IS INITIAL.
      ls_return-type = sy-msgty.
    ENDIF.
    ls_return-id         = sy-msgid.
    ls_return-number     = sy-msgno.
    ls_return-message_v1 = sy-msgv1.
    ls_return-message_v2 = sy-msgv2.
    ls_return-message_v3 = sy-msgv3.
    ls_return-message_v4 = sy-msgv4.
    add_bapiret( ls_return ).
  ENDMETHOD.

  METHOD add_bapiret.
    DATA: ls_msg    TYPE bal_s_msg,
          ls_return TYPE bapiret2.

    ls_return = is_return.
    IF ls_return-message IS INITIAL AND ls_return-id IS NOT INITIAL.
      MESSAGE ID ls_return-id TYPE 'S' NUMBER ls_return-number
        WITH ls_return-message_v1 ls_return-message_v2
             ls_return-message_v3 ls_return-message_v4
        INTO ls_return-message.
    ENDIF.
    APPEND ls_return TO mt_return.

    CHECK mv_handle IS NOT INITIAL.
    ls_msg-msgty = ls_return-type.
    ls_msg-msgid = ls_return-id.
    ls_msg-msgno = ls_return-number.
    ls_msg-msgv1 = ls_return-message_v1.
    ls_msg-msgv2 = ls_return-message_v2.
    ls_msg-msgv3 = ls_return-message_v3.
    ls_msg-msgv4 = ls_return-message_v4.
    IF ls_msg-msgid IS INITIAL.
      " Mensagem sem T100: grava como texto livre (ZSEPEX 000)
      ls_msg-msgid = zif_sepex_const=>gc_msgid.
      ls_msg-msgno = '000'.
      ls_msg-msgv1 = ls_return-message.
    ENDIF.
    CALL FUNCTION 'BAL_LOG_MSG_ADD'
      EXPORTING
        i_log_handle = mv_handle
        i_s_msg      = ls_msg
      EXCEPTIONS
        OTHERS       = 1.
  ENDMETHOD.

  METHOD add_excecao.
    add_bapiret( ix_erro->get_bapiret( ) ).
  ENDMETHOD.

  METHOD get_return.
    rt_return = mt_return.
  ENDMETHOD.

  METHOD salvar.
    DATA lt_handle TYPE bal_t_logh.

    CHECK mv_handle IS NOT INITIAL.
    APPEND mv_handle TO lt_handle.
    CALL FUNCTION 'BAL_DB_SAVE'
      EXPORTING
        i_t_log_handle   = lt_handle
        i_save_all       = space
      EXCEPTIONS
        OTHERS           = 1.
  ENDMETHOD.

ENDCLASS.

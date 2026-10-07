"! Separação Express - exceção com T100 (classe de mensagens ZSEPEX)
CLASS zcx_sepex DEFINITION
  PUBLIC
  INHERITING FROM cx_static_check
  CREATE PUBLIC.

  PUBLIC SECTION.
    INTERFACES if_t100_message.

    DATA msgv1 TYPE symsgv READ-ONLY.
    DATA msgv2 TYPE symsgv READ-ONLY.
    DATA msgv3 TYPE symsgv READ-ONLY.
    DATA msgv4 TYPE symsgv READ-ONLY.

    METHODS constructor
      IMPORTING
        !textid   LIKE if_t100_message=>t100key OPTIONAL
        !previous LIKE previous OPTIONAL
        !msgv1    TYPE symsgv OPTIONAL
        !msgv2    TYPE symsgv OPTIONAL
        !msgv3    TYPE symsgv OPTIONAL
        !msgv4    TYPE symsgv OPTIONAL.

    "! Levanta a exceção com mensagem da classe ZSEPEX
    CLASS-METHODS raise_msg
      IMPORTING
        !iv_msgno TYPE symsgno
        !iv_msgv1 TYPE any OPTIONAL
        !iv_msgv2 TYPE any OPTIONAL
        !iv_msgv3 TYPE any OPTIONAL
        !iv_msgv4 TYPE any OPTIONAL
      RAISING
        zcx_sepex.

    "! Levanta a exceção a partir de SY-MSGID/MSGNO/MSGV*
    CLASS-METHODS raise_sy
      RAISING
        zcx_sepex.

    "! Levanta a exceção com a primeira mensagem E/A/X de uma BAPIRET2
    CLASS-METHODS raise_from_bapiret
      IMPORTING
        !it_return       TYPE bapiret2_t
        !iv_msgno_padrao TYPE symsgno DEFAULT '000'
      RAISING
        zcx_sepex.

    "! Texto formatado da mensagem
    METHODS get_texto
      RETURNING
        VALUE(rv_texto) TYPE bapi_msg.

    "! Converte a exceção em linha BAPIRET2 (padrão T_RETURN do engine)
    METHODS get_bapiret
      RETURNING
        VALUE(rs_return) TYPE bapiret2.

  PROTECTED SECTION.
  PRIVATE SECTION.
ENDCLASS.


CLASS zcx_sepex IMPLEMENTATION.

  METHOD constructor ##ADT_SUPPRESS_GENERATION.
    super->constructor( previous = previous ).
    me->msgv1 = msgv1.
    me->msgv2 = msgv2.
    me->msgv3 = msgv3.
    me->msgv4 = msgv4.
    CLEAR me->textid.
    IF textid IS INITIAL.
      if_t100_message~t100key = if_t100_message=>default_textid.
    ELSE.
      if_t100_message~t100key = textid.
    ENDIF.
  ENDMETHOD.

  METHOD raise_msg.
    DATA: ls_t100key TYPE scx_t100key,
          lv_msgv1   TYPE symsgv,
          lv_msgv2   TYPE symsgv,
          lv_msgv3   TYPE symsgv,
          lv_msgv4   TYPE symsgv.

    ls_t100key-msgid = zif_sepex_const=>gc_msgid.
    ls_t100key-msgno = iv_msgno.
    ls_t100key-attr1 = 'MSGV1'.
    ls_t100key-attr2 = 'MSGV2'.
    ls_t100key-attr3 = 'MSGV3'.
    ls_t100key-attr4 = 'MSGV4'.

    IF iv_msgv1 IS SUPPLIED.
      WRITE iv_msgv1 TO lv_msgv1 LEFT-JUSTIFIED.
    ENDIF.
    IF iv_msgv2 IS SUPPLIED.
      WRITE iv_msgv2 TO lv_msgv2 LEFT-JUSTIFIED.
    ENDIF.
    IF iv_msgv3 IS SUPPLIED.
      WRITE iv_msgv3 TO lv_msgv3 LEFT-JUSTIFIED.
    ENDIF.
    IF iv_msgv4 IS SUPPLIED.
      WRITE iv_msgv4 TO lv_msgv4 LEFT-JUSTIFIED.
    ENDIF.

    RAISE EXCEPTION TYPE zcx_sepex
      EXPORTING
        textid = ls_t100key
        msgv1  = lv_msgv1
        msgv2  = lv_msgv2
        msgv3  = lv_msgv3
        msgv4  = lv_msgv4.
  ENDMETHOD.

  METHOD raise_sy.
    DATA ls_t100key TYPE scx_t100key.

    ls_t100key-msgid = sy-msgid.
    ls_t100key-msgno = sy-msgno.
    ls_t100key-attr1 = 'MSGV1'.
    ls_t100key-attr2 = 'MSGV2'.
    ls_t100key-attr3 = 'MSGV3'.
    ls_t100key-attr4 = 'MSGV4'.

    RAISE EXCEPTION TYPE zcx_sepex
      EXPORTING
        textid = ls_t100key
        msgv1  = sy-msgv1
        msgv2  = sy-msgv2
        msgv3  = sy-msgv3
        msgv4  = sy-msgv4.
  ENDMETHOD.

  METHOD raise_from_bapiret.
    DATA: ls_return  TYPE bapiret2,
          ls_t100key TYPE scx_t100key,
          lv_achou   TYPE xfeld.

    LOOP AT it_return INTO ls_return.
      IF ls_return-type CA 'EAX'.
        lv_achou = 'X'.
        EXIT.
      ENDIF.
    ENDLOOP.

    IF lv_achou = 'X' AND ls_return-id IS NOT INITIAL.
      ls_t100key-msgid = ls_return-id.
      ls_t100key-msgno = ls_return-number.
      ls_t100key-attr1 = 'MSGV1'.
      ls_t100key-attr2 = 'MSGV2'.
      ls_t100key-attr3 = 'MSGV3'.
      ls_t100key-attr4 = 'MSGV4'.
      RAISE EXCEPTION TYPE zcx_sepex
        EXPORTING
          textid = ls_t100key
          msgv1  = ls_return-message_v1
          msgv2  = ls_return-message_v2
          msgv3  = ls_return-message_v3
          msgv4  = ls_return-message_v4.
    ELSE.
      raise_msg( iv_msgno = iv_msgno_padrao
                 iv_msgv1 = ls_return-message ).
    ENDIF.
  ENDMETHOD.

  METHOD get_texto.
    DATA lv_texto TYPE string.

    MESSAGE ID if_t100_message~t100key-msgid
            TYPE 'S'
            NUMBER if_t100_message~t100key-msgno
            WITH msgv1 msgv2 msgv3 msgv4
            INTO lv_texto.
    rv_texto = lv_texto.
  ENDMETHOD.

  METHOD get_bapiret.
    rs_return-type       = 'E'.
    rs_return-id         = if_t100_message~t100key-msgid.
    rs_return-number     = if_t100_message~t100key-msgno.
    rs_return-message_v1 = msgv1.
    rs_return-message_v2 = msgv2.
    rs_return-message_v3 = msgv3.
    rs_return-message_v4 = msgv4.
    rs_return-message    = get_texto( ).
  ENDMETHOD.

ENDCLASS.

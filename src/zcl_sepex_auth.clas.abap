"! Separação Express - verificação do objeto de autorização ZSEPEX_AUT
CLASS zcl_sepex_auth DEFINITION
  PUBLIC
  FINAL
  CREATE PUBLIC.

  PUBLIC SECTION.
    "! Levanta ZSEPEX 016 quando o usuário não tem a atividade no depósito
    CLASS-METHODS verificar
      IMPORTING
        !iv_actvt TYPE activ_auth
        !iv_lgnum TYPE lgnum
      RAISING
        zcx_sepex.

    "! Versão sem exceção (para habilitar botões)
    CLASS-METHODS tem_autorizacao
      IMPORTING
        !iv_actvt     TYPE activ_auth
        !iv_lgnum     TYPE lgnum
      RETURNING
        VALUE(rv_ok)  TYPE xfeld.

  PROTECTED SECTION.
  PRIVATE SECTION.
ENDCLASS.


CLASS zcl_sepex_auth IMPLEMENTATION.

  METHOD tem_autorizacao.
    AUTHORITY-CHECK OBJECT 'ZSEPEX_AUT'
      ID 'ACTVT' FIELD iv_actvt
      ID 'LGNUM' FIELD iv_lgnum.
    IF sy-subrc = 0.
      rv_ok = 'X'.
    ENDIF.
  ENDMETHOD.

  METHOD verificar.
    IF tem_autorizacao( iv_actvt = iv_actvt iv_lgnum = iv_lgnum ) = space.
      zcx_sepex=>raise_msg( iv_msgno = '016'
                            iv_msgv1 = iv_actvt
                            iv_msgv2 = iv_lgnum ).
    ENDIF.
  ENDMETHOD.

ENDCLASS.

*&---------------------------------------------------------------------*
*& Report ZSEPEX_R_SINCRONIZAR  (transação ZSEPEX04)
*&---------------------------------------------------------------------*
*& Separação Express - job de sincronização (SM36, a cada 30 min):
*&  - OTs de regularização confirmadas/estornadas (LTAP) -> itens
*&  - saída de mercadoria da remessa (VBUK) -> data PGI / cancelamento
*&  - fecha o processo quando todos os itens foram regularizados
*&  - (P_CRIAOT) tenta criar a OT de regularização dos itens ainda sem
*&    OT, p.ex. depois que o reabastecimento do avulso foi confirmado
*& Protocolo no spool; detalhes no SLG1 (objeto ZSEPEX).
*&---------------------------------------------------------------------*
REPORT zsepex_r_sincronizar MESSAGE-ID zsepex.

TABLES: zsepex_t_cab.

SELECTION-SCREEN BEGIN OF BLOCK b1 WITH FRAME TITLE TEXT-001.
PARAMETERS:     p_lgnum TYPE lgnum.
SELECT-OPTIONS: s_vbeln FOR zsepex_t_cab-vbeln.
SELECTION-SCREEN END OF BLOCK b1.
SELECTION-SCREEN BEGIN OF BLOCK b2 WITH FRAME TITLE TEXT-002.
PARAMETERS: p_criaot AS CHECKBOX DEFAULT 'X'.
SELECTION-SCREEN END OF BLOCK b2.

START-OF-SELECTION.
  PERFORM f_executar.

*&---------------------------------------------------------------------*
FORM f_executar.
  DATA: lo_log    TYPE REF TO zcl_sepex_log,
        lx_erro   TYPE REF TO zcx_sepex,
        lt_cab    TYPE zsepex_t_cab_tt,
        ls_cab    TYPE zsepex_t_cab,
        lt_return TYPE bapiret2_t,
        ls_return TYPE bapiret2,
        lr_status TYPE RANGE OF zsepex_status,
        ls_rst    LIKE LINE OF lr_status,
        lv_proc   TYPE i,
        lv_conc   TYPE i,
        lv_status TYPE zsepex_status.

  DATA lv_ext TYPE balnrext.
  lv_ext = 'SINCRONIZACAO'.
  CREATE OBJECT lo_log EXPORTING iv_extnumber = lv_ext.

  IF s_vbeln[] IS INITIAL.
    zcl_sepex_sinc=>sincronizar_todos( EXPORTING iv_lgnum       = p_lgnum
                                                 io_log         = lo_log
                                       IMPORTING ev_processados = lv_proc
                                                 ev_concluidos  = lv_conc ).
  ELSE.
    ls_rst-sign = 'I'. ls_rst-option = 'BT'.
    ls_rst-low  = zif_sepex_const=>gc_status-virtual.
    ls_rst-high = zif_sepex_const=>gc_status-em_regul.
    APPEND ls_rst TO lr_status.
    lt_cab = zcl_sepex_controle=>ler_cabs_por_status( iv_lgnum  = p_lgnum
                                                     it_status = lr_status ).
    DELETE lt_cab WHERE vbeln NOT IN s_vbeln.
    LOOP AT lt_cab INTO ls_cab.
      TRY.
          lv_status = zcl_sepex_sinc=>sincronizar_remessa( iv_lgnum = ls_cab-lgnum
                                                           iv_vbeln = ls_cab-vbeln
                                                           io_log   = lo_log ).
          lv_proc = lv_proc + 1.
          IF lv_status = zif_sepex_const=>gc_status-concluido.
            lv_conc = lv_conc + 1.
          ENDIF.
        CATCH zcx_sepex INTO lx_erro.
          lo_log->add_excecao( lx_erro ).
      ENDTRY.
    ENDLOOP.
  ENDIF.

  IF lv_proc = 0.
    lo_log->add_msg( iv_msgty = 'I' iv_msgno = '029' ).
  ELSE.
    lo_log->add_msg( iv_msgno = '030' iv_msgv1 = lv_proc iv_msgv2 = lv_conc ).
  ENDIF.

  IF p_criaot = 'X'.
    PERFORM f_criar_ots_pendentes USING lo_log.
  ENDIF.
  lo_log->salvar( ).

  " Protocolo (spool / tela)
  lt_return = lo_log->get_return( ).
  LOOP AT lt_return INTO ls_return.
    WRITE: / ls_return-type, ls_return-message.
  ENDLOOP.
ENDFORM.

*&---------------------------------------------------------------------*
*& Itens pendentes sem OT de regularização: tenta criar a OT (mesma
*& função da ZSEPEX02). Reabastecimento do avulso conforme ZSEPEX_T_PAR.
*&---------------------------------------------------------------------*
FORM f_criar_ots_pendentes USING po_log TYPE REF TO zcl_sepex_log.
  DATA: lt_cab    TYPE zsepex_t_cab_tt,
        ls_cab    TYPE zsepex_t_cab,
        lt_itm    TYPE zsepex_t_itm_tt,
        ls_itm    TYPE zsepex_t_itm,
        lt_ot     TYPE zsepex_t_ot_tt,
        lr_status TYPE RANGE OF zsepex_status,
        ls_rst    LIKE LINE OF lr_status,
        lt_return TYPE STANDARD TABLE OF bapiret2,
        ls_return TYPE bapiret2,
        lv_tanum  TYPE tanum,
        lv_ok     TYPE int4,
        lv_pend   TYPE int4,
        lv_tem    TYPE xfeld,
        lv_criadas TYPE i,
        lv_erros   TYPE i.

  ls_rst-sign = 'I'. ls_rst-option = 'BT'.
  ls_rst-low  = zif_sepex_const=>gc_status-virtual.
  ls_rst-high = zif_sepex_const=>gc_status-em_regul.
  APPEND ls_rst TO lr_status.
  lt_cab = zcl_sepex_controle=>ler_cabs_por_status( iv_lgnum  = p_lgnum
                                                   it_status = lr_status ).
  IF s_vbeln[] IS NOT INITIAL.
    DELETE lt_cab WHERE vbeln NOT IN s_vbeln.
  ENDIF.

  LOOP AT lt_cab INTO ls_cab.
    " Só chama a criação quando há item com saldo fora de OT aberta
    lt_itm = zcl_sepex_controle=>ler_itens( iv_lgnum = ls_cab-lgnum iv_vbeln = ls_cab-vbeln ).
    lt_ot  = zcl_sepex_controle=>ler_ots( iv_lgnum = ls_cab-lgnum iv_vbeln = ls_cab-vbeln ).
    CLEAR lv_tem.
    LOOP AT lt_itm INTO ls_itm WHERE status < zif_sepex_const=>gc_status-concluido.
      IF zcl_sepex_controle=>qtd_pendente_item( is_itm = ls_itm it_ot = lt_ot ) > 0.
        lv_tem = 'X'.
        EXIT.
      ENDIF.
    ENDLOOP.
    IF lv_tem = space.
      CONTINUE.
    ENDIF.

    CLEAR: lt_return, lv_tanum, lv_ok, lv_pend.
    CALL FUNCTION 'ZSEPEX_CRIA_OT_REGUL'
      EXPORTING
        i_lgnum      = ls_cab-lgnum
        i_vbeln      = ls_cab-vbeln
      IMPORTING
        e_tanum      = lv_tanum
        e_itens_ok   = lv_ok
        e_itens_pend = lv_pend
      TABLES
        t_return     = lt_return
      EXCEPTIONS
        e_erro       = 1
        OTHERS       = 2.
    IF sy-subrc <> 0.
      lv_erros = lv_erros + 1.
    ELSEIF lv_tanum IS NOT INITIAL.
      lv_criadas = lv_criadas + 1.
    ENDIF.
    LOOP AT lt_return INTO ls_return.
      po_log->add_bapiret( ls_return ).
    ENDLOOP.
  ENDLOOP.

  IF lv_criadas > 0 OR lv_erros > 0.
    po_log->add_msg( iv_msgno = '022' iv_msgv1 = lv_criadas iv_msgv2 = lv_erros ).
  ENDIF.
ENDFORM.

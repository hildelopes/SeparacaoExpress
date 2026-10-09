*&---------------------------------------------------------------------*
*& Report ZSEPEX_R_SINCRONIZAR  (transação ZSEPEX04)
*&---------------------------------------------------------------------*
*& Separação Express - job de sincronização (SM36, a cada 30 min):
*&  - OTs de regularização confirmadas/estornadas (LTAP) -> itens
*&  - saída de mercadoria da remessa (VBUK) -> data PGI / cancelamento
*&  - fecha o processo quando todos os itens foram regularizados
*& Protocolo no spool; detalhes no SLG1 (objeto ZSEPEX).
*&---------------------------------------------------------------------*
REPORT zsepex_r_sincronizar MESSAGE-ID zsepex.

TABLES: zsepex_t_cab.

SELECTION-SCREEN BEGIN OF BLOCK b1 WITH FRAME TITLE TEXT-001.
PARAMETERS:     p_lgnum TYPE lgnum.
SELECT-OPTIONS: s_vbeln FOR zsepex_t_cab-vbeln.
SELECTION-SCREEN END OF BLOCK b1.

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
  lo_log->salvar( ).

  " Protocolo (spool / tela)
  lt_return = lo_log->get_return( ).
  LOOP AT lt_return INTO ls_return.
    WRITE: / ls_return-type, ls_return-message.
  ENDLOOP.
ENDFORM.

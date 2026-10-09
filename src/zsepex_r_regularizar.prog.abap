*&---------------------------------------------------------------------*
*& Report ZSEPEX_R_REGULARIZAR  (transação ZSEPEX02)
*&---------------------------------------------------------------------*
*& Separação Express - regularização física:
*&  - Exibir: itens com saldo pendente de regularização, por carga/
*&    remessa/material/lote, com a OT de regularização aberta (se houver)
*&  - Criar OTs: para as remessas selecionadas, cria a OT de regularização
*&    (bins -> posição virtual) para o saldo ainda sem OT - usado quando a
*&    criação imediata não cobriu tudo ou após diferença no RF
*&  - Sincronizar: lê LTAP/VBUK e atualiza status (igual ao job ZSEPEX04)
*& Modo teste: seleciona as UDs e mostra, sem criar OT.
*&---------------------------------------------------------------------*
REPORT zsepex_r_regularizar MESSAGE-ID zsepex.

TABLES: zsepex_t_cab, zsepex_t_itm.

TYPES: BEGIN OF ty_saida,
         origem     TYPE zsepex_origem,
         tknum      TYPE tknum,
         vbeln      TYPE vbeln_vl,
         posnr      TYPE posnr_vl,
         werks      TYPE werks_d,
         matnr      TYPE matnr,
         maktx      TYPE maktx,
         charg      TYPE charg_d,
         menge      TYPE zsepex_qtd,
         qtd_regul  TYPE zsepex_qtd,
         qtd_em_ot  TYPE zsepex_qtd,
         qtd_pend   TYPE zsepex_qtd,
         meins      TYPE meins,
         tanum      TYPE tanum,
         lenum      TYPE lenum,
         status     TYPE zsepex_status,
         status_txt TYPE val_text,
         dt_virt    TYPE datum,
         dias       TYPE i,
         msg        TYPE bapi_msg,
       END OF ty_saida.
DATA: gt_saida TYPE STANDARD TABLE OF ty_saida.

SELECTION-SCREEN BEGIN OF BLOCK b1 WITH FRAME TITLE TEXT-001.
PARAMETERS:     p_lgnum  TYPE lgnum OBLIGATORY.
SELECT-OPTIONS: s_tknum  FOR zsepex_t_cab-tknum,
                s_vbeln  FOR zsepex_t_cab-vbeln,
                s_status FOR zsepex_t_cab-status,
                s_matnr  FOR zsepex_t_itm-matnr.
SELECTION-SCREEN END OF BLOCK b1.
SELECTION-SCREEN BEGIN OF BLOCK b2 WITH FRAME TITLE TEXT-002.
PARAMETERS: p_exibir RADIOBUTTON GROUP acao DEFAULT 'X',
            p_criar  RADIOBUTTON GROUP acao,
            p_sinc   RADIOBUTTON GROUP acao.
SELECTION-SCREEN END OF BLOCK b2.
SELECTION-SCREEN BEGIN OF BLOCK b3 WITH FRAME TITLE TEXT-003.
PARAMETERS: p_teste AS CHECKBOX.
SELECTION-SCREEN END OF BLOCK b3.

START-OF-SELECTION.
  PERFORM f_executar.

*&---------------------------------------------------------------------*
FORM f_executar.
  DATA: lx_erro TYPE REF TO zcx_sepex,
        lv_actvt TYPE activ_auth.

  IF p_exibir = 'X'.
    lv_actvt = zif_sepex_const=>gc_actvt-exibir.
  ELSE.
    lv_actvt = zif_sepex_const=>gc_actvt-regularizar.
  ENDIF.
  TRY.
      zcl_sepex_auth=>verificar( iv_actvt = lv_actvt iv_lgnum = p_lgnum ).
    CATCH zcx_sepex INTO lx_erro.
      DATA lv_texto TYPE bapi_msg.
      lv_texto = lx_erro->get_texto( ).
      MESSAGE lv_texto TYPE 'S' DISPLAY LIKE 'E'.
      RETURN.
  ENDTRY.

  CASE 'X'.
    WHEN p_criar.
      PERFORM f_criar_ots.
    WHEN p_sinc.
      PERFORM f_sincronizar.
  ENDCASE.

  PERFORM f_montar_saida.
  PERFORM f_exibir_alv.
ENDFORM.

*&---------------------------------------------------------------------*
FORM f_ler_cabs CHANGING ct_cab TYPE zsepex_t_cab_tt.
  DATA: lr_status TYPE RANGE OF zsepex_status,
        ls_rst    LIKE LINE OF lr_status.

  IF s_status[] IS INITIAL.
    ls_rst-sign = 'I'. ls_rst-option = 'BT'.
    ls_rst-low  = zif_sepex_const=>gc_status-registrado.
    ls_rst-high = zif_sepex_const=>gc_status-em_regul.
    APPEND ls_rst TO lr_status.
  ELSE.
    lr_status = s_status[].
  ENDIF.
  ct_cab = zcl_sepex_controle=>ler_cabs_por_status( iv_lgnum  = p_lgnum
                                                   it_status = lr_status
                                                   it_tknum  = s_tknum[] ).
  DELETE ct_cab WHERE vbeln NOT IN s_vbeln.
ENDFORM.

*&---------------------------------------------------------------------*
FORM f_criar_ots.
  DATA: lt_cab    TYPE zsepex_t_cab_tt,
        ls_cab    TYPE zsepex_t_cab,
        lt_return TYPE STANDARD TABLE OF bapiret2,
        ls_return TYPE bapiret2,
        lt_ud     TYPE STANDARD TABLE OF zsepex_s_ud,
        ls_ud     TYPE zsepex_s_ud,
        lv_tanum  TYPE tanum,
        lv_ok     TYPE i,
        lv_erro   TYPE i,
        ls_saida  TYPE ty_saida.

  PERFORM f_ler_cabs CHANGING lt_cab.
  IF lt_cab IS INITIAL.
    MESSAGE s021.
    RETURN.
  ENDIF.

  LOOP AT lt_cab INTO ls_cab.
    CLEAR: lt_return, lt_ud, lv_tanum.
    CALL FUNCTION 'ZSEPEX_CRIA_OT_REGUL'
      EXPORTING
        i_lgnum  = p_lgnum
        i_vbeln  = ls_cab-vbeln
        i_teste  = p_teste
      IMPORTING
        e_tanum  = lv_tanum
      TABLES
        t_return = lt_return
        t_ud     = lt_ud
      EXCEPTIONS
        e_erro   = 1
        OTHERS   = 2.
    IF sy-subrc <> 0.
      lv_erro = lv_erro + 1.
    ELSEIF lv_tanum IS NOT INITIAL OR p_teste = 'X'.
      lv_ok = lv_ok + 1.
    ENDIF.
    " Em modo teste, mostra as UDs que seriam usadas
    IF p_teste = 'X'.
      LOOP AT lt_ud INTO ls_ud.
        CLEAR ls_saida.
        ls_saida-origem = ls_cab-origem.
        ls_saida-tknum  = ls_cab-tknum.
        ls_saida-vbeln  = ls_cab-vbeln.
        ls_saida-matnr  = ls_ud-matnr.
        ls_saida-charg  = ls_ud-charg.
        ls_saida-menge  = ls_ud-menge.
        ls_saida-meins  = ls_ud-meins.
        ls_saida-lenum  = ls_ud-lenum.
        ls_saida-msg    = |UD { ls_ud-lenum } { ls_ud-lgtyp }/{ ls_ud-lgpla } (teste)|.
        APPEND ls_saida TO gt_saida.
      ENDLOOP.
    ENDIF.
    LOOP AT lt_return INTO ls_return WHERE type CA 'EAXW'.
      CLEAR ls_saida.
      ls_saida-origem = ls_cab-origem.
      ls_saida-tknum  = ls_cab-tknum.
      ls_saida-vbeln  = ls_cab-vbeln.
      ls_saida-msg    = ls_return-message.
      APPEND ls_saida TO gt_saida.
    ENDLOOP.
  ENDLOOP.
  MESSAGE s022 WITH lv_ok lv_erro.
ENDFORM.

*&---------------------------------------------------------------------*
FORM f_sincronizar.
  DATA: lo_log  TYPE REF TO zcl_sepex_log,
        lx_erro TYPE REF TO zcx_sepex,
        lt_cab  TYPE zsepex_t_cab_tt,
        ls_cab  TYPE zsepex_t_cab.

  DATA lv_ext TYPE balnrext.
  lv_ext = 'ZSEPEX02'.
  CREATE OBJECT lo_log EXPORTING iv_extnumber = lv_ext.
  PERFORM f_ler_cabs CHANGING lt_cab.
  LOOP AT lt_cab INTO ls_cab.
    TRY.
        zcl_sepex_sinc=>sincronizar_remessa( iv_lgnum = ls_cab-lgnum
                                             iv_vbeln = ls_cab-vbeln
                                             io_log   = lo_log ).
      CATCH zcx_sepex INTO lx_erro.
        lo_log->add_excecao( lx_erro ).
    ENDTRY.
  ENDLOOP.
  lo_log->salvar( ).
  DATA lv_qtd TYPE i.
  lv_qtd = lines( lt_cab ).
  MESSAGE s030 WITH lv_qtd 0.
ENDFORM.

*&---------------------------------------------------------------------*
FORM f_montar_saida.
  DATA: lt_cab   TYPE zsepex_t_cab_tt,
        ls_cab   TYPE zsepex_t_cab,
        lt_itm   TYPE zsepex_t_itm_tt,
        ls_itm   TYPE zsepex_t_itm,
        lt_ot    TYPE zsepex_t_ot_tt,
        ls_ot    TYPE zsepex_t_ot,
        ls_saida TYPE ty_saida,
        lt_saida_msg LIKE gt_saida.

  " Mensagens já acumuladas pelas ações ficam no fim
  lt_saida_msg = gt_saida.
  CLEAR gt_saida.

  PERFORM f_ler_cabs CHANGING lt_cab.
  LOOP AT lt_cab INTO ls_cab.
    lt_itm = zcl_sepex_controle=>ler_itens( iv_lgnum = ls_cab-lgnum iv_vbeln = ls_cab-vbeln ).
    lt_ot  = zcl_sepex_controle=>ler_ots( iv_lgnum = ls_cab-lgnum iv_vbeln = ls_cab-vbeln ).
    DELETE lt_itm WHERE matnr NOT IN s_matnr.
    LOOP AT lt_itm INTO ls_itm.
      CLEAR ls_saida.
      MOVE-CORRESPONDING ls_itm TO ls_saida.
      ls_saida-origem  = ls_cab-origem.
      ls_saida-tknum   = ls_cab-tknum.
      ls_saida-dt_virt = ls_cab-dt_virt.
      IF ls_cab-dt_virt IS NOT INITIAL.
        ls_saida-dias = sy-datum - ls_cab-dt_virt.
      ENDIF.
      LOOP AT lt_ot INTO ls_ot WHERE vbeln = ls_itm-vbeln AND posnr = ls_itm-posnr
                                 AND pquit = space.
        ls_saida-qtd_em_ot = ls_saida-qtd_em_ot + ls_ot-vsolm.
        ls_saida-tanum = ls_ot-tanum.
        ls_saida-lenum = ls_ot-vlenr.
      ENDLOOP.
      ls_saida-qtd_pend = ls_itm-menge - ls_itm-qtd_regul - ls_saida-qtd_em_ot.
      IF ls_saida-qtd_pend < 0.
        ls_saida-qtd_pend = 0.
      ENDIF.
      ls_saida-status_txt = zcl_sepex_controle=>texto_status( ls_itm-status ).
      SELECT SINGLE maktx FROM makt INTO ls_saida-maktx
        WHERE matnr = ls_itm-matnr AND spras = sy-langu.
      APPEND ls_saida TO gt_saida.
    ENDLOOP.
  ENDLOOP.
  APPEND LINES OF lt_saida_msg TO gt_saida.
ENDFORM.

*&---------------------------------------------------------------------*
FORM f_exibir_alv.
  DATA: lo_alv     TYPE REF TO cl_salv_table,
        lo_cols    TYPE REF TO cl_salv_columns_table,
        lo_col     TYPE REF TO cl_salv_column_table,
        lo_funcs   TYPE REF TO cl_salv_functions_list,
        lx_salv    TYPE REF TO cx_salv_error,
        lx_nf      TYPE REF TO cx_salv_not_found.

  IF gt_saida IS INITIAL.
    MESSAGE s021.
    RETURN.
  ENDIF.

  TRY.
      cl_salv_table=>factory( IMPORTING r_salv_table = lo_alv
                              CHANGING  t_table      = gt_saida ).
      lo_funcs = lo_alv->get_functions( ).
      lo_funcs->set_all( abap_true ).
      lo_cols = lo_alv->get_columns( ).
      lo_cols->set_optimize( abap_true ).
      TRY.
          lo_col ?= lo_cols->get_column( 'QTD_EM_OT' ).
          lo_col->set_short_text( 'Em OT' ).
          lo_col->set_medium_text( 'Qtd em OT aberta' ).
          lo_col->set_long_text( 'Quantidade em OT de regularização aberta' ).
          lo_col ?= lo_cols->get_column( 'QTD_PEND' ).
          lo_col->set_short_text( 'Pendente' ).
          lo_col->set_medium_text( 'Qtd pendente' ).
          lo_col->set_long_text( 'Quantidade pendente sem OT' ).
          lo_col ?= lo_cols->get_column( 'STATUS_TXT' ).
          lo_col->set_short_text( 'Status' ).
          lo_col->set_medium_text( 'Status Express' ).
          lo_col->set_long_text( 'Status Separação Express' ).
          lo_col ?= lo_cols->get_column( 'DIAS' ).
          lo_col->set_short_text( 'Dias' ).
          lo_col->set_medium_text( 'Dias em aberto' ).
          lo_col->set_long_text( 'Dias desde a separação virtual' ).
          lo_col ?= lo_cols->get_column( 'MSG' ).
          lo_col->set_short_text( 'Mensagem' ).
          lo_col->set_medium_text( 'Mensagem' ).
          lo_col->set_long_text( 'Mensagem da ação' ).
          lo_col ?= lo_cols->get_column( 'LENUM' ).
          lo_col->set_short_text( 'UD' ).
          lo_col->set_medium_text( 'UD da OT' ).
          lo_col->set_long_text( 'UD de origem da OT de regularização' ).
        CATCH cx_salv_not_found INTO lx_nf.
      ENDTRY.
      lo_alv->display( ).
    CATCH cx_salv_error INTO lx_salv.
      MESSAGE lx_salv TYPE 'S' DISPLAY LIKE 'E'.
  ENDTRY.
ENDFORM.

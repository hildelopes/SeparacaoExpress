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
*&  - Botão Portão/Zona (ALV): define portão e zona de expedição para as
*&    remessas selecionadas: cabeçalho Express, remessa (só sem saída) e
*&    OTs de regularização abertas (LTAK-LGTOR/LGBZO + fila RF do portão)
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
         lgtor      TYPE lgtor,
         lgbzo      TYPE lgbzo,
         queue      TYPE lrf_queue,
         status     TYPE zsepex_status,
         status_txt TYPE val_text,
         dt_virt    TYPE datum,
         dias       TYPE i,
         msg        TYPE bapi_msg,
       END OF ty_saida.
DATA: gt_saida TYPE STANDARD TABLE OF ty_saida,
      go_alv   TYPE REF TO cl_salv_table.

*----------------------------------------------------------------------*
* Botões do ALV (Portão/Zona)
*----------------------------------------------------------------------*
CLASS lcl_handler DEFINITION.
  PUBLIC SECTION.
    METHODS on_added_function FOR EVENT added_function OF cl_salv_events
      IMPORTING e_salv_function.
ENDCLASS.

CLASS lcl_handler IMPLEMENTATION.
  METHOD on_added_function.
    CASE e_salv_function.
      WHEN 'PORTAO'.
        PERFORM f_portao_zona.
    ENDCASE.
  ENDMETHOD.
ENDCLASS.

DATA: go_handler TYPE REF TO lcl_handler.

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
        lv_lgtor TYPE lgtor,
        lv_lgbzo TYPE lgbzo,
        lt_saida_msg LIKE gt_saida.

  " Mensagens já acumuladas pelas ações ficam no fim
  lt_saida_msg = gt_saida.
  CLEAR gt_saida.

  PERFORM f_ler_cabs CHANGING lt_cab.
  LOOP AT lt_cab INTO ls_cab.
    lt_itm = zcl_sepex_controle=>ler_itens( iv_lgnum = ls_cab-lgnum iv_vbeln = ls_cab-vbeln ).
    lt_ot  = zcl_sepex_controle=>ler_ots( iv_lgnum = ls_cab-lgnum iv_vbeln = ls_cab-vbeln ).
    DELETE lt_itm WHERE matnr NOT IN s_matnr.
    " Portão/zona: cabeçalho Express; registros antigos caem na remessa
    lv_lgtor = ls_cab-lgtor.
    lv_lgbzo = ls_cab-lgbzo.
    IF lv_lgtor IS INITIAL.
      zcl_sepex_wm=>ler_portao_remessa( EXPORTING iv_vbeln = ls_cab-vbeln
                                        IMPORTING ev_lgtor = lv_lgtor
                                                  ev_lgbzo = lv_lgbzo ).
    ENDIF.
    LOOP AT lt_itm INTO ls_itm.
      CLEAR ls_saida.
      MOVE-CORRESPONDING ls_itm TO ls_saida.
      ls_saida-origem  = ls_cab-origem.
      ls_saida-tknum   = ls_cab-tknum.
      ls_saida-dt_virt = ls_cab-dt_virt.
      ls_saida-lgtor   = lv_lgtor.
      ls_saida-lgbzo   = lv_lgbzo.
      IF ls_cab-dt_virt IS NOT INITIAL.
        ls_saida-dias = sy-datum - ls_cab-dt_virt.
      ENDIF.
      LOOP AT lt_ot INTO ls_ot WHERE vbeln = ls_itm-vbeln AND posnr = ls_itm-posnr
                                 AND pquit = space.
        ls_saida-qtd_em_ot = ls_saida-qtd_em_ot + ls_ot-vsolm.
        ls_saida-tanum = ls_ot-tanum.
        ls_saida-lenum = ls_ot-vlenr.
      ENDLOOP.
      IF ls_saida-tanum IS NOT INITIAL.
        SELECT SINGLE queue FROM ltak INTO ls_saida-queue
          WHERE lgnum = ls_cab-lgnum AND tanum = ls_saida-tanum.
      ENDIF.
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
  DATA: lo_cols    TYPE REF TO cl_salv_columns_table,
        lo_col     TYPE REF TO cl_salv_column_table,
        lo_funcs   TYPE REF TO cl_salv_functions_list,
        lo_sel     TYPE REF TO cl_salv_selections,
        lo_events  TYPE REF TO cl_salv_events_table,
        lx_salv    TYPE REF TO cx_salv_error,
        lx_nf      TYPE REF TO cx_salv_not_found.

  IF gt_saida IS INITIAL.
    MESSAGE s021.
    RETURN.
  ENDIF.

  TRY.
      " No container padrão da tela de lista (e não em tela cheia), para o
      " ALV aceitar o botão próprio (ADD_FUNCTION); por isso o WRITE no fim
      cl_salv_table=>factory( EXPORTING r_container  = cl_gui_container=>default_screen
                              IMPORTING r_salv_table = go_alv
                              CHANGING  t_table      = gt_saida ).
      lo_funcs = go_alv->get_functions( ).
      lo_funcs->set_all( abap_true ).
      lo_funcs->add_function( name     = 'PORTAO'
                              icon     = '@3P@'
                              text     = 'Portão/Zona'
                              tooltip  = 'Definir portão e zona de expedição (remessa e OTs de regularização)'
                              position = if_salv_c_function_position=>right_of_salv_functions ).
      lo_sel = go_alv->get_selections( ).
      lo_sel->set_selection_mode( if_salv_c_selection_mode=>row_column ).
      lo_events = go_alv->get_event( ).
      CREATE OBJECT go_handler.
      SET HANDLER go_handler->on_added_function FOR lo_events.
      lo_cols = go_alv->get_columns( ).
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
          lo_col ?= lo_cols->get_column( 'LGTOR' ).
          lo_col->set_short_text( 'Portão' ).
          lo_col->set_medium_text( 'Portão' ).
          lo_col->set_long_text( 'Portão de expedição' ).
          lo_col ?= lo_cols->get_column( 'LGBZO' ).
          lo_col->set_short_text( 'Zona' ).
          lo_col->set_medium_text( 'Zona' ).
          lo_col->set_long_text( 'Zona de disponibilização' ).
          lo_col ?= lo_cols->get_column( 'QUEUE' ).
          lo_col->set_short_text( 'Fila RF' ).
          lo_col->set_medium_text( 'Fila RF' ).
          lo_col->set_long_text( 'Fila RF da OT de regularização' ).
        CATCH cx_salv_not_found INTO lx_nf.
      ENDTRY.
      go_alv->display( ).
    CATCH cx_salv_error INTO lx_salv.
      MESSAGE lx_salv TYPE 'S' DISPLAY LIKE 'E'.
      RETURN.
  ENDTRY.
  " Tela de lista que hospeda o DEFAULT_SCREEN
  WRITE space.
ENDFORM.

*&---------------------------------------------------------------------*
*&      Form  F_PORTAO_ZONA  (botão do ALV)
*&---------------------------------------------------------------------*
*  Portão/zona para as remessas das linhas selecionadas: pergunta no
*  popup (padrão = 1ª linha), valida em T30B/T30C e aplica por remessa
*----------------------------------------------------------------------*
FORM f_portao_zona.
  DATA: lo_sel    TYPE REF TO cl_salv_selections,
        lt_rows   TYPE salv_t_row,
        lv_row    TYPE i,
        ls_saida  TYPE ty_saida,
        ls_prim   TYPE ty_saida,
        lt_vbeln  TYPE STANDARD TABLE OF vbeln_vl,
        lv_vbeln  TYPE vbeln_vl,
        lv_lgtor  TYPE lgtor,
        lv_lgbzo  TYPE lgbzo,
        lv_cancel TYPE xfeld,
        lt_msg    LIKE gt_saida,
        lo_log    TYPE REF TO zcl_sepex_log,
        lv_ext    TYPE balnrext,
        lx_erro   TYPE REF TO zcx_sepex,
        lv_texto  TYPE bapi_msg.

  " Autorização de regularização (a lista pode ter sido aberta só com exibir)
  TRY.
      zcl_sepex_auth=>verificar( iv_actvt = zif_sepex_const=>gc_actvt-regularizar
                                 iv_lgnum = p_lgnum ).
    CATCH zcx_sepex INTO lx_erro.
      lv_texto = lx_erro->get_texto( ).
      MESSAGE lv_texto TYPE 'S' DISPLAY LIKE 'E'.
      RETURN.
  ENDTRY.

  " Remessas distintas das linhas marcadas (ignora linhas só de mensagem)
  lo_sel  = go_alv->get_selections( ).
  lt_rows = lo_sel->get_selected_rows( ).
  LOOP AT lt_rows INTO lv_row.
    READ TABLE gt_saida INTO ls_saida INDEX lv_row.
    IF sy-subrc = 0 AND ls_saida-vbeln IS NOT INITIAL.
      IF ls_prim IS INITIAL.
        ls_prim = ls_saida.
      ENDIF.
      APPEND ls_saida-vbeln TO lt_vbeln.
    ENDIF.
  ENDLOOP.
  SORT lt_vbeln.
  DELETE ADJACENT DUPLICATES FROM lt_vbeln.
  IF lt_vbeln IS INITIAL.
    MESSAGE s021 DISPLAY LIKE 'E'.
    RETURN.
  ENDIF.

  PERFORM f_popup_portao USING    ls_prim-lgtor ls_prim-lgbzo
                         CHANGING lv_lgtor lv_lgbzo lv_cancel.
  IF lv_cancel = 'X'.
    RETURN.
  ENDIF.

  " Validação: portão (T30B) e zona do portão (T30C), no depósito
  SELECT SINGLE lgtor FROM t30b INTO lv_lgtor
    WHERE lgnum = p_lgnum AND lgtor = lv_lgtor.
  IF sy-subrc <> 0.
    MESSAGE s037 WITH lv_lgtor p_lgnum DISPLAY LIKE 'E'.
    RETURN.
  ENDIF.
  IF lv_lgbzo IS NOT INITIAL.
    SELECT SINGLE lgbzo FROM t30c INTO lv_lgbzo
      WHERE lgnum = p_lgnum AND lgtor = lv_lgtor AND lgbzo = lv_lgbzo.
    IF sy-subrc <> 0.
      MESSAGE s038 WITH lv_lgbzo lv_lgtor DISPLAY LIKE 'E'.
      RETURN.
    ENDIF.
  ENDIF.

  lv_ext = 'ZSEPEX02'.
  CREATE OBJECT lo_log EXPORTING iv_extnumber = lv_ext.
  LOOP AT lt_vbeln INTO lv_vbeln.
    PERFORM f_aplicar_portao_remessa USING    lv_vbeln lv_lgtor lv_lgbzo lo_log
                                     CHANGING lt_msg.
  ENDLOOP.
  lo_log->salvar( ).

  " Remonta a lista (F_MONTAR_SAIDA guarda o conteúdo atual como
  " mensagens no fim) e atualiza o ALV
  gt_saida = lt_msg.
  PERFORM f_montar_saida.
  go_alv->refresh( refresh_mode = if_salv_c_refresh=>full ).
ENDFORM.

*&---------------------------------------------------------------------*
*&      Form  F_POPUP_PORTAO
*&---------------------------------------------------------------------*
*  Campos LIKP-LGTOR / LIKP-LGBZO: F4 pelas tabelas de verificação
*----------------------------------------------------------------------*
FORM f_popup_portao USING    pv_lgtor_ini TYPE lgtor
                             pv_lgbzo_ini TYPE lgbzo
                    CHANGING cv_lgtor     TYPE lgtor
                             cv_lgbzo     TYPE lgbzo
                             cv_cancel    TYPE xfeld.
  DATA: lt_sval TYPE STANDARD TABLE OF sval,
        ls_sval TYPE sval,
        lv_rc   TYPE c LENGTH 1.

  CLEAR: cv_cancel, cv_lgtor, cv_lgbzo.
  ls_sval-tabname   = 'LIKP'.
  ls_sval-fieldname = 'LGTOR'.
  ls_sval-value     = pv_lgtor_ini.
  ls_sval-field_obl = 'X'.
  ls_sval-fieldtext = 'Portão'.
  APPEND ls_sval TO lt_sval.
  CLEAR ls_sval.
  ls_sval-tabname   = 'LIKP'.
  ls_sval-fieldname = 'LGBZO'.
  ls_sval-value     = pv_lgbzo_ini.
  ls_sval-fieldtext = 'Zona'.
  APPEND ls_sval TO lt_sval.

  CALL FUNCTION 'POPUP_GET_VALUES'
    EXPORTING
      popup_title     = 'Portão / zona de expedição'
    IMPORTING
      returncode      = lv_rc
    TABLES
      fields          = lt_sval
    EXCEPTIONS
      error_in_fields = 1
      OTHERS          = 2.
  IF sy-subrc <> 0 OR lv_rc = 'A'.
    cv_cancel = 'X'.
    RETURN.
  ENDIF.
  READ TABLE lt_sval INTO ls_sval INDEX 1.
  cv_lgtor = ls_sval-value.
  READ TABLE lt_sval INTO ls_sval INDEX 2.
  cv_lgbzo = ls_sval-value.
ENDFORM.

*&---------------------------------------------------------------------*
*&      Form  F_APLICAR_PORTAO_REMESSA
*&---------------------------------------------------------------------*
*  Uma remessa: bloqueio Express -> cabeçalho (MODIFY) -> remessa via
*  WS_DELIVERY_UPDATE se ainda sem saída (o commit dela leva o cabeçalho)
*  -> cada OT de regularização aberta (portão/zona + fila, commit por OT)
*----------------------------------------------------------------------*
FORM f_aplicar_portao_remessa USING    pv_vbeln TYPE vbeln_vl
                                       pv_lgtor TYPE lgtor
                                       pv_lgbzo TYPE lgbzo
                                       po_log   TYPE REF TO zcl_sepex_log
                              CHANGING ct_msg   LIKE gt_saida.
  DATA: ls_cab   TYPE zsepex_t_cab,
        ls_par   TYPE zsepex_t_par,
        lt_ot    TYPE zsepex_t_ot_tt,
        ls_ot    TYPE zsepex_t_ot,
        lv_kostk TYPE kostk,
        lv_lvstk TYPE lvstk,
        lv_wbstk TYPE wbstk,
        lv_qtd   TYPE i,
        lv_bloq  TYPE xfeld,
        lx_erro  TYPE REF TO zcx_sepex,
        ls_msg   TYPE ty_saida.

  ls_msg-vbeln = pv_vbeln.
  TRY.
      ls_par = zcl_sepex_controle=>ler_param( p_lgnum ).
      zcl_sepex_controle=>bloquear( iv_lgnum = p_lgnum iv_vbeln = pv_vbeln ).
      lv_bloq = 'X'.

      " a) cabeçalho Express (sem commit ainda)
      ls_cab = zcl_sepex_controle=>gravar_portao_zona( iv_lgnum = p_lgnum
                                                       iv_vbeln = pv_vbeln
                                                       iv_lgtor = pv_lgtor
                                                       iv_lgbzo = pv_lgbzo ).
      IF ls_cab IS INITIAL.
        zcx_sepex=>raise_msg( iv_msgno = '002' iv_msgv1 = pv_vbeln ).
      ENDIF.
      ls_msg-origem = ls_cab-origem.
      ls_msg-tknum  = ls_cab-tknum.

      " b) remessa, só sem saída de mercadoria
      zcl_sepex_wm=>ler_status_remessa( EXPORTING iv_vbeln = pv_vbeln
                                        IMPORTING ev_kostk = lv_kostk
                                                  ev_lvstk = lv_lvstk
                                                  ev_wbstk = lv_wbstk ).
      IF lv_wbstk <> 'C'.
        zcl_sepex_wm=>atualizar_portao_remessa( iv_vbeln = pv_vbeln
                                                iv_lgtor = pv_lgtor
                                                iv_lgbzo = pv_lgbzo ).
      ELSE.
        COMMIT WORK AND WAIT.
        po_log->add_msg( iv_msgty = 'W' iv_msgno = '039' iv_msgv1 = pv_vbeln ).
        MESSAGE s039 WITH pv_vbeln INTO ls_msg-msg.
        APPEND ls_msg TO ct_msg.
      ENDIF.

      " c) OTs de regularização abertas
      lt_ot = zcl_sepex_controle=>ler_ots( iv_lgnum = p_lgnum iv_vbeln = pv_vbeln ).
      DELETE lt_ot WHERE pquit = 'X'.
      SORT lt_ot BY tanum.
      DELETE ADJACENT DUPLICATES FROM lt_ot COMPARING tanum.
      LOOP AT lt_ot INTO ls_ot.
        TRY.
            zcl_sepex_wm=>aplicar_portao_ot( iv_lgnum     = p_lgnum
                                             iv_tanum     = ls_ot-tanum
                                             iv_lgtor     = pv_lgtor
                                             iv_lgbzo     = pv_lgbzo
                                             iv_fila_pref = ls_par-fila_reg_pref ).
            lv_qtd = lv_qtd + 1.
          CATCH zcx_sepex INTO lx_erro.
            po_log->add_excecao( lx_erro ).
            ls_msg-tanum = ls_ot-tanum.
            ls_msg-msg   = lx_erro->get_texto( ).
            APPEND ls_msg TO ct_msg.
            CLEAR ls_msg-tanum.
        ENDTRY.
      ENDLOOP.

      zcl_sepex_controle=>desbloquear( iv_lgnum = p_lgnum iv_vbeln = pv_vbeln ).
      po_log->add_msg( iv_msgno = '036' iv_msgv1 = pv_lgtor iv_msgv2 = pv_lgbzo
                       iv_msgv3 = pv_vbeln iv_msgv4 = lv_qtd ).
      MESSAGE s036 WITH pv_lgtor pv_lgbzo pv_vbeln lv_qtd INTO ls_msg-msg.
      APPEND ls_msg TO ct_msg.

    CATCH zcx_sepex INTO lx_erro.
      ROLLBACK WORK.
      IF lv_bloq = 'X'.
        zcl_sepex_controle=>desbloquear( iv_lgnum = p_lgnum iv_vbeln = pv_vbeln ).
      ENDIF.
      po_log->add_excecao( lx_erro ).
      ls_msg-msg = lx_erro->get_texto( ).
      APPEND ls_msg TO ct_msg.
  ENDTRY.
ENDFORM.

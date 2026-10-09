*&---------------------------------------------------------------------*
*& Report ZSEPEX_R_PENDENCIAS  (transação ZSEPEX03)
*&---------------------------------------------------------------------*
*& Separação Express - pendências de separação física:
*&  - por carga / remessa / material / lote, com idade em dias e destaque
*&    (vermelho) acima de DIAS_ALERTA do depósito
*&  - versão de fechamento: saldo da posição virtual (LQUA) por
*&    material/lote, para a evidência de auditoria
*&  - envio por e-mail (job diário) para os destinatários do parâmetro
*&---------------------------------------------------------------------*
REPORT zsepex_r_pendencias MESSAGE-ID zsepex.

TABLES: zsepex_t_cab.

TYPES: BEGIN OF ty_pend,
         alerta     TYPE icon_d,
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
         qtd_pend   TYPE zsepex_qtd,
         meins      TYPE meins,
         tanum      TYPE tanum,
         status     TYPE zsepex_status,
         status_txt TYPE val_text,
         dt_virt    TYPE datum,
         dt_pgi     TYPE datum,
         dias       TYPE i,
         origem_id  TYPE zsepex_origem_id,
         color      TYPE lvc_t_scol,
       END OF ty_pend,
       BEGIN OF ty_fech,
         lgtyp TYPE lgtyp,
         lgpla TYPE lgpla,
         matnr TYPE matnr,
         maktx TYPE maktx,
         charg TYPE charg_d,
         verme TYPE lqua-verme,
         meins TYPE meins,
         remessas TYPE i,
       END OF ty_fech.

DATA: gt_pend TYPE STANDARD TABLE OF ty_pend,
      gt_fech TYPE STANDARD TABLE OF ty_fech,
      gs_par  TYPE zsepex_t_par.

SELECTION-SCREEN BEGIN OF BLOCK b1 WITH FRAME TITLE TEXT-001.
PARAMETERS:     p_lgnum  TYPE lgnum OBLIGATORY.
SELECT-OPTIONS: s_tknum  FOR zsepex_t_cab-tknum,
                s_vbeln  FOR zsepex_t_cab-vbeln,
                s_origem FOR zsepex_t_cab-origem,
                s_status FOR zsepex_t_cab-status,
                s_dtvirt FOR zsepex_t_cab-dt_virt.
SELECTION-SCREEN END OF BLOCK b1.
SELECTION-SCREEN BEGIN OF BLOCK b2 WITH FRAME TITLE TEXT-002.
PARAMETERS: p_aberto AS CHECKBOX DEFAULT 'X',
            p_fech   AS CHECKBOX,
            p_email  AS CHECKBOX.
SELECTION-SCREEN END OF BLOCK b2.

START-OF-SELECTION.
  PERFORM f_executar.

*&---------------------------------------------------------------------*
FORM f_executar.
  DATA: lx_erro  TYPE REF TO zcx_sepex,
        lv_texto TYPE bapi_msg.

  TRY.
      zcl_sepex_auth=>verificar( iv_actvt = zif_sepex_const=>gc_actvt-exibir
                                 iv_lgnum = p_lgnum ).
      gs_par = zcl_sepex_controle=>ler_param( p_lgnum ).
    CATCH zcx_sepex INTO lx_erro.
      lv_texto = lx_erro->get_texto( ).
      MESSAGE lv_texto TYPE 'S' DISPLAY LIKE 'E'.
      RETURN.
  ENDTRY.

  PERFORM f_montar_pendencias.
  IF p_fech = 'X'.
    PERFORM f_montar_fechamento.
  ENDIF.
  IF p_email = 'X'.
    PERFORM f_enviar_email.
  ENDIF.
  IF sy-batch = space.
    PERFORM f_exibir.
  ENDIF.
ENDFORM.

*&---------------------------------------------------------------------*
FORM f_montar_pendencias.
  DATA: lt_cab    TYPE zsepex_t_cab_tt,
        ls_cab    TYPE zsepex_t_cab,
        lt_itm    TYPE zsepex_t_itm_tt,
        ls_itm    TYPE zsepex_t_itm,
        lt_ot     TYPE zsepex_t_ot_tt,
        ls_ot     TYPE zsepex_t_ot,
        ls_pend   TYPE ty_pend,
        ls_color  TYPE lvc_s_scol,
        lr_status TYPE RANGE OF zsepex_status,
        ls_rst    LIKE LINE OF lr_status.

  IF s_status[] IS NOT INITIAL.
    lr_status = s_status[].
  ELSEIF p_aberto = 'X'.
    ls_rst-sign = 'I'. ls_rst-option = 'BT'.
    ls_rst-low  = zif_sepex_const=>gc_status-registrado.
    ls_rst-high = zif_sepex_const=>gc_status-em_regul.
    APPEND ls_rst TO lr_status.
  ENDIF.
  lt_cab = zcl_sepex_controle=>ler_cabs_por_status( iv_lgnum  = p_lgnum
                                                   it_status = lr_status
                                                   it_tknum  = s_tknum[] ).
  DELETE lt_cab WHERE vbeln NOT IN s_vbeln OR origem NOT IN s_origem
                   OR dt_virt NOT IN s_dtvirt.

  LOOP AT lt_cab INTO ls_cab.
    lt_itm = zcl_sepex_controle=>ler_itens( iv_lgnum = ls_cab-lgnum iv_vbeln = ls_cab-vbeln ).
    lt_ot  = zcl_sepex_controle=>ler_ots( iv_lgnum = ls_cab-lgnum iv_vbeln = ls_cab-vbeln ).
    LOOP AT lt_itm INTO ls_itm.
      IF p_aberto = 'X' AND ls_itm-status = zif_sepex_const=>gc_status-concluido.
        CONTINUE.
      ENDIF.
      CLEAR ls_pend.
      MOVE-CORRESPONDING ls_itm TO ls_pend.
      ls_pend-origem    = ls_cab-origem.
      ls_pend-origem_id = ls_cab-origem_id.
      ls_pend-tknum     = ls_cab-tknum.
      ls_pend-dt_virt   = ls_cab-dt_virt.
      ls_pend-dt_pgi    = ls_cab-dt_pgi.
      ls_pend-qtd_pend  = ls_itm-menge - ls_itm-qtd_regul.
      IF ls_pend-qtd_pend < 0.
        ls_pend-qtd_pend = 0.
      ENDIF.
      IF ls_cab-dt_virt IS NOT INITIAL.
        ls_pend-dias = sy-datum - ls_cab-dt_virt.
      ENDIF.
      READ TABLE lt_ot INTO ls_ot WITH KEY vbeln = ls_itm-vbeln posnr = ls_itm-posnr pquit = space.
      IF sy-subrc = 0.
        ls_pend-tanum = ls_ot-tanum.
      ENDIF.
      ls_pend-status_txt = zcl_sepex_controle=>texto_status( ls_itm-status ).
      SELECT SINGLE maktx FROM makt INTO ls_pend-maktx
        WHERE matnr = ls_itm-matnr AND spras = sy-langu.

      IF ls_itm-status = zif_sepex_const=>gc_status-concluido.
        ls_pend-alerta = icon_led_green.
      ELSEIF gs_par-dias_alerta > 0 AND ls_pend-dias > gs_par-dias_alerta.
        ls_pend-alerta = icon_led_red.
        CLEAR ls_color.
        ls_color-color-col = 6.
        ls_color-color-int = 1.
        APPEND ls_color TO ls_pend-color.
      ELSE.
        ls_pend-alerta = icon_led_yellow.
      ENDIF.
      APPEND ls_pend TO gt_pend.
    ENDLOOP.
  ENDLOOP.
  SORT gt_pend BY dias DESCENDING tknum vbeln posnr.
ENDFORM.

*&---------------------------------------------------------------------*
FORM f_montar_fechamento.
  TYPES: BEGIN OF lty_lqua,
           lgtyp TYPE lgtyp,
           lgpla TYPE lgpla,
           matnr TYPE matnr,
           charg TYPE charg_d,
           verme TYPE lqua-verme,
           meins TYPE meins,
         END OF lty_lqua.
  DATA: lt_lqua TYPE STANDARD TABLE OF lty_lqua,
        ls_lqua TYPE lty_lqua,
        ls_fech TYPE ty_fech,
        ls_pend TYPE ty_pend.

  SELECT lgtyp lgpla matnr charg verme meins
    FROM lqua INTO TABLE lt_lqua
    WHERE lgnum = p_lgnum
      AND lgtyp = gs_par-lgtyp_virt.
  LOOP AT lt_lqua INTO ls_lqua.
    CLEAR ls_fech.
    MOVE-CORRESPONDING ls_lqua TO ls_fech.
    COLLECT ls_fech INTO gt_fech.
  ENDLOOP.
  LOOP AT gt_fech INTO ls_fech.
    SELECT SINGLE maktx FROM makt INTO ls_fech-maktx
      WHERE matnr = ls_fech-matnr AND spras = sy-langu.
    LOOP AT gt_pend INTO ls_pend WHERE matnr = ls_fech-matnr AND charg = ls_fech-charg
                                   AND qtd_pend > 0.
      ls_fech-remessas = ls_fech-remessas + 1.
    ENDLOOP.
    MODIFY gt_fech FROM ls_fech.
  ENDLOOP.
  SORT gt_fech BY matnr charg.
ENDFORM.

*&---------------------------------------------------------------------*
FORM f_exibir.
  DATA: lo_alv   TYPE REF TO cl_salv_table,
        lo_cols  TYPE REF TO cl_salv_columns_table,
        lo_col   TYPE REF TO cl_salv_column_table,
        lo_funcs TYPE REF TO cl_salv_functions_list,
        lo_disp  TYPE REF TO cl_salv_display_settings,
        lx_salv  TYPE REF TO cx_salv_error,
        lx_nf    TYPE REF TO cx_salv_not_found,
        lv_tit   TYPE lvc_title.

  IF p_fech = 'X'.
    IF gt_fech IS INITIAL.
      MESSAGE s021.
      RETURN.
    ENDIF.
    TRY.
        cl_salv_table=>factory( IMPORTING r_salv_table = lo_alv
                                CHANGING  t_table      = gt_fech ).
        lo_alv->get_functions( )->set_all( abap_true ).
        lo_alv->get_columns( )->set_optimize( abap_true ).
        lv_tit = |Separação Express - saldo da posição virtual { gs_par-lgtyp_virt }/{ gs_par-lgpla_virt } em { sy-datum DATE = USER }|.
        lo_alv->get_display_settings( )->set_list_header( lv_tit ).
        TRY.
            lo_col ?= lo_alv->get_columns( )->get_column( 'REMESSAS' ).
            lo_col->set_short_text( 'Remessas' ).
            lo_col->set_medium_text( 'Remessas pend.' ).
            lo_col->set_long_text( 'Remessas com pendência no lote' ).
          CATCH cx_salv_not_found INTO lx_nf.
        ENDTRY.
        lo_alv->display( ).
      CATCH cx_salv_error INTO lx_salv.
        MESSAGE lx_salv TYPE 'S' DISPLAY LIKE 'E'.
    ENDTRY.
    RETURN.
  ENDIF.

  IF gt_pend IS INITIAL.
    MESSAGE s021.
    RETURN.
  ENDIF.
  TRY.
      cl_salv_table=>factory( IMPORTING r_salv_table = lo_alv
                              CHANGING  t_table      = gt_pend ).
      lo_funcs = lo_alv->get_functions( ).
      lo_funcs->set_all( abap_true ).
      lo_cols = lo_alv->get_columns( ).
      lo_cols->set_optimize( abap_true ).
      lo_cols->set_color_column( 'COLOR' ).
      lo_disp = lo_alv->get_display_settings( ).
      lv_tit = |Separação Express - pendências de separação física (alerta > { gs_par-dias_alerta } dias)|.
      lo_disp->set_list_header( lv_tit ).
      TRY.
          lo_col ?= lo_cols->get_column( 'ALERTA' ).
          lo_col->set_short_text( 'Alerta' ).
          lo_col->set_medium_text( 'Alerta' ).
          lo_col->set_long_text( 'Alerta de prazo' ).
          lo_col ?= lo_cols->get_column( 'QTD_PEND' ).
          lo_col->set_short_text( 'Pendente' ).
          lo_col->set_medium_text( 'Qtd pendente' ).
          lo_col->set_long_text( 'Quantidade pendente de separação' ).
          lo_col ?= lo_cols->get_column( 'STATUS_TXT' ).
          lo_col->set_short_text( 'Status' ).
          lo_col->set_medium_text( 'Status Express' ).
          lo_col->set_long_text( 'Status Separação Express' ).
          lo_col ?= lo_cols->get_column( 'DIAS' ).
          lo_col->set_short_text( 'Dias' ).
          lo_col->set_medium_text( 'Dias em aberto' ).
          lo_col->set_long_text( 'Dias desde a separação virtual' ).
          lo_col ?= lo_cols->get_column( 'TANUM' ).
          lo_col->set_short_text( 'OT regul.' ).
          lo_col->set_medium_text( 'OT regularização' ).
          lo_col->set_long_text( 'OT de regularização aberta' ).
        CATCH cx_salv_not_found INTO lx_nf.
      ENDTRY.
      lo_alv->display( ).
    CATCH cx_salv_msg INTO lx_salv.
      MESSAGE lx_salv TYPE 'S' DISPLAY LIKE 'E'.
  ENDTRY.
ENDFORM.

*&---------------------------------------------------------------------*
*& E-mail diário: corpo em texto com as pendências por carga e anexo CSV
*&---------------------------------------------------------------------*
FORM f_enviar_email.
  DATA: lo_bcs     TYPE REF TO cl_bcs,
        lo_doc     TYPE REF TO cl_document_bcs,
        lo_rec     TYPE REF TO if_recipient_bcs,
        lx_bcs     TYPE REF TO cx_bcs,
        lt_texto   TYPE soli_tab,
        ls_texto   TYPE soli,
        lt_csv     TYPE soli_tab,
        lv_csv     TYPE string,
        lt_dest    TYPE STANDARD TABLE OF string,
        lv_dest    TYPE string,
        lv_addr    TYPE adr6-smtp_addr,
        lv_assunto TYPE so_obj_des,
        lv_n       TYPE i,
        ls_pend    TYPE ty_pend,
        lv_tknum   TYPE tknum,
        lv_linha   TYPE string,
        lv_qtd     TYPE c LENGTH 20,
        lv_qtdp    TYPE c LENGTH 20,
        lv_size    TYPE so_obj_len.

  IF gs_par-email_dest IS INITIAL.
    MESSAGE i024 WITH p_lgnum.
    RETURN.
  ENDIF.
  SPLIT gs_par-email_dest AT ';' INTO TABLE lt_dest.

  " Corpo
  lv_linha = |Separação Express - pendências de separação física em { sy-datum DATE = USER } (depósito { p_lgnum })|.
  ls_texto = lv_linha. APPEND ls_texto TO lt_texto.
  CLEAR ls_texto. APPEND ls_texto TO lt_texto.
  IF gt_pend IS INITIAL.
    ls_texto = 'Nenhuma pendência.'. APPEND ls_texto TO lt_texto.
  ENDIF.
  SORT gt_pend BY tknum vbeln posnr.
  LOOP AT gt_pend INTO ls_pend.
    IF ls_pend-tknum <> lv_tknum.
      lv_tknum = ls_pend-tknum.
      CLEAR ls_texto. APPEND ls_texto TO lt_texto.
      lv_linha = |Carga { ls_pend-tknum ALPHA = OUT } - separação virtual em { ls_pend-dt_virt DATE = USER } ({ ls_pend-dias } dias)|.
      ls_texto = lv_linha. APPEND ls_texto TO lt_texto.
    ENDIF.
    WRITE ls_pend-qtd_pend TO lv_qtdp UNIT ls_pend-meins LEFT-JUSTIFIED.
    WRITE ls_pend-menge    TO lv_qtd  UNIT ls_pend-meins LEFT-JUSTIFIED.
    CONDENSE: lv_qtdp, lv_qtd.
    lv_linha = |  Remessa { ls_pend-vbeln ALPHA = OUT } - |
            && |{ ls_pend-matnr ALPHA = OUT } { ls_pend-maktx } lote { ls_pend-charg }: |
            && |pendente { lv_qtdp } de { lv_qtd } { ls_pend-meins }|.
    IF ls_pend-alerta = icon_led_red.
      lv_linha = |{ lv_linha }  ** ACIMA DO PRAZO **|.
    ENDIF.
    ls_texto = lv_linha. APPEND ls_texto TO lt_texto.
  ENDLOOP.
  SORT gt_pend BY dias DESCENDING tknum vbeln posnr.

  " Anexo CSV
  lv_csv = 'Origem;Carga;Remessa;Item;Centro;Material;Descricao;Lote;Qtd;Regularizado;Pendente;UM;OT;Status;Sep.virtual;PGI;Dias'.
  ls_texto = lv_csv. APPEND ls_texto TO lt_csv.
  LOOP AT gt_pend INTO ls_pend.
    WRITE ls_pend-qtd_pend TO lv_qtdp UNIT ls_pend-meins LEFT-JUSTIFIED.
    WRITE ls_pend-menge    TO lv_qtd  UNIT ls_pend-meins LEFT-JUSTIFIED.
    CONDENSE: lv_qtdp, lv_qtd.
    lv_csv = |{ ls_pend-origem };{ ls_pend-tknum ALPHA = OUT };|
          && |{ ls_pend-vbeln ALPHA = OUT };{ ls_pend-posnr };{ ls_pend-werks };|
          && |{ ls_pend-matnr ALPHA = OUT };{ ls_pend-maktx };{ ls_pend-charg };|
          && |{ lv_qtd };{ ls_pend-qtd_regul };{ lv_qtdp };{ ls_pend-meins };|
          && |{ ls_pend-tanum };{ ls_pend-status_txt };|
          && |{ ls_pend-dt_virt DATE = USER };{ ls_pend-dt_pgi DATE = USER };|
          && |{ ls_pend-dias }|.
    ls_texto = lv_csv. APPEND ls_texto TO lt_csv.
  ENDLOOP.

  TRY.
      lo_bcs = cl_bcs=>create_persistent( ).
      lv_assunto = |Separação Express - pendências { sy-datum DATE = USER }|.
      lo_doc = cl_document_bcs=>create_document( i_type    = 'RAW'
                                                 i_text    = lt_texto
                                                 i_subject = lv_assunto ).
      lv_size = lines( lt_csv ) * 255.
      lo_doc->add_attachment( i_attachment_type    = 'CSV'
                              i_attachment_subject = 'pendencias_express'
                              i_attachment_size    = lv_size
                              i_att_content_text   = lt_csv ).
      lo_bcs->set_document( lo_doc ).
      LOOP AT lt_dest INTO lv_dest.
        CONDENSE lv_dest.
        CHECK lv_dest IS NOT INITIAL.
        lv_addr = lv_dest.
        lo_rec = cl_cam_address_bcs=>create_internet_address( lv_addr ).
        lo_bcs->add_recipient( lo_rec ).
        lv_n = lv_n + 1.
      ENDLOOP.
      lo_bcs->set_send_immediately( 'X' ).
      lo_bcs->send( ).
      COMMIT WORK.
      MESSAGE s023 WITH lv_n.
    CATCH cx_bcs INTO lx_bcs.
      MESSAGE lx_bcs TYPE 'S' DISPLAY LIKE 'E'.
  ENDTRY.
ENDFORM.

*----------------------------------------------------------------------*
* Monitor de Carga ZWMR0010 - repositório ZWMR0010
*----------------------------------------------------------------------*

*======================================================================*
* A) ZWMR0010_PARAMETROS - checkbox ao lado da carga fechada (bloco B5)
*======================================================================*
SELECTION-SCREEN BEGIN OF BLOCK b5 WITH FRAME TITLE text-049.
  PARAMETERS: p_fech AS CHECKBOX,
              p_expr AS CHECKBOX.                     " SEPEX: Separação Express
SELECTION-SCREEN END OF BLOCK b5.

AT SELECTION-SCREEN.                                   " SEPEX: exclusivos
  IF p_fech = abap_true AND p_expr = abap_true.
    MESSAGE 'Marque Carga fechada OU Separação Express, não as duas' TYPE 'E'.
  ENDIF.

*======================================================================*
* B) ZWMR0010_ALV - USER_COMMAND_OO, comando SEPARAR
*======================================================================*
    WHEN 'SEPARAR'.
      IF p_fech = abap_true.
        PERFORM zf_separar_fechada.
      ELSEIF p_expr = abap_true.                       " SEPEX
        PERFORM zf_separar_express.                    " SEPEX
      ELSE.
        PERFORM zf_separar.
      ENDIF.

*======================================================================*
* C) ZWMR0010_FORM - ZF_CRIA_TRANSFERENCIA: novo parâmetro P_EXPRESS
*    (assinatura e repasse à ZTM_REG_TRANSFERENCIA). Chamadas existentes
*    passam space; ZF_SEPARAR_EXPRESS passa abap_true.
*======================================================================*
FORM zf_cria_transferencia USING p_auto p_express CHANGING ev_numero .   " SEPEX
  ...
  CALL FUNCTION 'ZTM_REG_TRANSFERENCIA'
    EXPORTING
      i_modo     = i_modo
      ...
      i_auto     = v_auto
      i_express  = p_express                           " SEPEX
    IMPORTING
  ...
* Carga do depositante (Armazém Geral): repassar para a classe
  PERFORM zf_separacao_retorno USING    wa_alv-tknum
                                        p_express       " SEPEX (ver 04_zcl_armazem_geral)
                               CHANGING v_erro.

* Chamadas existentes a ajustar (acrescentar o 2º parâmetro):
*   tela 0101 SALVAR (PAI):  PERFORM zf_cria_transferencia USING space    space CHANGING lv_numero.
*   ZF_MASS_TRANSF:          PERFORM zf_cria_transferencia USING abap_true space CHANGING lv_numero.

*======================================================================*
* D) ZWMR0010_FORM - novo FORM ZF_SEPARAR_EXPRESS (ao lado de
*    ZF_SEPARAR_FECHADA). Uma carga por vez; mesma tela 0101 de
*    portão/zona do fluxo normal; carga dispensada da conferência de
*    expedição (ZWMT011) só para liberar o faturamento no dia 31.
*======================================================================*
*&---------------------------------------------------------------------*
*&      Form  ZF_SEPARAR_EXPRESS                                  " SEPEX
*&---------------------------------------------------------------------*
FORM zf_separar_express.
  DATA: lt_rows    TYPE STANDARD TABLE OF lvc_s_row,
        ls_rows    TYPE lvc_s_row,
        v_bloqueio TYPE c,
        lv_ag_sep  TYPE xfeld,
        wa_icentros TYPE zwm_icentros.

  CALL METHOD go_alv->get_selected_rows IMPORTING et_index_rows = lt_rows.
  IF lines( lt_rows ) <> 1.
    MESSAGE text-018 TYPE 'I'.
    RETURN.
  ENDIF.
  READ TABLE lt_rows INTO ls_rows INDEX 1.
  READ TABLE it_alv INTO wa_alv INDEX ls_rows-index.

  " Autorização Express (liberar)
  IF zcl_sepex_auth=>tem_autorizacao( iv_actvt = zif_sepex_const=>gc_actvt-liberar
                                      iv_lgnum = 'DFC' ) = space.
    MESSAGE 'Sem autorização para Separação Express (ZSEPEX_AUT 01)' TYPE 'I'.
    RETURN.
  ENDIF.

  PERFORM zf_bloqueio_vttk USING wa_alv-tknum 'B' CHANGING v_bloqueio.
  IF v_bloqueio = abap_true.
    RETURN.
  ENDIF.

  IF wa_alv-sttrg <> '2'.
    MESSAGE text-032 TYPE 'I'.
  ELSE.
    PERFORM zf_ag_carga_depositante USING wa_alv-tknum wa_alv-tplst CHANGING lv_ag_sep.
    IF lv_ag_sep <> abap_true.
      SELECT SINGLE * FROM zwm_icentros INTO wa_icentros
        WHERE docref = wa_alv-tknum AND status <> 'C'.
      IF sy-subrc = 0.
        MESSAGE 'Processo de separação já iniciado.' TYPE 'I'.
        PERFORM zf_bloqueio_vttk USING wa_alv-tknum 'L' CHANGING v_bloqueio.
        RETURN.
      ENDIF.
    ENDIF.

    " Mesma tela de portão/zona; no SALVAR a tela 0101 chama
    " ZF_CRIA_TRANSFERENCIA (p_express = abap_true quando p_expr marcado)
    v_etapa = '1'.
    CLEAR: v_portao, v_zona, v_posicaoi, v_e_fechar.
    CALL SCREEN 0101 STARTING AT 1 1 ENDING AT 48 8.

    " Dispensa da conferência de expedição para o faturamento do dia 31
    " (a conferência acontece no carregamento, pelos volumes Express)
    IF v_e_fechar <> abap_true.
      DATA ls_zwmt011 TYPE zwmt011.
      ls_zwmt011-tknum = wa_alv-tknum.
      MODIFY zwmt011 FROM ls_zwmt011.
      COMMIT WORK AND WAIT.
    ENDIF.
  ENDIF.

  CALL FUNCTION 'HU_PACKING_REFRESH'.
  PERFORM zf_bloqueio_vttk USING wa_alv-tknum 'L' CHANGING v_bloqueio.
  PERFORM zf_bloqueia_monitor USING abap_true.
  PERFORM zf_refresh.
ENDFORM.

* Observação: no PAI da tela 0101 (SALVAR), onde hoje está
*   PERFORM zf_cria_transferencia USING space CHANGING lv_numero.
* passar p_expr como 2º parâmetro:
*   PERFORM zf_cria_transferencia USING space p_expr CHANGING lv_numero.   " SEPEX

*======================================================================*
* E) ZWMR0010_FORM - ZF_VALIDA_SALDO_TRANSF: descontar o saldo Express
*    ainda sem OT de regularização. Inserir após o LOOP que soma LQUA
*    em <fs_sal>-disp (antes das remessas ZZICENTROS).
*======================================================================*
  " SEPEX >>> saldo da Separação Express ainda não reservado por OT
  DATA: lt_sepex TYPE TABLE OF zsepex_s_saldo,
        ls_sepex TYPE zsepex_s_saldo.
  CALL FUNCTION 'ZSEPEX_SALDO_PENDENTE'
    EXPORTING
      i_lgnum     = 'DFC'
      i_werks     = 'DPFE'
      i_so_sem_ot = abap_true
    TABLES
      t_saldo     = lt_sepex.
  LOOP AT lt_sepex INTO ls_sepex.
    READ TABLE lt_saldo ASSIGNING <fs_sal> WITH KEY matnr = ls_sepex-matnr.
    CHECK sy-subrc = 0.
    lv_conv = ls_sepex-menge.
    IF ls_sepex-meins <> <fs_sal>-vrkme.
      PERFORM zf_convert_material USING ls_sepex-matnr ls_sepex-meins
                                        <fs_sal>-vrkme ls_sepex-menge
                               CHANGING lv_conv.
    ENDIF.
    SUBTRACT lv_conv FROM <fs_sal>-disp.
  ENDLOOP.
  " SEPEX <<<

*  O mesmo desconto vale para ZF_PREENCHE_SIMULACAO (carga fechada),
*  reduzindo <fs_lqua>-verme por material/lote antes da escolha de UDs.
*  Como o Express substitui a carga fechada, pode ser omitido se a
*  carga fechada for desativada junto com a entrada em produção.

*======================================================================*
* F) ZWMR0010_TOP / ZF_MONTA_ALV - coluna Express (opcional, fase 1)
*======================================================================*
*  tp_alv: express(4) TYPE c.                       " ícone
*  ZF_MONTA_ALV, após ler wa_icentros:
*    IF wa_icentros-zzexpress = abap_true. wa_alv-express = '@39@'. ENDIF.   " SEPEX
*  Hotspot em EXPRESS -> SUBMIT zsepex_r_pendencias WITH p_lgnum = 'DFC'
*                                                   WITH s_tknum = wa_alv-tknum AND RETURN.

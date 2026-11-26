*&---------------------------------------------------------------------*
*& Report ZSEPEX_R_CARGA_PAR
*&---------------------------------------------------------------------*
*& Separação Express - carga inicial dos parâmetros (ZSEPEX_T_PAR e
*& ZSEPEX_T_PAR_LT). Uso: após recarga do QAS ou na entrada em PRD, pela
*& SE38, com os valores padrão da instalação (README, passo 3). Modo teste
*& mostra o que seria gravado. Grava por MODIFY: pode rodar de novo para
*& ajustar valores sem perder a linha.
*&---------------------------------------------------------------------*
REPORT zsepex_r_carga_par MESSAGE-ID zsepex.

SELECTION-SCREEN BEGIN OF BLOCK b1 WITH FRAME TITLE TEXT-001.
PARAMETERS: p_lgnum TYPE lgnum            DEFAULT 'DFC' OBLIGATORY,
            p_lgtyp TYPE lgtyp            DEFAULT '9EX' OBLIGATORY,
            p_lgber TYPE lgber            DEFAULT '001' OBLIGATORY,
            p_lgpla TYPE lgpla            DEFAULT 'EXPRESS' OBLIGATORY,
            p_bwlvs TYPE bwlvs            DEFAULT '9EX' OBLIGATORY,
            p_otime TYPE zsepex_ot_imed   DEFAULT 'X',
            p_avs   TYPE zsepex_lgtyp_avs DEFAULT 'AVS',
            p_reab  TYPE zsepex_reab_auto DEFAULT 'X',
            p_udpar TYPE zsepex_ud_parcial,
            p_prefp TYPE zsepex_fila_reg_pref DEFAULT 'PC',
            p_prefa TYPE zsepex_fila_reg_pref DEFAULT 'AV',
            p_dias  TYPE zsepex_dias      DEFAULT 7,
            p_email TYPE ad_smtpadr,
            p_ativo TYPE xfeld            DEFAULT 'X'.
SELECTION-SCREEN END OF BLOCK b1.

SELECTION-SCREEN BEGIN OF BLOCK b2 WITH FRAME TITLE TEXT-002.
PARAMETERS: p_lt1 TYPE lgtyp DEFAULT 'DIA',
            p_lt2 TYPE lgtyp DEFAULT 'DTA',
            p_lt3 TYPE lgtyp DEFAULT 'XDC',
            p_lt4 TYPE lgtyp DEFAULT 'DII',
            p_lt5 TYPE lgtyp,
            p_ltlim AS CHECKBOX DEFAULT 'X'.
SELECTION-SCREEN COMMENT /1(79) TEXT-c01.
SELECTION-SCREEN END OF BLOCK b2.

SELECTION-SCREEN BEGIN OF BLOCK b3 WITH FRAME TITLE TEXT-003.
PARAMETERS: p_teste AS CHECKBOX DEFAULT 'X'.
SELECTION-SCREEN END OF BLOCK b3.

START-OF-SELECTION.
  PERFORM f_carregar.

*&---------------------------------------------------------------------*
FORM f_carregar.
  DATA: ls_par    TYPE zsepex_t_par,
        ls_old    TYPE zsepex_t_par,
        lt_lt     TYPE STANDARD TABLE OF zsepex_t_par_lt,
        ls_lt     TYPE zsepex_t_par_lt,
        lt_lgtyp  TYPE STANDARD TABLE OF lgtyp,
        lv_lgtyp  TYPE lgtyp,
        lv_prio   TYPE numc2,
        lv_existe TYPE xfeld,
        lv_acao   TYPE c LENGTH 10.

  " ---- ZSEPEX_T_PAR (uma linha por depósito)
  SELECT SINGLE * FROM zsepex_t_par INTO ls_old WHERE lgnum = p_lgnum.
  IF sy-subrc = 0.
    lv_existe = 'X'.
    ls_par = ls_old.
  ENDIF.
  ls_par-mandt         = sy-mandt.
  ls_par-lgnum         = p_lgnum.
  ls_par-lgtyp_virt    = p_lgtyp.
  ls_par-lgber_virt    = p_lgber.
  ls_par-lgpla_virt    = p_lgpla.
  ls_par-bwlvs_reg     = p_bwlvs.
  ls_par-ot_imediata   = p_otime.
  ls_par-lgtyp_avs     = p_avs.
  ls_par-reab_auto     = p_reab.
  ls_par-ud_parcial    = p_udpar.
  ls_par-fila_pal_pref = p_prefp.
  ls_par-fila_avs_pref = p_prefa.
  ls_par-dias_alerta   = p_dias.
  ls_par-email_dest    = p_email.
  ls_par-ativo         = p_ativo.
  IF lv_existe = 'X'.
    ls_par-aenam = sy-uname.
    ls_par-aedat = sy-datum.
    ls_par-aezet = sy-uzeit.
    lv_acao = 'alterada'.
  ELSE.
    ls_par-ernam = sy-uname.
    ls_par-erdat = sy-datum.
    ls_par-erzet = sy-uzeit.
    lv_acao = 'nova'.
  ENDIF.

  " ---- ZSEPEX_T_PAR_LT (tipos de depósito de origem, prioridade na ordem)
  APPEND p_lt1 TO lt_lgtyp.
  APPEND p_lt2 TO lt_lgtyp.
  APPEND p_lt3 TO lt_lgtyp.
  APPEND p_lt4 TO lt_lgtyp.
  APPEND p_lt5 TO lt_lgtyp.
  DELETE lt_lgtyp WHERE table_line IS INITIAL.
  LOOP AT lt_lgtyp INTO lv_lgtyp.
    lv_prio = sy-tabix.
    CLEAR ls_lt.
    ls_lt-mandt      = sy-mandt.
    ls_lt-lgnum      = p_lgnum.
    ls_lt-lgtyp      = lv_lgtyp.
    ls_lt-prioridade = lv_prio.
    ls_lt-ativo      = 'X'.
    APPEND ls_lt TO lt_lt.
  ENDLOOP.

  " ---- Lista do que vai ser gravado
  WRITE: / 'ZSEPEX_T_PAR', p_lgnum, '-', lv_acao.
  WRITE: / '  Posição virtual   :', ls_par-lgtyp_virt, ls_par-lgber_virt, ls_par-lgpla_virt.
  WRITE: / '  Tipo mov. regul.  :', ls_par-bwlvs_reg.
  WRITE: / '  OT imediata       :', ls_par-ot_imediata.
  WRITE: / '  Tipo dep. avulso  :', ls_par-lgtyp_avs.
  WRITE: / '  Reabast. automát. :', ls_par-reab_auto.
  WRITE: / '  UD parcial        :', ls_par-ud_parcial.
  WRITE: / '  Fila paletes      :', ls_par-fila_pal_pref, '_D_<portão>'.
  WRITE: / '  Fila avulso       :', ls_par-fila_avs_pref, '_D_<portão>'.
  WRITE: / '  Dias alerta       :', ls_par-dias_alerta.
  WRITE: / '  E-mail            :', ls_par-email_dest.
  WRITE: / '  Ativo             :', ls_par-ativo.
  SKIP.
  WRITE: / 'ZSEPEX_T_PAR_LT', p_lgnum.
  LOOP AT lt_lt INTO ls_lt.
    WRITE: / '  Tipo', ls_lt-lgtyp, 'prioridade', ls_lt-prioridade.
  ENDLOOP.
  IF p_ltlim = 'X'.
    WRITE: / '  (tipos do depósito fora da lista serão removidos)'.
  ENDIF.
  SKIP.

  IF p_teste = 'X'.
    WRITE: / 'Modo teste: nada gravado.' COLOR COL_TOTAL.
    RETURN.
  ENDIF.

  " ---- Gravação
  MODIFY zsepex_t_par FROM ls_par.
  IF sy-subrc <> 0.
    ROLLBACK WORK.
    WRITE: / 'Erro ao gravar ZSEPEX_T_PAR' COLOR COL_NEGATIVE.
    RETURN.
  ENDIF.
  IF p_ltlim = 'X'.
    DELETE FROM zsepex_t_par_lt WHERE lgnum = p_lgnum.
  ENDIF.
  IF lt_lt IS NOT INITIAL.
    MODIFY zsepex_t_par_lt FROM TABLE lt_lt.
    IF sy-subrc <> 0.
      ROLLBACK WORK.
      WRITE: / 'Erro ao gravar ZSEPEX_T_PAR_LT' COLOR COL_NEGATIVE.
      RETURN.
    ENDIF.
  ENDIF.
  COMMIT WORK AND WAIT.
  WRITE: / 'Parâmetros gravados. Conferir na SM30 (ZSEPEX_T_PAR / ZSEPEX_T_PAR_LT).' COLOR COL_POSITIVE.
ENDFORM.

*----------------------------------------------------------------------*
* Engine ZWM_ICENTROS - repositório ZWMR0010
* Funcoes/ZWM_ICENTROS/LZWM_ICENTROSTOP.abap e ZWM_ICENTROS.abap
*----------------------------------------------------------------------*

*======================================================================*
* A) ZF_CONFIRMA_ETAPAS - ramo "(M ou R) e status R/N"
*    Hoje: IF p_criaot ... ELSEIF wa_icentros-automatica ... ELSE erro 044
*    Inserir o ramo Express ANTES do ELSEIF automatica.
*======================================================================*
  ELSEIF ( wa_icentros-modo = 'M' OR wa_icentros-modo = 'R' ) AND ( wa_icentros-status = 'R' OR  wa_icentros-status = 'N' ).

    IF p_criaot = abap_true AND wa_icentros-zzexpress <> abap_true.   " SEPEX: Express não cria OT física
      PERFORM zf_cria_ot TABLES p_t_return
                          USING p_parc_ot.

    ELSEIF wa_icentros-zzexpress = abap_true.                          " SEPEX >>>
      PERFORM zf_sepex_separa_virtual TABLES p_t_return.               " SEPEX <<<

    ELSEIF wa_icentros-automatica = abap_true.
      "Remessa Automatica
      ... (inalterado)

*======================================================================*
* B) Bloco final da FM ZWM_ICENTROS ("Remessa Automatica"):
*    IF wa_icentros-automatica = abap_true AND wa_icentros-status = 'R'.
*    Acrescentar o equivalente Express logo após o ENDIF desse bloco,
*    para não esperar a próxima execução do job.
*======================================================================*
   IF wa_icentros-zzexpress = abap_true AND wa_icentros-status = 'R'.   " SEPEX >>>
     PERFORM zf_sepex_separa_virtual TABLES t_return.
   ENDIF.                                                                " SEPEX <<<

*======================================================================*
* C) ZF_CRIA_OT e ZF_CONTINUA_OT (e ZF_CONTINUA_OT_INBOUND):
*    hoje: IF wa_icentros-automatica = abap_true. CONTINUE. ENDIF.
*    trocar por:
*======================================================================*
    IF wa_icentros-automatica = abap_true OR wa_icentros-zzexpress = abap_true.   " SEPEX
      CONTINUE.
    ENDIF.

*======================================================================*
* D) Novo FORM no LZWM_ICENTROSTOP (ao lado de ZF_CRIA_OT).
*    Uma OT virtual por remessa do processo (ZWM_IC_EF com grupo);
*    todas OK -> status S (mesmo efeito do Z_WM_CONFIRMA_ICENTRO).
*======================================================================*
*&---------------------------------------------------------------------*
*&      Form  ZF_SEPEX_SEPARA_VIRTUAL                            " SEPEX
*&---------------------------------------------------------------------*
FORM zf_sepex_separa_virtual TABLES p_t_return STRUCTURE it_return.
  DATA: lt_ret      TYPE TABLE OF bapiret2,
        ls_ret      TYPE bapiret2,
        lv_erro     TYPE xfeld,
        lv_lgnum    TYPE lgnum,
        lv_origem   TYPE zsepex_origem,
        lv_orig_id  TYPE zsepex_origem_id,
        lv_tknum    TYPE tknum.

  lv_origem  = zif_sepex_const=>gc_origem-icentros.
  lv_orig_id = wa_icentros-numero.
  lv_tknum   = wa_icentros-docref.

  LOOP AT it_ic_ef INTO wa_ic_ef.
    IF wa_ic_ef-remessa IS INITIAL OR wa_ic_ef-grupo IS INITIAL.
      CONTINUE.
    ENDIF.
    IF wa_ic_ef-ctrl_ot = abap_true.
      CONTINUE.                       " remessa já tratada
    ENDIF.

    " Nº depósito WM da origem (T320), como o engine faz em ZF_CRIA_GRUPO
    CLEAR lv_lgnum.
    SELECT SINGLE lgnum FROM t320 INTO lv_lgnum
      WHERE werks = wa_ic_ef-centro_o
        AND lgort = wa_ic_ef-deposito_o.
    IF lv_lgnum IS INITIAL.
      lv_lgnum = 'DFC'.
    ENDIF.

    CLEAR lt_ret.
    CALL FUNCTION 'ZSEPEX_SEPARA_VIRTUAL'
      EXPORTING
        i_lgnum     = lv_lgnum
        i_vbeln     = wa_ic_ef-remessa
        i_refnr     = wa_ic_ef-grupo
        i_origem    = lv_origem
        i_origem_id = lv_orig_id
        i_tknum     = lv_tknum
      TABLES
        t_return    = lt_ret
      EXCEPTIONS
        e_erro      = 1
        OTHERS      = 2.
    IF sy-subrc <> 0.
      lv_erro = abap_true.
      LOOP AT lt_ret INTO ls_ret.
        MOVE-CORRESPONDING ls_ret TO p_t_return.
        APPEND p_t_return.
      ENDLOOP.
      PERFORM zf_log_error TABLES p_t_return USING abap_false.
      CONTINUE.
    ENDIF.

    wa_ic_ef-ctrl_ot = abap_true.
    MODIFY zwm_ic_ef FROM wa_ic_ef.
    COMMIT WORK AND WAIT.
  ENDLOOP.

  IF lv_erro <> abap_true.
    wa_icentros-status = 'S'.         " OTs "confirmadas": segue para SAIDA_MERC
    MODIFY zwm_icentros FROM wa_icentros.
    COMMIT WORK AND WAIT.
    CALL FUNCTION 'HU_PACKING_REFRESH'.
    PERFORM zf_bloqueio_zwm004 USING v_bloq.
  ENDIF.
ENDFORM.

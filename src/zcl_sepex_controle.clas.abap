"! Separação Express - controle: parâmetros, cabeçalho, itens, OTs de
"! regularização, bloqueio e saldo pendente. Toda gravação em tabela Z
"! do pacote passa por aqui.
CLASS zcl_sepex_controle DEFINITION
  PUBLIC
  FINAL
  CREATE PUBLIC.

  PUBLIC SECTION.
    TYPES ty_t_itm TYPE STANDARD TABLE OF zsepex_t_itm WITH DEFAULT KEY.
    TYPES ty_t_ot  TYPE STANDARD TABLE OF zsepex_t_ot  WITH DEFAULT KEY.
    TYPES ty_t_cab TYPE STANDARD TABLE OF zsepex_t_cab WITH DEFAULT KEY.
    TYPES ty_t_lgtyp TYPE STANDARD TABLE OF zsepex_t_par_lt WITH DEFAULT KEY.
    TYPES ty_r_status TYPE RANGE OF zsepex_status.
    TYPES ty_r_tknum  TYPE RANGE OF tknum.

    "! Parâmetros do depósito (ZSEPEX 001 se não cadastrado/inativo)
    CLASS-METHODS ler_param
      IMPORTING
        !iv_lgnum       TYPE lgnum
      RETURNING
        VALUE(rs_par)   TYPE zsepex_t_par
      RAISING
        zcx_sepex.

    "! Tipos de depósito de origem da regularização, por prioridade
    "! (ZSEPEX 026 se nenhum ativo)
    CLASS-METHODS ler_lgtyp_origem
      IMPORTING
        !iv_lgnum        TYPE lgnum
      RETURNING
        VALUE(rt_lgtyp)  TYPE ty_t_lgtyp
      RAISING
        zcx_sepex.

    CLASS-METHODS ler_cab
      IMPORTING
        !iv_lgnum      TYPE lgnum
        !iv_vbeln      TYPE vbeln_vl
      RETURNING
        VALUE(rs_cab)  TYPE zsepex_t_cab.

    CLASS-METHODS ler_itens
      IMPORTING
        !iv_lgnum       TYPE lgnum
        !iv_vbeln       TYPE vbeln_vl
      RETURNING
        VALUE(rt_itm)   TYPE ty_t_itm.

    CLASS-METHODS ler_ots
      IMPORTING
        !iv_lgnum      TYPE lgnum
        !iv_vbeln      TYPE vbeln_vl
      RETURNING
        VALUE(rt_ot)   TYPE ty_t_ot.

    "! Cabeçalhos por status (job de sincronização e relatórios)
    CLASS-METHODS ler_cabs_por_status
      IMPORTING
        !iv_lgnum      TYPE lgnum OPTIONAL
        !it_status     TYPE ty_r_status OPTIONAL
        !it_tknum      TYPE ty_r_tknum OPTIONAL
      RETURNING
        VALUE(rt_cab)  TYPE ty_t_cab.

    "! Grava cabeçalho (INSERT ou UPDATE) com auditoria. Sem COMMIT.
    CLASS-METHODS gravar_cab
      CHANGING
        !cs_cab TYPE zsepex_t_cab.

    "! Grava itens (MODIFY). Sem COMMIT.
    CLASS-METHODS gravar_itens
      IMPORTING
        !it_itm TYPE ty_t_itm.

    "! Grava OTs de regularização (MODIFY). Sem COMMIT.
    CLASS-METHODS gravar_ots
      IMPORTING
        !it_ot TYPE ty_t_ot.

    "! Muda o status do cabeçalho e grava. Sem COMMIT.
    CLASS-METHODS set_status
      IMPORTING
        !iv_lgnum  TYPE lgnum
        !iv_vbeln  TYPE vbeln_vl
        !iv_status TYPE zsepex_status
        !iv_data   TYPE datum OPTIONAL.

    CLASS-METHODS bloquear
      IMPORTING
        !iv_lgnum TYPE lgnum
        !iv_vbeln TYPE vbeln_vl
      RAISING
        zcx_sepex.

    CLASS-METHODS desbloquear
      IMPORTING
        !iv_lgnum TYPE lgnum
        !iv_vbeln TYPE vbeln_vl.

    "! Saldo Express ainda pendente de regularização física, por
    "! material/centro/lote, em unidade do item. Considera os itens com
    "! status < concluído e desconta o que já está em OT de regularização
    "! aberta (essas UDs já estão reservadas no WM). Usado pelo monitor
    "! (ZF_VALIDA_SALDO_TRANSF) e pela classe do Armazém Geral
    "! (DETERMINAR_LOTES_REMESSA).
    CLASS-METHODS saldo_pendente
      IMPORTING
        !iv_lgnum       TYPE lgnum
        !iv_werks       TYPE werks_d OPTIONAL
        !iv_so_sem_ot   TYPE xfeld DEFAULT 'X'
      RETURNING
        VALUE(rt_saldo) TYPE zsepex_t_saldo_tt.

    "! Quantidade pendente de um item (MENGE - QTD_REGUL - em OT aberta)
    CLASS-METHODS qtd_pendente_item
      IMPORTING
        !is_itm       TYPE zsepex_t_itm
        !it_ot        TYPE ty_t_ot
      RETURNING
        VALUE(rv_qtd) TYPE zsepex_qtd.

    "! Texto do status (domínio)
    CLASS-METHODS texto_status
      IMPORTING
        !iv_status       TYPE zsepex_status
      RETURNING
        VALUE(rv_texto)  TYPE val_text.

  PROTECTED SECTION.
  PRIVATE SECTION.
    CLASS-DATA gt_status_txt TYPE STANDARD TABLE OF dd07v WITH DEFAULT KEY.
ENDCLASS.


CLASS zcl_sepex_controle IMPLEMENTATION.

  METHOD ler_param.
    SELECT SINGLE * FROM zsepex_t_par INTO rs_par
      WHERE lgnum = iv_lgnum.
    IF sy-subrc <> 0 OR rs_par-ativo = space
       OR rs_par-lgtyp_virt IS INITIAL OR rs_par-lgpla_virt IS INITIAL.
      zcx_sepex=>raise_msg( iv_msgno = '001' iv_msgv1 = iv_lgnum ).
    ENDIF.
  ENDMETHOD.

  METHOD ler_lgtyp_origem.
    SELECT * FROM zsepex_t_par_lt INTO TABLE rt_lgtyp
      WHERE lgnum = iv_lgnum
        AND ativo = 'X'
      ORDER BY prioridade lgtyp.
    IF sy-subrc <> 0.
      zcx_sepex=>raise_msg( iv_msgno = '026' iv_msgv1 = iv_lgnum ).
    ENDIF.
  ENDMETHOD.

  METHOD ler_cab.
    SELECT SINGLE * FROM zsepex_t_cab INTO rs_cab
      WHERE lgnum = iv_lgnum
        AND vbeln = iv_vbeln.
  ENDMETHOD.

  METHOD ler_itens.
    SELECT * FROM zsepex_t_itm INTO TABLE rt_itm
      WHERE lgnum = iv_lgnum
        AND vbeln = iv_vbeln
      ORDER BY PRIMARY KEY.
  ENDMETHOD.

  METHOD ler_ots.
    SELECT * FROM zsepex_t_ot INTO TABLE rt_ot
      WHERE lgnum = iv_lgnum
        AND vbeln = iv_vbeln
      ORDER BY PRIMARY KEY.
  ENDMETHOD.

  METHOD ler_cabs_por_status.
    IF iv_lgnum IS INITIAL.
      SELECT * FROM zsepex_t_cab INTO TABLE rt_cab
        WHERE status IN it_status
          AND tknum  IN it_tknum
        ORDER BY PRIMARY KEY.
    ELSE.
      SELECT * FROM zsepex_t_cab INTO TABLE rt_cab
        WHERE lgnum  = iv_lgnum
          AND status IN it_status
          AND tknum  IN it_tknum
        ORDER BY PRIMARY KEY.
    ENDIF.
  ENDMETHOD.

  METHOD gravar_cab.
    DATA ls_old TYPE zsepex_t_cab.

    cs_cab-mandt = sy-mandt.
    SELECT SINGLE * FROM zsepex_t_cab INTO ls_old
      WHERE lgnum = cs_cab-lgnum
        AND vbeln = cs_cab-vbeln.
    IF sy-subrc <> 0.
      cs_cab-ernam = sy-uname.
      cs_cab-erdat = sy-datum.
      cs_cab-erzet = sy-uzeit.
    ELSE.
      cs_cab-ernam = ls_old-ernam.
      cs_cab-erdat = ls_old-erdat.
      cs_cab-erzet = ls_old-erzet.
    ENDIF.
    cs_cab-aenam = sy-uname.
    cs_cab-aedat = sy-datum.
    cs_cab-aezet = sy-uzeit.
    MODIFY zsepex_t_cab FROM cs_cab.
  ENDMETHOD.

  METHOD gravar_itens.
    DATA lt_itm TYPE ty_t_itm.
    FIELD-SYMBOLS <ls_itm> TYPE zsepex_t_itm.

    lt_itm = it_itm.
    LOOP AT lt_itm ASSIGNING <ls_itm>.
      <ls_itm>-mandt = sy-mandt.
    ENDLOOP.
    IF lt_itm IS NOT INITIAL.
      MODIFY zsepex_t_itm FROM TABLE lt_itm.
    ENDIF.
  ENDMETHOD.

  METHOD gravar_ots.
    DATA lt_ot TYPE ty_t_ot.
    FIELD-SYMBOLS <ls_ot> TYPE zsepex_t_ot.

    lt_ot = it_ot.
    LOOP AT lt_ot ASSIGNING <ls_ot>.
      <ls_ot>-mandt = sy-mandt.
      IF <ls_ot>-ernam IS INITIAL.
        <ls_ot>-ernam = sy-uname.
        <ls_ot>-erdat = sy-datum.
        <ls_ot>-erzet = sy-uzeit.
      ENDIF.
    ENDLOOP.
    IF lt_ot IS NOT INITIAL.
      MODIFY zsepex_t_ot FROM TABLE lt_ot.
    ENDIF.
  ENDMETHOD.

  METHOD set_status.
    DATA ls_cab TYPE zsepex_t_cab.

    ls_cab = ler_cab( iv_lgnum = iv_lgnum iv_vbeln = iv_vbeln ).
    CHECK ls_cab IS NOT INITIAL.
    ls_cab-status = iv_status.
    CASE iv_status.
      WHEN zif_sepex_const=>gc_status-virtual.
        ls_cab-dt_virt = sy-datum.
        ls_cab-hr_virt = sy-uzeit.
      WHEN zif_sepex_const=>gc_status-pgi.
        IF iv_data IS NOT INITIAL.
          ls_cab-dt_pgi = iv_data.
        ELSE.
          ls_cab-dt_pgi = sy-datum.
        ENDIF.
      WHEN zif_sepex_const=>gc_status-concluido.
        ls_cab-dt_concl = sy-datum.
    ENDCASE.
    gravar_cab( CHANGING cs_cab = ls_cab ).
  ENDMETHOD.

  METHOD bloquear.
    CALL FUNCTION 'ENQUEUE_EZSEPEX_CAB'
      EXPORTING
        lgnum          = iv_lgnum
        vbeln          = iv_vbeln
      EXCEPTIONS
        foreign_lock   = 1
        system_failure = 2
        OTHERS         = 3.
    IF sy-subrc <> 0.
      zcx_sepex=>raise_msg( iv_msgno = '015'
                            iv_msgv1 = iv_vbeln
                            iv_msgv2 = sy-msgv1 ).
    ENDIF.
  ENDMETHOD.

  METHOD desbloquear.
    CALL FUNCTION 'DEQUEUE_EZSEPEX_CAB'
      EXPORTING
        lgnum = iv_lgnum
        vbeln = iv_vbeln.
  ENDMETHOD.

  METHOD qtd_pendente_item.
    DATA ls_ot TYPE zsepex_t_ot.

    rv_qtd = is_itm-menge - is_itm-qtd_regul.
    " OT aberta já reserva a UD: não conta como pendente de reserva
    LOOP AT it_ot INTO ls_ot WHERE vbeln = is_itm-vbeln
                               AND posnr = is_itm-posnr
                               AND pquit = space.
      rv_qtd = rv_qtd - ls_ot-vsolm.
    ENDLOOP.
    IF rv_qtd < 0.
      rv_qtd = 0.
    ENDIF.
  ENDMETHOD.

  METHOD saldo_pendente.
    TYPES: BEGIN OF lty_key,
             lgnum TYPE lgnum,
             vbeln TYPE vbeln_vl,
           END OF lty_key.
    DATA: lt_itm     TYPE ty_t_itm,
          lt_ot      TYPE ty_t_ot,
          lt_cab_key TYPE STANDARD TABLE OF lty_key,
          ls_itm     TYPE zsepex_t_itm,
          ls_saldo   TYPE zsepex_s_saldo,
          lv_conc    TYPE zsepex_status.

    lv_conc = zif_sepex_const=>gc_status-concluido.

    " Cabeçalhos ainda abertos no depósito
    SELECT lgnum vbeln FROM zsepex_t_cab INTO TABLE lt_cab_key
      WHERE lgnum  = iv_lgnum
        AND status < lv_conc.
    IF lt_cab_key IS INITIAL.
      RETURN.
    ENDIF.
    SELECT * FROM zsepex_t_itm INTO TABLE lt_itm
      FOR ALL ENTRIES IN lt_cab_key
      WHERE lgnum  = lt_cab_key-lgnum
        AND vbeln  = lt_cab_key-vbeln
        AND status < lv_conc.
    IF iv_werks IS NOT INITIAL.
      DELETE lt_itm WHERE werks <> iv_werks.
    ENDIF.
    IF lt_itm IS INITIAL.
      RETURN.
    ENDIF.

    IF iv_so_sem_ot = 'X'.
      SELECT * FROM zsepex_t_ot INTO TABLE lt_ot
        FOR ALL ENTRIES IN lt_itm
        WHERE lgnum = lt_itm-lgnum
          AND vbeln = lt_itm-vbeln
          AND posnr = lt_itm-posnr
          AND pquit = space.
    ENDIF.

    LOOP AT lt_itm INTO ls_itm.
      CLEAR ls_saldo.
      ls_saldo-matnr = ls_itm-matnr.
      ls_saldo-werks = ls_itm-werks.
      ls_saldo-charg = ls_itm-charg.
      ls_saldo-meins = ls_itm-meins.
      IF iv_so_sem_ot = 'X'.
        ls_saldo-menge = qtd_pendente_item( is_itm = ls_itm it_ot = lt_ot ).
      ELSE.
        ls_saldo-menge = ls_itm-menge - ls_itm-qtd_regul.
      ENDIF.
      IF ls_saldo-menge > 0.
        COLLECT ls_saldo INTO rt_saldo.
      ENDIF.
    ENDLOOP.
  ENDMETHOD.

  METHOD texto_status.
    DATA ls_dd07v TYPE dd07v.

    IF gt_status_txt IS INITIAL.
      CALL FUNCTION 'DD_DOMVALUES_GET'
        EXPORTING
          domname        = 'ZSEPEX_D_STATUS'
          text           = 'X'
          langu          = sy-langu
        TABLES
          dd07v_tab      = gt_status_txt
        EXCEPTIONS
          wrong_textflag = 1
          OTHERS         = 2.
    ENDIF.
    READ TABLE gt_status_txt INTO ls_dd07v WITH KEY domvalue_l = iv_status.
    IF sy-subrc = 0.
      rv_texto = ls_dd07v-ddtext.
    ELSE.
      rv_texto = iv_status.
    ENDIF.
  ENDMETHOD.

ENDCLASS.

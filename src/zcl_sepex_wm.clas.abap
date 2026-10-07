"! Separação Express - encapsula as chamadas WM:
"! OT virtual da remessa (L_TO_CREATE_DN com origem manual + L_TO_CONFIRM),
"! OT de regularização (L_TO_CREATE_MULTIPLE por UD) e leitura de LTAP.
CLASS zcl_sepex_wm DEFINITION
  PUBLIC
  FINAL
  CREATE PUBLIC.

  PUBLIC SECTION.
    TYPES: BEGIN OF ty_item_lote,
             posnr TYPE posnr_vl,
             matnr TYPE matnr,
             werks TYPE werks_d,
             lgort TYPE lgort_d,
             charg TYPE charg_d,
             lfimg TYPE lfimg,
             meins TYPE meins,
           END OF ty_item_lote.
    TYPES ty_t_item_lote TYPE STANDARD TABLE OF ty_item_lote WITH DEFAULT KEY.
    TYPES ty_t_ltap TYPE STANDARD TABLE OF ltap WITH DEFAULT KEY.

    "! Itens de lote da remessa de saída: subitens de divisão de lote
    "! (POSNR >= 900000) ou itens principais já com lote e sem divisão.
    "! Só itens relevantes para picking (KOMKZ) e com quantidade.
    CLASS-METHODS ler_itens_lote
      IMPORTING
        !iv_vbeln       TYPE vbeln_vl
      RETURNING
        VALUE(rt_itens) TYPE ty_t_item_lote.

    "! Status da remessa (VBUK): picking, WM e movimento de mercadoria
    CLASS-METHODS ler_status_remessa
      IMPORTING
        !iv_vbeln TYPE vbeln_vl
      EXPORTING
        !ev_kostk TYPE kostk
        !ev_lvstk TYPE lvstk
        !ev_wbstk TYPE wbstk.

    "! OT da remessa com origem manual na posição virtual, um item por
    "! item de lote. Não confirma (ver confirmar_ot).
    CLASS-METHODS criar_ot_virtual
      IMPORTING
        !iv_lgnum        TYPE lgnum
        !iv_vbeln        TYPE vbeln_vl
        !iv_refnr        TYPE lvs_refnr OPTIONAL
        !is_par          TYPE zsepex_t_par
        !it_itens        TYPE ty_t_item_lote
      RETURNING
        VALUE(rv_tanum)  TYPE tanum
      RAISING
        zcx_sepex.

    "! Confirma a OT inteira (todos os itens abertos, qtd. teórica)
    CLASS-METHODS confirmar_ot
      IMPORTING
        !iv_lgnum TYPE lgnum
        !iv_tanum TYPE tanum
      RAISING
        zcx_sepex.

    "! OT de regularização: itens por UD (origem = UD, destino = posição
    "! virtual), tipo de movimento parametrizado, não confirmada.
    CLASS-METHODS criar_ot_regularizacao
      IMPORTING
        !iv_lgnum        TYPE lgnum
        !is_par          TYPE zsepex_t_par
        !it_ud           TYPE zsepex_t_ud_tt
      RETURNING
        VALUE(rv_tanum)  TYPE tanum
      RAISING
        zcx_sepex.

    CLASS-METHODS ler_ltap
      IMPORTING
        !iv_lgnum       TYPE lgnum
        !iv_tanum       TYPE tanum
      RETURNING
        VALUE(rt_ltap)  TYPE ty_t_ltap.

    "! Saldo (soma de LQUA-VERME) na posição virtual por material/lote
    CLASS-METHODS saldo_posicao_virtual
      IMPORTING
        !iv_lgnum        TYPE lgnum
        !is_par          TYPE zsepex_t_par
        !iv_matnr        TYPE matnr
        !iv_charg        TYPE charg_d
      RETURNING
        VALUE(rv_saldo)  TYPE zsepex_qtd.

  PROTECTED SECTION.
  PRIVATE SECTION.
ENDCLASS.


CLASS zcl_sepex_wm IMPLEMENTATION.

  METHOD ler_itens_lote.
    TYPES: BEGIN OF lty_lips,
             vbeln TYPE vbeln_vl,
             posnr TYPE posnr_vl,
             uecha TYPE uecha,
             matnr TYPE matnr,
             werks TYPE werks_d,
             lgort TYPE lgort_d,
             charg TYPE charg_d,
             lfimg TYPE lfimg,
             vrkme TYPE vrkme,
             komkz TYPE komkz,
           END OF lty_lips.
    DATA: lt_lips TYPE STANDARD TABLE OF lty_lips,
          ls_lips TYPE lty_lips,
          ls_item TYPE ty_item_lote.

    SELECT vbeln posnr uecha matnr werks lgort charg lfimg vrkme komkz
      FROM lips INTO TABLE lt_lips
      WHERE vbeln = iv_vbeln.
    IF sy-subrc <> 0.
      RETURN.
    ENDIF.

    LOOP AT lt_lips INTO ls_lips.
      IF ls_lips-lfimg <= 0 OR ls_lips-komkz IS INITIAL.
        CONTINUE.
      ENDIF.
      IF ls_lips-uecha IS INITIAL.
        " Item principal: só conta se não tem divisão de lote e tem lote
        READ TABLE lt_lips TRANSPORTING NO FIELDS WITH KEY uecha = ls_lips-posnr.
        IF sy-subrc = 0 OR ls_lips-charg IS INITIAL.
          CONTINUE.
        ENDIF.
      ELSEIF ls_lips-charg IS INITIAL.
        CONTINUE.
      ENDIF.
      CLEAR ls_item.
      ls_item-posnr = ls_lips-posnr.
      ls_item-matnr = ls_lips-matnr.
      ls_item-werks = ls_lips-werks.
      ls_item-lgort = ls_lips-lgort.
      ls_item-charg = ls_lips-charg.
      ls_item-lfimg = ls_lips-lfimg.
      ls_item-meins = ls_lips-vrkme.
      APPEND ls_item TO rt_itens.
    ENDLOOP.
    SORT rt_itens BY posnr.
  ENDMETHOD.

  METHOD ler_status_remessa.
    CLEAR: ev_kostk, ev_lvstk, ev_wbstk.
    SELECT SINGLE kostk lvstk wbstk FROM vbuk
      INTO (ev_kostk, ev_lvstk, ev_wbstk)
      WHERE vbeln = iv_vbeln.
  ENDMETHOD.

  METHOD criar_ot_virtual.
    DATA: lt_delit TYPE l03b_delit_t,
          ls_delit TYPE l03b_delit,
          ls_item  TYPE ty_item_lote,
          lv_tanum TYPE tanum.

    LOOP AT it_itens INTO ls_item.
      CLEAR ls_delit.
      ls_delit-posnr = ls_item-posnr.
      ls_delit-anfme = ls_item-lfimg.
      ls_delit-altme = ls_item-meins.
      ls_delit-vltyp = is_par-lgtyp_virt.
      ls_delit-vlber = is_par-lgber_virt.
      ls_delit-vlpla = is_par-lgpla_virt.
      APPEND ls_delit TO lt_delit.
    ENDLOOP.
    IF lt_delit IS INITIAL.
      zcx_sepex=>raise_msg( iv_msgno = '004' iv_msgv1 = iv_vbeln ).
    ENDIF.

    " Mesmo padrão do Z_WM_CONFIRMA_ICENTRO (carga fechada): origem
    " manual por item, sem confirmação na criação, commit explícito
    CALL FUNCTION 'L_TO_CREATE_DN'
      EXPORTING
        i_lgnum                    = iv_lgnum
        i_vbeln                    = iv_vbeln
        i_refnr                    = iv_refnr
        i_squit                    = space
        i_update_task              = space
        i_commit_work              = 'X'
        i_bname                    = sy-uname
        it_delit                   = lt_delit
      IMPORTING
        e_tanum                    = lv_tanum
      EXCEPTIONS
        foreign_lock               = 1
        dn_completed               = 2
        partial_delivery_forbidden = 3
        xfeld_wrong                = 4
        ldest_wrong                = 5
        drukz_wrong                = 6
        dn_wrong                   = 7
        squit_forbidden            = 8
        no_to_created              = 9
        teilk_wrong                = 10
        update_without_commit      = 11
        no_authority               = 12
        no_picking_allowed         = 13
        error_message              = 15
        OTHERS                     = 14.
    CASE sy-subrc.
      WHEN 0.
        rv_tanum = lv_tanum.
      WHEN 2.
        " Remessa já processada no WM: reaproveita a OT existente
        SELECT tanum FROM ltak INTO rv_tanum UP TO 1 ROWS
          WHERE lgnum = iv_lgnum
            AND vbeln = iv_vbeln
          ORDER BY tanum DESCENDING.
        ENDSELECT.
        IF rv_tanum IS INITIAL.
          zcx_sepex=>raise_msg( iv_msgno = '008' iv_msgv1 = iv_vbeln
                                iv_msgv2 = 'DN_COMPLETED sem OT' ).
        ENDIF.
      WHEN 15.
        zcx_sepex=>raise_sy( ).
      WHEN OTHERS.
        IF sy-msgid IS NOT INITIAL.
          zcx_sepex=>raise_sy( ).
        ENDIF.
        zcx_sepex=>raise_msg( iv_msgno = '008' iv_msgv1 = iv_vbeln
                              iv_msgv2 = 'L_TO_CREATE_DN'
                              iv_msgv3 = sy-subrc ).
    ENDCASE.
  ENDMETHOD.

  METHOD confirmar_ot.
    DATA: lt_ltap      TYPE ty_t_ltap,
          ls_ltap      TYPE ltap,
          lt_ltap_conf TYPE STANDARD TABLE OF ltap_conf,
          ls_ltap_conf TYPE ltap_conf.

    lt_ltap = ler_ltap( iv_lgnum = iv_lgnum iv_tanum = iv_tanum ).
    DELETE lt_ltap WHERE pquit = 'X'.
    IF lt_ltap IS INITIAL.
      RETURN.   " já confirmada
    ENDIF.

    LOOP AT lt_ltap INTO ls_ltap.
      CLEAR ls_ltap_conf.
      ls_ltap_conf-tanum = ls_ltap-tanum.
      ls_ltap_conf-tapos = ls_ltap-tapos.
      ls_ltap_conf-nista = ls_ltap-vsola.
      ls_ltap_conf-altme = ls_ltap-altme.
      APPEND ls_ltap_conf TO lt_ltap_conf.
    ENDLOOP.

    CALL FUNCTION 'L_TO_CONFIRM'
      EXPORTING
        i_lgnum                        = iv_lgnum
        i_tanum                        = iv_tanum
        i_quknz                        = zif_sepex_const=>gc_quknz
        i_commit_work                  = 'X'
      TABLES
        t_ltap_conf                    = lt_ltap_conf
      EXCEPTIONS
        two_step_confirmation_required = 8
        error_message                  = 15
        OTHERS                         = 14.
    IF sy-subrc <> 0.
      IF sy-msgid IS NOT INITIAL.
        zcx_sepex=>raise_sy( ).
      ENDIF.
      zcx_sepex=>raise_msg( iv_msgno = '009' iv_msgv1 = iv_tanum
                            iv_msgv2 = 'L_TO_CONFIRM' iv_msgv3 = sy-subrc ).
    ENDIF.
  ENDMETHOD.

  METHOD criar_ot_regularizacao.
    DATA: lt_creat TYPE STANDARD TABLE OF ltap_creat,
          ls_creat TYPE ltap_creat,
          ls_ud    TYPE zsepex_s_ud,
          lv_tanum TYPE tanum.

    LOOP AT it_ud INTO ls_ud.
      CLEAR ls_creat.
      ls_creat-matnr = ls_ud-matnr.
      ls_creat-werks = ls_ud-werks.
      ls_creat-lgort = ls_ud-lgort.
      ls_creat-charg = ls_ud-charg.
      ls_creat-anfme = ls_ud-menge.
      ls_creat-altme = ls_ud-meins.
      ls_creat-vltyp = ls_ud-lgtyp.
      ls_creat-vlpla = ls_ud-lgpla.
      ls_creat-vlenr = ls_ud-lenum.
      ls_creat-nltyp = is_par-lgtyp_virt.
      ls_creat-nlber = is_par-lgber_virt.
      ls_creat-nlpla = is_par-lgpla_virt.
      APPEND ls_creat TO lt_creat.
    ENDLOOP.
    IF lt_creat IS INITIAL.
      RETURN.
    ENDIF.

    CALL FUNCTION 'L_TO_CREATE_MULTIPLE'
      EXPORTING
        i_lgnum               = iv_lgnum
        i_bwlvs               = is_par-bwlvs_reg
        i_squit               = space
        i_commit_work         = 'X'
        i_bname               = sy-uname
      IMPORTING
        e_tanum               = lv_tanum
      TABLES
        t_ltap_creat          = lt_creat
      EXCEPTIONS
        no_to_created         = 1
        bwlvs_wrong           = 2
        betyp_wrong           = 3
        benum_missing         = 4
        betyp_missing         = 5
        foreign_lock          = 6
        vltyp_wrong           = 7
        vlpla_wrong           = 8
        vltyp_missing         = 9
        nltyp_wrong           = 10
        nlpla_wrong           = 11
        nltyp_missing         = 12
        rltyp_wrong           = 13
        rlpla_wrong           = 14
        rltyp_missing         = 15
        squit_forbidden       = 16
        manual_to_forbidden   = 17
        letyp_wrong           = 18
        vlpla_missing         = 19
        nlpla_missing         = 20
        sobkz_wrong           = 21
        sobkz_missing         = 22
        sonum_missing         = 23
        bestq_wrong           = 24
        lgber_wrong           = 25
        xfeld_wrong           = 26
        date_wrong            = 27
        drukz_wrong           = 28
        ldest_wrong           = 29
        update_without_commit = 30
        no_authority          = 31
        material_not_found    = 32
        lenum_wrong           = 33
        error_message         = 35
        OTHERS                = 34.
    IF sy-subrc <> 0.
      IF sy-msgid IS NOT INITIAL.
        zcx_sepex=>raise_sy( ).
      ENDIF.
      zcx_sepex=>raise_msg( iv_msgno = '013' iv_msgv1 = 'L_TO_CREATE_MULTIPLE'
                            iv_msgv2 = sy-subrc ).
    ENDIF.
    rv_tanum = lv_tanum.
  ENDMETHOD.

  METHOD ler_ltap.
    SELECT * FROM ltap INTO TABLE rt_ltap
      WHERE lgnum = iv_lgnum
        AND tanum = iv_tanum
      ORDER BY PRIMARY KEY.
  ENDMETHOD.

  METHOD saldo_posicao_virtual.
    SELECT SUM( verme ) FROM lqua INTO rv_saldo
      WHERE lgnum = iv_lgnum
        AND lgtyp = is_par-lgtyp_virt
        AND lgpla = is_par-lgpla_virt
        AND matnr = iv_matnr
        AND charg = iv_charg.
  ENDMETHOD.

ENDCLASS.

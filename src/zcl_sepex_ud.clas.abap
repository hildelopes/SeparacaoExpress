"! Separação Express - seleção de UDs/quants para a OT de regularização.
"! Regras do armazém (mesmas da separação normal e da paletização do
"! monitor ZWMR0010):
"!  1. Paletes inteiros saem das posições (tipos da ZSEPEX_T_PAR_LT):
"!     só UD com saldo >= paletização (MLGN-LHMG1), sem OT aberta na UD
"!     e sem bloqueio da posição; mais antigas primeiro.
"!  2. O resto (fração de palete) sai do avulso (tipo de depósito
"!     ZSEPEX_T_PAR-LGTYP_AVS, posição fixa da MLGT), de qualquer quant
"!     do lote.
"!  3. Se o avulso não cobre: com UD_PARCIAL = X tira o resto de uma UD
"!     de posição (parcial); senão fica pendente e EV_FALTA_AVULSO
"!     informa a quantidade para o reabastecimento (NT 919).
"! Material sem paletização: qualquer quant, parcial permitido.
CLASS zcl_sepex_ud DEFINITION
  PUBLIC
  FINAL
  CREATE PUBLIC.

  PUBLIC SECTION.
    TYPES ty_t_lenum TYPE STANDARD TABLE OF lenum WITH DEFAULT KEY.

    "! Seleciona UDs/quants para material/centro/lote até cobrir iv_menge
    "! (na unidade iv_meins). ev_falta recebe o que não foi coberto;
    "! ev_falta_avulso, a parte de ev_falta que é fração de palete e
    "! deveria vir do avulso (candidata a reabastecimento); ev_lhmg1, a
    "! paletização na unidade do item (0 = sem paletização).
    CLASS-METHODS selecionar
      IMPORTING
        !iv_lgnum  TYPE lgnum
        !iv_matnr  TYPE matnr
        !iv_werks  TYPE werks_d
        !iv_charg  TYPE charg_d
        !iv_menge  TYPE zsepex_qtd
        !iv_meins  TYPE meins
        !it_lgtyp  TYPE zsepex_t_par_lt_tt
        !it_excluir_lenum TYPE ty_t_lenum OPTIONAL
        !iv_lgtyp_avs  TYPE lgtyp OPTIONAL
        !iv_ud_parcial TYPE xfeld OPTIONAL
      EXPORTING
        !et_ud     TYPE zsepex_t_ud_tt
        !ev_falta  TYPE zsepex_qtd
        !ev_falta_avulso TYPE zsepex_qtd
        !ev_lhmg1  TYPE zsepex_qtd
      RAISING
        zcx_sepex.

    "! Converte quantidade entre unidades do material
    CLASS-METHODS converter
      IMPORTING
        !iv_matnr      TYPE matnr
        !iv_de         TYPE meins
        !iv_para       TYPE meins
        !iv_menge      TYPE zsepex_qtd
      RETURNING
        VALUE(rv_qtd)  TYPE zsepex_qtd.

  PROTECTED SECTION.
  PRIVATE SECTION.
    TYPES: BEGIN OF ty_lqua,
             lgnum TYPE lgnum,
             lqnum TYPE lqua-lqnum,
             matnr TYPE matnr,
             werks TYPE werks_d,
             lgort TYPE lgort_d,
             charg TYPE charg_d,
             lgtyp TYPE lgtyp,
             lgpla TYPE lgpla,
             lenum TYPE lenum,
             verme TYPE lqua-verme,
             meins TYPE meins,
             edatu TYPE lqua-edatu,
             prio  TYPE numc2,
             avulso TYPE xfeld,
           END OF ty_lqua.
    TYPES ty_t_lqua TYPE STANDARD TABLE OF ty_lqua WITH DEFAULT KEY.

    CLASS-METHODS filtrar_disponiveis
      CHANGING
        !ct_lqua TYPE ty_t_lqua.
ENDCLASS.


CLASS zcl_sepex_ud IMPLEMENTATION.

  METHOD converter.
    DATA: lv_in  TYPE ekpo-menge,
          lv_out TYPE ekpo-menge.

    IF iv_de = iv_para OR iv_de IS INITIAL OR iv_para IS INITIAL.
      rv_qtd = iv_menge.
      RETURN.
    ENDIF.
    lv_in = iv_menge.
    CALL FUNCTION 'MD_CONVERT_MATERIAL_UNIT'
      EXPORTING
        i_matnr              = iv_matnr
        i_in_me              = iv_de
        i_out_me             = iv_para
        i_menge              = lv_in
      IMPORTING
        e_menge              = lv_out
      EXCEPTIONS
        error_in_application = 1
        error                = 2
        OTHERS               = 3.
    IF sy-subrc <> 0.
      rv_qtd = iv_menge.
    ELSE.
      rv_qtd = lv_out.
    ENDIF.
  ENDMETHOD.

  METHOD filtrar_disponiveis.
    TYPES: BEGIN OF lty_ltap,
             lgnum TYPE lgnum,
             vlenr TYPE ltap-vlenr,
             nlenr TYPE ltap-nlenr,
           END OF lty_ltap,
           BEGIN OF lty_lagp,
             lgnum TYPE lgnum,
             lgtyp TYPE lgtyp,
             lgpla TYPE lgpla,
             skzua TYPE lagp-skzua,
             skzue TYPE lagp-skzue,
             skzsa TYPE lagp-skzsa,
             skzse TYPE lagp-skzse,
             spgru TYPE lagp-spgru,
           END OF lty_lagp.
    DATA: lt_ltap TYPE STANDARD TABLE OF lty_ltap,
          lt_lagp TYPE STANDARD TABLE OF lty_lagp,
          ls_lagp TYPE lty_lagp.
    FIELD-SYMBOLS <ls_lqua> TYPE ty_lqua.

    DELETE ct_lqua WHERE verme <= 0.
    IF ct_lqua IS INITIAL.
      RETURN.
    ENDIF.

    " OTs abertas que usam a UD como origem ou destino
    SELECT lgnum vlenr nlenr FROM ltap INTO TABLE lt_ltap
      FOR ALL ENTRIES IN ct_lqua
      WHERE lgnum = ct_lqua-lgnum
        AND pquit = space
        AND ( vlenr = ct_lqua-lenum OR nlenr = ct_lqua-lenum ).
    SORT lt_ltap BY lgnum vlenr nlenr.

    " Bloqueios da posição (saída e geral)
    SELECT lgnum lgtyp lgpla skzua skzue skzsa skzse spgru
      FROM lagp INTO TABLE lt_lagp
      FOR ALL ENTRIES IN ct_lqua
      WHERE lgnum = ct_lqua-lgnum
        AND lgtyp = ct_lqua-lgtyp
        AND lgpla = ct_lqua-lgpla.
    SORT lt_lagp BY lgnum lgtyp lgpla.

    LOOP AT ct_lqua ASSIGNING <ls_lqua>.
      IF <ls_lqua>-lenum IS NOT INITIAL.
        READ TABLE lt_ltap TRANSPORTING NO FIELDS
          WITH KEY lgnum = <ls_lqua>-lgnum vlenr = <ls_lqua>-lenum.
        IF sy-subrc <> 0.
          READ TABLE lt_ltap TRANSPORTING NO FIELDS
            WITH KEY lgnum = <ls_lqua>-lgnum nlenr = <ls_lqua>-lenum.
        ENDIF.
        IF sy-subrc = 0.
          DELETE ct_lqua.
          CONTINUE.
        ENDIF.
      ENDIF.
      READ TABLE lt_lagp INTO ls_lagp
        WITH KEY lgnum = <ls_lqua>-lgnum lgtyp = <ls_lqua>-lgtyp
                 lgpla = <ls_lqua>-lgpla BINARY SEARCH.
      IF sy-subrc = 0 AND ( ls_lagp-skzua IS NOT INITIAL
                         OR ls_lagp-skzsa IS NOT INITIAL
                         OR ls_lagp-spgru IS NOT INITIAL ).
        DELETE ct_lqua.
      ENDIF.
    ENDLOOP.
  ENDMETHOD.

  METHOD selecionar.
    DATA: lt_lqua   TYPE ty_t_lqua,
          lt_avs    TYPE ty_t_lqua,
          ls_lgtyp  TYPE zsepex_t_par_lt,
          lr_lgtyp  TYPE RANGE OF lgtyp,
          ls_rlgtyp LIKE LINE OF lr_lgtyp,
          ls_ud     TYPE zsepex_s_ud,
          lv_resto  TYPE zsepex_qtd,
          lv_qtd    TYPE zsepex_qtd,
          lv_lhmg1  TYPE zsepex_qtd,
          lv_meins_wm TYPE meins.
    FIELD-SYMBOLS <ls_lqua> TYPE ty_lqua.

    CLEAR: et_ud, ev_falta, ev_falta_avulso, ev_lhmg1.
    lv_resto = iv_menge.
    IF lv_resto <= 0.
      RETURN.
    ENDIF.

    LOOP AT it_lgtyp INTO ls_lgtyp.
      ls_rlgtyp-sign = 'I'. ls_rlgtyp-option = 'EQ'. ls_rlgtyp-low = ls_lgtyp-lgtyp.
      APPEND ls_rlgtyp TO lr_lgtyp.
    ENDLOOP.
    IF lr_lgtyp IS INITIAL.
      zcx_sepex=>raise_msg( iv_msgno = '026' iv_msgv1 = iv_lgnum ).
    ENDIF.

    " Quants das posições (tipos de depósito com UD)
    SELECT lgnum lqnum matnr werks lgort charg lgtyp lgpla lenum verme meins edatu
      FROM lqua INTO CORRESPONDING FIELDS OF TABLE lt_lqua
      WHERE lgnum = iv_lgnum
        AND matnr = iv_matnr
        AND werks = iv_werks
        AND charg = iv_charg
        AND lgtyp IN lr_lgtyp
        AND bestq = space
        AND sobkz = space
        AND verme > 0.

    " Quants do avulso (posição fixa, sem UD). LQUA-VERME já desconta o
    " que está em OT aberta a partir da posição.
    IF iv_lgtyp_avs IS NOT INITIAL.
      SELECT lgnum lqnum matnr werks lgort charg lgtyp lgpla lenum verme meins edatu
        FROM lqua INTO CORRESPONDING FIELDS OF TABLE lt_avs
        WHERE lgnum = iv_lgnum
          AND matnr = iv_matnr
          AND werks = iv_werks
          AND charg = iv_charg
          AND lgtyp = iv_lgtyp_avs
          AND bestq = space
          AND sobkz = space
          AND verme > 0.
      LOOP AT lt_avs ASSIGNING <ls_lqua>.
        <ls_lqua>-avulso = 'X'.
        <ls_lqua>-prio   = '99'.
      ENDLOOP.
      APPEND LINES OF lt_avs TO lt_lqua.
    ENDIF.

    IF lt_lqua IS INITIAL.
      ev_falta = lv_resto.
      RETURN.
    ENDIF.

    " UDs já usadas em outra OT desta execução (ainda não gravadas)
    IF it_excluir_lenum IS NOT INITIAL.
      LOOP AT lt_lqua ASSIGNING <ls_lqua> WHERE lenum <> space.
        READ TABLE it_excluir_lenum TRANSPORTING NO FIELDS
          WITH KEY table_line = <ls_lqua>-lenum.
        IF sy-subrc = 0.
          DELETE lt_lqua.
        ENDIF.
      ENDLOOP.
    ENDIF.

    filtrar_disponiveis( CHANGING ct_lqua = lt_lqua ).
    IF lt_lqua IS INITIAL.
      ev_falta = lv_resto.
      RETURN.
    ENDIF.

    " Quantidade por UD (palete cheio) e unidade WM do material
    SELECT SINGLE lhmg1 lhme1 FROM mlgn INTO (lv_lhmg1, lv_meins_wm)
      WHERE matnr = iv_matnr
        AND lgnum = iv_lgnum.
    IF sy-subrc = 0 AND lv_lhmg1 > 0.
      lv_lhmg1 = converter( iv_matnr = iv_matnr iv_de = lv_meins_wm
                            iv_para = iv_meins iv_menge = lv_lhmg1 ).
    ELSE.
      CLEAR lv_lhmg1.
    ENDIF.
    ev_lhmg1 = lv_lhmg1.

    " Quantidades na unidade do item; prioridade do tipo de depósito;
    " mais antigas primeiro (avulso por último, prio 99)
    LOOP AT lt_lqua ASSIGNING <ls_lqua>.
      <ls_lqua>-verme = converter( iv_matnr = iv_matnr iv_de = <ls_lqua>-meins
                                   iv_para = iv_meins iv_menge = <ls_lqua>-verme ).
      <ls_lqua>-meins = iv_meins.
      IF <ls_lqua>-avulso = space.
        READ TABLE it_lgtyp INTO ls_lgtyp WITH KEY lgtyp = <ls_lqua>-lgtyp.
        IF sy-subrc = 0.
          <ls_lqua>-prio = ls_lgtyp-prioridade.
        ENDIF.
      ENDIF.
    ENDLOOP.
    SORT lt_lqua BY prio edatu lqnum.

    " 1ª passada: paletes inteiros das posições (saldo >= paletização,
    " quando conhecida) que cabem inteiros no resto
    LOOP AT lt_lqua ASSIGNING <ls_lqua> WHERE avulso = space.
      IF lv_resto <= 0.
        EXIT.
      ENDIF.
      IF lv_lhmg1 > 0 AND <ls_lqua>-verme < lv_lhmg1.
        CONTINUE.
      ENDIF.
      IF <ls_lqua>-verme > lv_resto.
        CONTINUE.
      ENDIF.
      CLEAR ls_ud.
      MOVE-CORRESPONDING <ls_lqua> TO ls_ud.
      ls_ud-menge   = <ls_lqua>-verme.
      ls_ud-meins   = iv_meins.
      ls_ud-inteira = 'X'.
      APPEND ls_ud TO et_ud.
      lv_resto = lv_resto - <ls_lqua>-verme.
      CLEAR <ls_lqua>-verme.
    ENDLOOP.

    " 2ª passada: resto a partir do avulso (qualquer quant do lote)
    LOOP AT lt_lqua ASSIGNING <ls_lqua> WHERE avulso = 'X' AND verme > 0.
      IF lv_resto <= 0.
        EXIT.
      ENDIF.
      IF <ls_lqua>-verme >= lv_resto.
        lv_qtd = lv_resto.
      ELSE.
        lv_qtd = <ls_lqua>-verme.
      ENDIF.
      CLEAR ls_ud.
      MOVE-CORRESPONDING <ls_lqua> TO ls_ud.
      ls_ud-menge = lv_qtd.
      ls_ud-meins = iv_meins.
      APPEND ls_ud TO et_ud.
      lv_resto = lv_resto - lv_qtd.
      <ls_lqua>-verme = <ls_lqua>-verme - lv_qtd.
    ENDLOOP.

    " 3ª passada: resto de uma UD de posição (parcial). Só quando o
    " material não tem paletização ou o parâmetro UD_PARCIAL permite.
    IF lv_resto > 0 AND ( lv_lhmg1 = 0 OR iv_ud_parcial = 'X' ).
      LOOP AT lt_lqua ASSIGNING <ls_lqua> WHERE avulso = space AND verme > 0.
        IF lv_resto <= 0.
          EXIT.
        ENDIF.
        IF <ls_lqua>-verme >= lv_resto.
          lv_qtd = lv_resto.
        ELSE.
          lv_qtd = <ls_lqua>-verme.
        ENDIF.
        CLEAR ls_ud.
        MOVE-CORRESPONDING <ls_lqua> TO ls_ud.
        ls_ud-menge = lv_qtd.
        ls_ud-meins = iv_meins.
        IF lv_qtd = <ls_lqua>-verme.
          ls_ud-inteira = 'X'.
        ENDIF.
        APPEND ls_ud TO et_ud.
        lv_resto = lv_resto - lv_qtd.
        <ls_lqua>-verme = <ls_lqua>-verme - lv_qtd.
      ENDLOOP.
    ENDIF.

    IF lv_resto > 0.
      ev_falta = lv_resto.
      " Fração de palete não coberta: deveria sair do avulso
      IF lv_lhmg1 > 0.
        ev_falta_avulso = lv_resto MOD lv_lhmg1.
      ENDIF.
    ENDIF.
  ENDMETHOD.

ENDCLASS.

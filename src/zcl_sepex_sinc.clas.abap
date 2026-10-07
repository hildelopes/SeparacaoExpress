"! Separação Express - sincroniza o controle com o WM e a remessa:
"! confirmações/diferenças das OTs de regularização (LTAP), saída de
"! mercadoria da remessa (VBUK) e fechamento quando tudo foi
"! regularizado. Usada pelo job ZSEPEX04 e pela ZSEPEX02.
CLASS zcl_sepex_sinc DEFINITION
  PUBLIC
  FINAL
  CREATE PUBLIC.

  PUBLIC SECTION.
    "! Sincroniza uma remessa. Retorna o status final. COMMIT próprio.
    CLASS-METHODS sincronizar_remessa
      IMPORTING
        !iv_lgnum        TYPE lgnum
        !iv_vbeln        TYPE vbeln_vl
        !io_log          TYPE REF TO zcl_sepex_log OPTIONAL
      RETURNING
        VALUE(rv_status) TYPE zsepex_status
      RAISING
        zcx_sepex.

    "! Sincroniza todos os processos abertos do depósito (ou de todos)
    CLASS-METHODS sincronizar_todos
      IMPORTING
        !iv_lgnum      TYPE lgnum OPTIONAL
        !io_log        TYPE REF TO zcl_sepex_log
      EXPORTING
        !ev_processados TYPE i
        !ev_concluidos  TYPE i.

  PROTECTED SECTION.
  PRIVATE SECTION.
ENDCLASS.


CLASS zcl_sepex_sinc IMPLEMENTATION.

  METHOD sincronizar_remessa.
    DATA: ls_cab      TYPE zsepex_t_cab,
          lt_itm      TYPE zsepex_t_itm_tt,
          lt_ot       TYPE zsepex_t_ot_tt,
          ls_ot       TYPE zsepex_t_ot,
          lt_ltap     TYPE zcl_sepex_wm=>ty_t_ltap,
          ls_ltap     TYPE ltap,
          lv_kostk    TYPE kostk,
          lv_lvstk    TYPE lvstk,
          lv_wbstk    TYPE wbstk,
          lv_wadat    TYPE wadat_ist,
          lv_tanum    TYPE tanum,
          lv_tem_ot   TYPE xfeld,
          lv_tem_reg  TYPE xfeld,
          lv_tudo_ok  TYPE xfeld,
          lv_pend     TYPE i,
          lv_regul    TYPE i,
          lv_status   TYPE zsepex_status.
    FIELD-SYMBOLS: <ls_itm> TYPE zsepex_t_itm,
                   <ls_ot>  TYPE zsepex_t_ot.

    ls_cab = zcl_sepex_controle=>ler_cab( iv_lgnum = iv_lgnum iv_vbeln = iv_vbeln ).
    IF ls_cab IS INITIAL.
      zcx_sepex=>raise_msg( iv_msgno = '002' iv_msgv1 = iv_vbeln ).
    ENDIF.
    rv_status = ls_cab-status.
    IF ls_cab-status = zif_sepex_const=>gc_status-concluido
       OR ls_cab-status = zif_sepex_const=>gc_status-cancelado.
      RETURN.
    ENDIF.

    zcl_sepex_controle=>bloquear( iv_lgnum = iv_lgnum iv_vbeln = iv_vbeln ).

    lt_itm = zcl_sepex_controle=>ler_itens( iv_lgnum = iv_lgnum iv_vbeln = iv_vbeln ).
    lt_ot  = zcl_sepex_controle=>ler_ots( iv_lgnum = iv_lgnum iv_vbeln = iv_vbeln ).

    " ---- OTs de regularização: confirmação, diferença, estorno
    LOOP AT lt_ot ASSIGNING <ls_ot>.
      IF <ls_ot>-tanum <> lv_tanum.
        lv_tanum = <ls_ot>-tanum.
        lt_ltap = zcl_sepex_wm=>ler_ltap( iv_lgnum = iv_lgnum iv_tanum = lv_tanum ).
      ENDIF.
      READ TABLE lt_ltap INTO ls_ltap WITH KEY tanum = <ls_ot>-tanum tapos = <ls_ot>-tapos.
      IF sy-subrc <> 0.
        CONTINUE.
      ENDIF.
      IF ls_ltap-vorga = 'ST'.
        " OT estornada (LT15): item volta a pendente
        IF <ls_ot>-pquit <> 'X' OR <ls_ot>-nistm <> 0.
          <ls_ot>-pquit = 'X'.
          <ls_ot>-nistm = 0.
          <ls_ot>-ndifa = 0.
          IF io_log IS BOUND.
            io_log->add_msg( iv_msgty = 'W' iv_msgno = '028' iv_msgv1 = <ls_ot>-tanum
                             iv_msgv2 = <ls_ot>-posnr iv_msgv3 = <ls_ot>-vbeln ).
          ENDIF.
        ENDIF.
        CONTINUE.
      ENDIF.
      IF ls_ltap-pquit = 'X' AND <ls_ot>-pquit <> 'X'.
        <ls_ot>-pquit = 'X'.
        <ls_ot>-nistm = ls_ltap-nistm.
        <ls_ot>-ndifa = ls_ltap-ndifa.
        <ls_ot>-qdatu = ls_ltap-qdatu.
        <ls_ot>-qname = ls_ltap-qname.
        IF ls_ltap-ndifa <> 0 AND io_log IS BOUND.
          io_log->add_msg( iv_msgty = 'W' iv_msgno = '020' iv_msgv1 = <ls_ot>-tanum
                           iv_msgv2 = <ls_ot>-tapos iv_msgv3 = ls_ltap-ndifa iv_msgv4 = ls_ltap-altme ).
        ENDIF.
      ENDIF.
    ENDLOOP.
    zcl_sepex_controle=>gravar_ots( lt_ot ).

    " ---- Itens: quantidade regularizada = soma das OTs confirmadas
    lv_tudo_ok = 'X'.
    LOOP AT lt_itm ASSIGNING <ls_itm>.
      CLEAR <ls_itm>-qtd_regul.
      LOOP AT lt_ot INTO ls_ot WHERE vbeln = <ls_itm>-vbeln
                                 AND posnr = <ls_itm>-posnr.
        lv_tem_ot = 'X'.
        IF ls_ot-pquit = 'X'.
          <ls_itm>-qtd_regul = <ls_itm>-qtd_regul + ls_ot-nistm.
        ENDIF.
      ENDLOOP.
      IF <ls_itm>-qtd_regul >= <ls_itm>-menge.
        <ls_itm>-status = zif_sepex_const=>gc_status-concluido.
        lv_regul = lv_regul + 1.
      ELSE.
        lv_tudo_ok = space.
        lv_pend = lv_pend + 1.
        IF <ls_itm>-qtd_regul > 0.
          lv_tem_reg = 'X'.
          <ls_itm>-status = zif_sepex_const=>gc_status-em_regul.
        ELSEIF lv_tem_ot = 'X'.
          <ls_itm>-status = zif_sepex_const=>gc_status-ot_regul.
        ELSE.
          <ls_itm>-status = zif_sepex_const=>gc_status-virtual.
        ENDIF.
      ENDIF.
    ENDLOOP.
    zcl_sepex_controle=>gravar_itens( lt_itm ).

    " ---- Remessa: saída de mercadoria (e estorno)
    zcl_sepex_wm=>ler_status_remessa( EXPORTING iv_vbeln = iv_vbeln
                                      IMPORTING ev_kostk = lv_kostk
                                                ev_lvstk = lv_lvstk
                                                ev_wbstk = lv_wbstk ).
    IF lv_wbstk = 'C' AND ls_cab-dt_pgi IS INITIAL.
      SELECT SINGLE wadat_ist FROM likp INTO lv_wadat WHERE vbeln = iv_vbeln.
      IF lv_wadat IS INITIAL.
        lv_wadat = sy-datum.
      ENDIF.
      ls_cab-dt_pgi = lv_wadat.
      IF io_log IS BOUND.
        io_log->add_msg( iv_msgno = '025' iv_msgv1 = iv_vbeln iv_msgv2 = lv_wadat ).
      ENDIF.
    ELSEIF lv_wbstk <> 'C' AND ls_cab-dt_pgi IS NOT INITIAL.
      " Saída estornada depois de registrada: processo cancelado; as OTs
      " de regularização abertas devem ser estornadas (LT15) pela logística
      ls_cab-status = zif_sepex_const=>gc_status-cancelado.
      zcl_sepex_controle=>gravar_cab( CHANGING cs_cab = ls_cab ).
      COMMIT WORK AND WAIT.
      zcl_sepex_controle=>desbloquear( iv_lgnum = iv_lgnum iv_vbeln = iv_vbeln ).
      IF io_log IS BOUND.
        io_log->add_msg( iv_msgty = 'W' iv_msgno = '019' iv_msgv1 = iv_vbeln ).
      ENDIF.
      rv_status = ls_cab-status.
      RETURN.
    ENDIF.

    " ---- Status do cabeçalho
    IF lv_tudo_ok = 'X' AND lt_itm IS NOT INITIAL.
      lv_status = zif_sepex_const=>gc_status-concluido.
      ls_cab-dt_concl = sy-datum.
    ELSEIF lv_tem_reg = 'X'.
      lv_status = zif_sepex_const=>gc_status-em_regul.
    ELSEIF ls_cab-dt_pgi IS NOT INITIAL.
      lv_status = zif_sepex_const=>gc_status-pgi.
    ELSEIF lv_tem_ot = 'X'.
      lv_status = zif_sepex_const=>gc_status-ot_regul.
    ELSE.
      lv_status = zif_sepex_const=>gc_status-virtual.
    ENDIF.
    ls_cab-status = lv_status.
    zcl_sepex_controle=>gravar_cab( CHANGING cs_cab = ls_cab ).
    COMMIT WORK AND WAIT.
    zcl_sepex_controle=>desbloquear( iv_lgnum = iv_lgnum iv_vbeln = iv_vbeln ).

    IF io_log IS BOUND.
      IF lv_status = zif_sepex_const=>gc_status-concluido.
        io_log->add_msg( iv_msgno = '018' iv_msgv1 = iv_vbeln ).
      ELSE.
        io_log->add_msg( iv_msgno = '017' iv_msgv1 = iv_vbeln
                         iv_msgv2 = lv_regul iv_msgv3 = lv_pend ).
      ENDIF.
    ENDIF.
    rv_status = lv_status.
  ENDMETHOD.

  METHOD sincronizar_todos.
    DATA: lt_cab    TYPE zsepex_t_cab_tt,
          ls_cab    TYPE zsepex_t_cab,
          lr_status TYPE RANGE OF zsepex_status,
          ls_rst    LIKE LINE OF lr_status,
          lx_erro   TYPE REF TO zcx_sepex,
          lv_status TYPE zsepex_status.

    CLEAR: ev_processados, ev_concluidos.
    ls_rst-sign = 'I'. ls_rst-option = 'BT'.
    ls_rst-low  = zif_sepex_const=>gc_status-virtual.
    ls_rst-high = zif_sepex_const=>gc_status-em_regul.
    APPEND ls_rst TO lr_status.

    lt_cab = zcl_sepex_controle=>ler_cabs_por_status( iv_lgnum  = iv_lgnum
                                                     it_status = lr_status ).
    LOOP AT lt_cab INTO ls_cab.
      TRY.
          lv_status = sincronizar_remessa( iv_lgnum = ls_cab-lgnum
                                           iv_vbeln = ls_cab-vbeln
                                           io_log   = io_log ).
          ev_processados = ev_processados + 1.
          IF lv_status = zif_sepex_const=>gc_status-concluido.
            ev_concluidos = ev_concluidos + 1.
          ENDIF.
        CATCH zcx_sepex INTO lx_erro.
          io_log->add_excecao( lx_erro ).
      ENDTRY.
    ENDLOOP.
  ENDMETHOD.

ENDCLASS.

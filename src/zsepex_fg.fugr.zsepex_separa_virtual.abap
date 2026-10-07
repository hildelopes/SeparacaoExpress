FUNCTION zsepex_separa_virtual.
*"----------------------------------------------------------------------
*"*"Interface local:
*"  IMPORTING
*"     REFERENCE(I_LGNUM) TYPE  LGNUM
*"     REFERENCE(I_VBELN) TYPE  VBELN_VL
*"     REFERENCE(I_REFNR) TYPE  LVS_REFNR OPTIONAL
*"     REFERENCE(I_ORIGEM) TYPE  ZSEPEX_ORIGEM
*"     REFERENCE(I_ORIGEM_ID) TYPE  ZSEPEX_ORIGEM_ID OPTIONAL
*"     REFERENCE(I_TKNUM) TYPE  TKNUM OPTIONAL
*"     REFERENCE(I_CRIAR_OT_REGUL) TYPE  XFELD DEFAULT ' '
*"  EXPORTING
*"     REFERENCE(E_TANUM) TYPE  TANUM
*"     REFERENCE(E_TANUM_REGUL) TYPE  TANUM
*"  TABLES
*"      T_RETURN STRUCTURE  BAPIRET2 OPTIONAL
*"  EXCEPTIONS
*"      E_ERRO
*"----------------------------------------------------------------------
* Separação virtual da remessa de saída do DPFE:
*  1. valida parâmetros, remessa (sem PGI) e itens com lote;
*  2. cria a OT da remessa com origem manual na posição virtual
*     (9EX/EXPRESS) e a confirma -> quant negativo por material/lote;
*  3. grava ZSEPEX_T_CAB (status 1) e ZSEPEX_T_ITM;
*  4. se OT_IMEDIATA (parâmetro) ou I_CRIAR_OT_REGUL, cria a OT de
*     regularização (reserva das UDs) -> status 2.
* Idempotente: remessa já registrada só repete a etapa que faltou.
*----------------------------------------------------------------------
  DATA: lo_log    TYPE REF TO zcl_sepex_log,
        lx_erro   TYPE REF TO zcx_sepex,
        ls_par    TYPE zsepex_t_par,
        ls_cab    TYPE zsepex_t_cab,
        lt_itm    TYPE zsepex_t_itm_tt,
        ls_itm    TYPE zsepex_t_itm,
        lt_itens  TYPE zcl_sepex_wm=>ty_t_item_lote,
        ls_item   TYPE zcl_sepex_wm=>ty_item_lote,
        lt_ltap   TYPE zcl_sepex_wm=>ty_t_ltap,
        ls_ltap   TYPE ltap,
        lv_kostk  TYPE kostk,
        lv_lvstk  TYPE lvstk,
        lv_wbstk  TYPE wbstk,
        lv_tanum  TYPE tanum,
        lv_werks  TYPE werks_d,
        lv_bloq   TYPE xfeld,
        lt_ret    TYPE bapiret2_t,
        ls_ret    TYPE bapiret2.

  CLEAR: e_tanum, e_tanum_regul, t_return[].
  CREATE OBJECT lo_log EXPORTING iv_extnumber = i_vbeln.

  TRY.
      ls_par = zcl_sepex_controle=>ler_param( i_lgnum ).

      zcl_sepex_controle=>bloquear( iv_lgnum = i_lgnum iv_vbeln = i_vbeln ).
      lv_bloq = 'X'.

      " Remessa existe e ainda sem saída de mercadoria
      SELECT SINGLE werks FROM lips INTO lv_werks
        WHERE vbeln = i_vbeln.
      IF sy-subrc <> 0.
        zcx_sepex=>raise_msg( iv_msgno = '002' iv_msgv1 = i_vbeln ).
      ENDIF.
      zcl_sepex_wm=>ler_status_remessa( EXPORTING iv_vbeln = i_vbeln
                                        IMPORTING ev_kostk = lv_kostk
                                                  ev_lvstk = lv_lvstk
                                                  ev_wbstk = lv_wbstk ).
      IF lv_wbstk = 'C'.
        zcx_sepex=>raise_msg( iv_msgno = '003' iv_msgv1 = i_vbeln ).
      ENDIF.

      ls_cab = zcl_sepex_controle=>ler_cab( iv_lgnum = i_lgnum iv_vbeln = i_vbeln ).
      IF ls_cab IS NOT INITIAL AND ls_cab-status > zif_sepex_const=>gc_status-ot_regul.
        zcx_sepex=>raise_msg( iv_msgno = '005' iv_msgv1 = i_vbeln iv_msgv2 = ls_cab-status ).
      ENDIF.

      " Itens de lote (a determinação de lote já aconteceu antes: ZSD_ICENTRO_ESTOQ
      " no engine, DETERMINAR_LOTES_REMESSA na classe)
      lt_itens = zcl_sepex_wm=>ler_itens_lote( i_vbeln ).
      IF lt_itens IS INITIAL.
        zcx_sepex=>raise_msg( iv_msgno = '004' iv_msgv1 = i_vbeln ).
      ENDIF.

      " ---- OT virtual: cria (se a remessa ainda não está separada) e confirma
      IF lv_kostk = 'C' AND lv_lvstk = 'C'
         AND ls_cab-status >= zif_sepex_const=>gc_status-virtual.
        " Reexecução: WM já concluído e controle gravado; só devolve a OT
        SELECT tanum FROM ltak INTO lv_tanum UP TO 1 ROWS
          WHERE lgnum = i_lgnum AND vbeln = i_vbeln
          ORDER BY tanum DESCENDING.
        ENDSELECT.
      ELSE.
        IF lv_kostk <> 'C'.
          lv_tanum = zcl_sepex_wm=>criar_ot_virtual( iv_lgnum = i_lgnum
                                                     iv_vbeln = i_vbeln
                                                     iv_refnr = i_refnr
                                                     is_par   = ls_par
                                                     it_itens = lt_itens ).
          lo_log->add_msg( iv_msgno = '006' iv_msgv1 = lv_tanum iv_msgv2 = i_vbeln
                           iv_msgv3 = i_origem iv_msgv4 = i_origem_id ).
        ELSE.
          " OT já existe (criada antes) mas a remessa não fechou no WM
          SELECT tanum FROM ltak INTO lv_tanum UP TO 1 ROWS
            WHERE lgnum = i_lgnum AND vbeln = i_vbeln
            ORDER BY tanum DESCENDING.
          ENDSELECT.
        ENDIF.
        IF lv_tanum IS NOT INITIAL.
          zcl_sepex_wm=>confirmar_ot( iv_lgnum = i_lgnum iv_tanum = lv_tanum ).
          lo_log->add_msg( iv_msgno = '007' iv_msgv1 = lv_tanum ).
        ENDIF.
      ENDIF.
      e_tanum = lv_tanum.

      " ---- Controle Express
      IF ls_cab IS INITIAL.
        ls_cab-lgnum     = i_lgnum.
        ls_cab-vbeln     = i_vbeln.
        ls_cab-origem    = i_origem.
        ls_cab-origem_id = i_origem_id.
        ls_cab-tknum     = i_tknum.
        ls_cab-refnr     = i_refnr.
        ls_cab-werks     = lv_werks.
      ENDIF.
      IF ls_cab-status < zif_sepex_const=>gc_status-virtual.
        ls_cab-status  = zif_sepex_const=>gc_status-virtual.
        ls_cab-dt_virt = sy-datum.
        ls_cab-hr_virt = sy-uzeit.
      ENDIF.

      IF lv_tanum IS NOT INITIAL.
        lt_ltap = zcl_sepex_wm=>ler_ltap( iv_lgnum = i_lgnum iv_tanum = lv_tanum ).
      ENDIF.
      CLEAR lt_itm.
      LOOP AT lt_itens INTO ls_item.
        CLEAR ls_itm.
        ls_itm-lgnum  = i_lgnum.
        ls_itm-vbeln  = i_vbeln.
        ls_itm-posnr  = ls_item-posnr.
        ls_itm-matnr  = ls_item-matnr.
        ls_itm-werks  = ls_item-werks.
        ls_itm-lgort  = ls_item-lgort.
        ls_itm-charg  = ls_item-charg.
        ls_itm-menge  = ls_item-lfimg.
        ls_itm-meins  = ls_item-meins.
        ls_itm-status = zif_sepex_const=>gc_status-virtual.
        READ TABLE lt_ltap INTO ls_ltap WITH KEY posnr = ls_item-posnr.
        IF sy-subrc = 0.
          ls_itm-tanum_virt = ls_ltap-tanum.
          ls_itm-tapos_virt = ls_ltap-tapos.
        ENDIF.
        APPEND ls_itm TO lt_itm.
      ENDLOOP.

      zcl_sepex_controle=>gravar_cab( CHANGING cs_cab = ls_cab ).
      zcl_sepex_controle=>gravar_itens( lt_itm ).
      COMMIT WORK AND WAIT.
      lo_log->add_msg( iv_msgno = '010' iv_msgv1 = i_vbeln iv_msgv2 = ls_cab-status ).

      " ---- OT de regularização (reserva das UDs) na mesma execução
      IF ls_par-ot_imediata = 'X' OR i_criar_ot_regul = 'X'.
        CLEAR lt_ret.
        CALL FUNCTION 'ZSEPEX_CRIA_OT_REGUL'
          EXPORTING
            i_lgnum  = i_lgnum
            i_vbeln  = i_vbeln
          IMPORTING
            e_tanum  = e_tanum_regul
          TABLES
            t_return = lt_ret
          EXCEPTIONS
            e_erro   = 1
            OTHERS   = 2.
        LOOP AT lt_ret INTO ls_ret.
          " Falha na regularização não desfaz a separação virtual: fica
          " pendente para a ZSEPEX02; registra como aviso
          IF sy-subrc <> 0 AND ls_ret-type CA 'EAX'.
            ls_ret-type = 'W'.
          ENDIF.
          lo_log->add_bapiret( ls_ret ).
        ENDLOOP.
      ENDIF.

      zcl_sepex_controle=>desbloquear( iv_lgnum = i_lgnum iv_vbeln = i_vbeln ).
      lo_log->salvar( ).
      t_return[] = lo_log->get_return( ).

    CATCH zcx_sepex INTO lx_erro.
      ROLLBACK WORK.
      IF lv_bloq = 'X'.
        zcl_sepex_controle=>desbloquear( iv_lgnum = i_lgnum iv_vbeln = i_vbeln ).
      ENDIF.
      lo_log->add_excecao( lx_erro ).
      lo_log->salvar( ).
      t_return[] = lo_log->get_return( ).
      RAISE e_erro.
  ENDTRY.

ENDFUNCTION.

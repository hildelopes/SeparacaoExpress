FUNCTION zsepex_cria_ot_regul.
*"----------------------------------------------------------------------
*"*"Interface local:
*"  IMPORTING
*"     REFERENCE(I_LGNUM) TYPE  LGNUM
*"     REFERENCE(I_VBELN) TYPE  VBELN_VL
*"     REFERENCE(I_TESTE) TYPE  XFELD DEFAULT ' '
*"  EXPORTING
*"     REFERENCE(E_TANUM) TYPE  TANUM
*"     REFERENCE(E_TANUM_AVS) TYPE  TANUM
*"     REFERENCE(E_ITENS_OK) TYPE  INT4
*"     REFERENCE(E_ITENS_PEND) TYPE  INT4
*"  TABLES
*"      T_RETURN STRUCTURE  BAPIRET2 OPTIONAL
*"      T_UD STRUCTURE  ZSEPEX_S_UD OPTIONAL
*"  EXCEPTIONS
*"      E_ERRO
*"----------------------------------------------------------------------
* Para cada item da remessa com saldo pendente (MENGE - QTD_REGUL - em
* OT aberta), seleciona UDs do MESMO lote (regra 1: o lote escolhido na
* separação virtual é obrigatório) e cria as OTs de regularização da
* remessa, com um item por UD/quant, destino = posição virtual: uma OT
* com os paletes inteiros (E_TANUM) e outra com as frações de palete /
* avulso (E_TANUM_AVS), como o Monitor de Carga separa palete x avulso.
* As OTs ficam abertas (reservam as UDs) até a confirmação no RF.
* Portão/zona: cada OT recebe no cabeçalho (LTAK-LGTOR/LGBZO) o portão/
* zona do cabeçalho Express (padrão: o da remessa de transferência) e vai
* para a fila RF do portão: paletes FILA_PAL_PREF_D_portão (ex. PC_D_001),
* avulso FILA_AVS_PREF_D_portão (ex. AV_D_001).
* Regra do armazém (ZCL_SEPEX_UD): paletes inteiros das posições, fração
* de palete do avulso (LGTYP_AVS). Se o avulso não cobre e REAB_AUTO = X,
* cria o reabastecimento NT/OT 919 (ZFWM_REABASTECIMENTO) e deixa o item
* pendente; a OT de regularização sai na próxima execução (ZSEPEX02 ou
* job ZSEPEX04), depois da confirmação do reabastecimento.
*----------------------------------------------------------------------
  DATA: lo_log     TYPE REF TO zcl_sepex_log,
        lx_erro    TYPE REF TO zcx_sepex,
        ls_par     TYPE zsepex_t_par,
        lt_lgtyp   TYPE zsepex_t_par_lt_tt,
        ls_cab     TYPE zsepex_t_cab,
        lt_itm     TYPE zsepex_t_itm_tt,
        ls_itm     TYPE zsepex_t_itm,
        lt_ot      TYPE zsepex_t_ot_tt,
        ls_ot      TYPE zsepex_t_ot,
        lt_ud      TYPE zsepex_t_ud_tt,
        lt_ud_all  TYPE zsepex_t_ud_tt,
        ls_ud      TYPE zsepex_s_ud,
        lt_lenum   TYPE zcl_sepex_ud=>ty_t_lenum,
        lt_ltap    TYPE zcl_sepex_wm=>ty_t_ltap,
        ls_ltap    TYPE ltap,
        lv_pend    TYPE zsepex_qtd,
        lv_falta   TYPE zsepex_qtd,
        lv_falta_avs TYPE zsepex_qtd,
        lv_falta_pal TYPE zsepex_qtd,
        lv_lhmg1   TYPE zsepex_qtd,
        lv_tbnum   TYPE tbnum,
        lv_tanum_r TYPE tanum,
        lv_msg     TYPE bapi_msg,
        lx_reab    TYPE REF TO zcx_sepex,
        lv_tanum   TYPE tanum,
        lv_bloq    TYPE xfeld,
        lv_idx     TYPE i,
        lv_lgtor   TYPE lgtor,
        lv_lgbzo   TYPE lgbzo,
        lv_queue   TYPE lrf_queue,
        lx_portao  TYPE REF TO zcx_sepex,
        ls_ret     TYPE bapiret2,
        lt_ud_pal  TYPE zsepex_t_ud_tt,
        lt_ud_avs  TYPE zsepex_t_ud_tt.

  TYPES: BEGIN OF lty_criada,
           tanum   TYPE tanum,
           inteira TYPE xfeld,
           pref    TYPE zsepex_fila_reg_pref,
           tipo    TYPE c LENGTH 10,
           qtd     TYPE i,
         END OF lty_criada.
  DATA: lt_criadas TYPE STANDARD TABLE OF lty_criada,
        ls_criada  TYPE lty_criada.

  CLEAR: e_tanum, e_tanum_avs, e_itens_ok, e_itens_pend, t_return[], t_ud[].
  DATA lv_ext TYPE balnrext.
  lv_ext = i_vbeln.
  CREATE OBJECT lo_log EXPORTING iv_extnumber = lv_ext.

  TRY.
      ls_par   = zcl_sepex_controle=>ler_param( i_lgnum ).
      lt_lgtyp = zcl_sepex_controle=>ler_lgtyp_origem( i_lgnum ).

      ls_cab = zcl_sepex_controle=>ler_cab( iv_lgnum = i_lgnum iv_vbeln = i_vbeln ).
      IF ls_cab IS INITIAL.
        zcx_sepex=>raise_msg( iv_msgno = '002' iv_msgv1 = i_vbeln ).
      ENDIF.
      IF ls_cab-status = zif_sepex_const=>gc_status-concluido
         OR ls_cab-status = zif_sepex_const=>gc_status-cancelado.
        zcx_sepex=>raise_msg( iv_msgno = '014' iv_msgv1 = i_vbeln ).
      ENDIF.

      IF i_teste = space.
        zcl_sepex_controle=>bloquear( iv_lgnum = i_lgnum iv_vbeln = i_vbeln ).
        lv_bloq = 'X'.
      ENDIF.

      lt_itm = zcl_sepex_controle=>ler_itens( iv_lgnum = i_lgnum iv_vbeln = i_vbeln ).
      lt_ot  = zcl_sepex_controle=>ler_ots( iv_lgnum = i_lgnum iv_vbeln = i_vbeln ).

      LOOP AT lt_itm INTO ls_itm WHERE status < zif_sepex_const=>gc_status-concluido.
        lv_pend = zcl_sepex_controle=>qtd_pendente_item( is_itm = ls_itm it_ot = lt_ot ).
        IF lv_pend <= 0.
          CONTINUE.
        ENDIF.
        CLEAR: lt_ud, lv_falta, lv_falta_avs, lv_lhmg1.
        zcl_sepex_ud=>selecionar( EXPORTING iv_lgnum = i_lgnum
                                            iv_matnr = ls_itm-matnr
                                            iv_werks = ls_itm-werks
                                            iv_charg = ls_itm-charg
                                            iv_menge = lv_pend
                                            iv_meins = ls_itm-meins
                                            it_lgtyp = lt_lgtyp
                                            it_excluir_lenum = lt_lenum
                                            iv_lgtyp_avs  = ls_par-lgtyp_avs
                                            iv_ud_parcial = ls_par-ud_parcial
                                  IMPORTING et_ud    = lt_ud
                                            ev_falta = lv_falta
                                            ev_falta_avulso = lv_falta_avs
                                            ev_lhmg1 = lv_lhmg1 ).
        LOOP AT lt_ud INTO ls_ud.
          " Vincula a UD ao item da remessa (campo LGORT guarda o do item)
          ls_ud-lgort = ls_itm-lgort.
          APPEND ls_ud TO lt_ud_all.
          APPEND ls_ud TO t_ud.
          " Guarda a UD inteira já usada para não repetir em outro item
          IF ls_ud-inteira = 'X'.
            APPEND ls_ud-lenum TO lt_lenum.
          ENDIF.
          " Pré-monta a linha de controle (TANUM/TAPOS após a criação)
          CLEAR ls_ot.
          ls_ot-lgnum = i_lgnum.
          ls_ot-vbeln = i_vbeln.
          ls_ot-posnr = ls_itm-posnr.
          ls_ot-matnr = ls_itm-matnr.
          ls_ot-charg = ls_itm-charg.
          ls_ot-vlenr   = ls_ud-lenum.
          ls_ot-inteira = ls_ud-inteira.
          ls_ot-vsolm   = ls_ud-menge.
          ls_ot-meins   = ls_ud-meins.
          APPEND ls_ot TO lt_ot.   " marcado por TANUM vazio
        ENDLOOP.
        IF lv_falta > 0.
          e_itens_pend = e_itens_pend + 1.
          " Paletes inteiros que faltam nas posições
          IF lv_lhmg1 > 0 AND lv_falta >= lv_lhmg1.
            lv_falta_pal = lv_falta - lv_falta_avs.
            lo_log->add_msg( iv_msgty = 'W' iv_msgno = '035' iv_msgv1 = ls_itm-matnr
                             iv_msgv2 = ls_itm-charg iv_msgv3 = lv_falta_pal
                             iv_msgv4 = ls_itm-meins ).
          ELSEIF lv_falta_avs = 0.
            lo_log->add_msg( iv_msgty = 'W' iv_msgno = '027' iv_msgv1 = ls_itm-matnr
                             iv_msgv2 = ls_itm-charg iv_msgv3 = lv_falta iv_msgv4 = ls_itm-meins ).
          ENDIF.
          " Fração de palete sem saldo no avulso: reabastecimento (NT 919)
          IF lv_falta_avs > 0 AND ls_par-lgtyp_avs IS NOT INITIAL.
            zcl_sepex_wm=>reabastecimento_pendente(
              EXPORTING iv_lgnum = i_lgnum iv_matnr = ls_itm-matnr
                        iv_charg = ls_itm-charg iv_lgtyp_avs = ls_par-lgtyp_avs
              IMPORTING ev_tbnum = lv_tbnum ev_tanum = lv_tanum_r ).
            IF lv_tbnum IS NOT INITIAL OR lv_tanum_r IS NOT INITIAL.
              lo_log->add_msg( iv_msgty = 'W' iv_msgno = '033' iv_msgv1 = ls_itm-matnr
                               iv_msgv2 = ls_itm-charg iv_msgv3 = lv_tbnum iv_msgv4 = lv_tanum_r ).
            ELSEIF ls_par-reab_auto = 'X' AND i_teste = space.
              TRY.
                  lv_msg = zcl_sepex_wm=>reabastecer_avulso( iv_lgnum = i_lgnum
                                                             iv_matnr = ls_itm-matnr
                                                             iv_charg = ls_itm-charg
                                                             iv_werks = ls_itm-werks
                                                             iv_lgort = ls_itm-lgort ).
                  lo_log->add_msg( iv_msgty = 'I' iv_msgno = '032' iv_msgv1 = ls_itm-matnr
                                   iv_msgv2 = ls_itm-charg iv_msgv3 = lv_msg ).
                CATCH zcx_sepex INTO lx_reab.
                  lo_log->add_excecao( lx_reab ).
              ENDTRY.
            ELSE.
              lo_log->add_msg( iv_msgty = 'W' iv_msgno = '031' iv_msgv1 = ls_itm-matnr
                               iv_msgv2 = ls_itm-charg iv_msgv3 = lv_falta_avs
                               iv_msgv4 = ls_itm-meins ).
            ENDIF.
          ENDIF.
        ELSE.
          e_itens_ok = e_itens_ok + 1.
        ENDIF.
      ENDLOOP.

      IF lt_ud_all IS INITIAL.
        IF e_itens_pend = 0.
          lo_log->add_msg( iv_msgty = 'I' iv_msgno = '014' iv_msgv1 = i_vbeln ).
        ENDIF.
        IF lv_bloq = 'X'.
          zcl_sepex_controle=>desbloquear( iv_lgnum = i_lgnum iv_vbeln = i_vbeln ).
        ENDIF.
        lo_log->salvar( ).
        t_return[] = lo_log->get_return( ).
        RETURN.
      ENDIF.

      IF i_teste = 'X'.
        lo_log->salvar( ).
        t_return[] = lo_log->get_return( ).
        RETURN.
      ENDIF.

      " Portão/zona: cabeçalho Express; registros antigos caem na remessa
      lv_lgtor = ls_cab-lgtor.
      lv_lgbzo = ls_cab-lgbzo.
      IF lv_lgtor IS INITIAL.
        zcl_sepex_wm=>ler_portao_remessa( EXPORTING iv_vbeln = i_vbeln
                                          IMPORTING ev_lgtor = lv_lgtor
                                                    ev_lgbzo = lv_lgbzo ).
        IF lv_lgtor IS NOT INITIAL.
          zcl_sepex_controle=>gravar_portao_zona( iv_lgnum = i_lgnum iv_vbeln = i_vbeln
                                                  iv_lgtor = lv_lgtor iv_lgbzo = lv_lgbzo ).
        ENDIF.
      ENDIF.

      " Duas OTs por remessa, como o Monitor de Carga separa palete x
      " avulso: paletes inteiros (fila PC_D_portão) e frações de palete /
      " avulso (fila AV_D_portão)
      LOOP AT lt_ud_all INTO ls_ud.
        IF ls_ud-inteira = 'X'.
          APPEND ls_ud TO lt_ud_pal.
        ELSE.
          APPEND ls_ud TO lt_ud_avs.
        ENDIF.
      ENDLOOP.

      IF lt_ud_pal IS NOT INITIAL.
        CLEAR ls_criada.
        ls_criada-tanum   = zcl_sepex_wm=>criar_ot_regularizacao( iv_lgnum = i_lgnum
                                                                   is_par   = ls_par
                                                                   it_ud    = lt_ud_pal ).
        ls_criada-inteira = 'X'.
        ls_criada-pref    = ls_par-fila_pal_pref.
        ls_criada-tipo    = 'paletes'.
        ls_criada-qtd     = lines( lt_ud_pal ).
        APPEND ls_criada TO lt_criadas.
        e_tanum = ls_criada-tanum.
      ENDIF.
      IF lt_ud_avs IS NOT INITIAL.
        CLEAR ls_criada.
        IF lt_criadas IS INITIAL.
          ls_criada-tanum = zcl_sepex_wm=>criar_ot_regularizacao( iv_lgnum = i_lgnum
                                                                   is_par   = ls_par
                                                                   it_ud    = lt_ud_avs ).
        ELSE.
          " A OT dos paletes já existe (commit da L_TO_CREATE_MULTIPLE):
          " falha aqui não pode desfazer o controle dela - vira aviso e o
          " avulso fica pendente para a próxima execução
          TRY.
              ls_criada-tanum = zcl_sepex_wm=>criar_ot_regularizacao( iv_lgnum = i_lgnum
                                                                       is_par   = ls_par
                                                                       it_ud    = lt_ud_avs ).
            CATCH zcx_sepex INTO lx_portao.
              ls_ret = lx_portao->get_bapiret( ).
              ls_ret-type = 'W'.
              lo_log->add_bapiret( ls_ret ).
              CLEAR ls_criada-tanum.
          ENDTRY.
        ENDIF.
        IF ls_criada-tanum IS NOT INITIAL.
          ls_criada-pref = ls_par-fila_avs_pref.
          ls_criada-tipo = 'avulso'.
          ls_criada-qtd  = lines( lt_ud_avs ).
          APPEND ls_criada TO lt_criadas.
          e_tanum_avs = ls_criada-tanum.
          IF e_tanum IS INITIAL.
            e_tanum = ls_criada-tanum.
          ENDIF.
        ENDIF.
      ENDIF.

      LOOP AT lt_criadas INTO ls_criada.
        lv_tanum = ls_criada-tanum.

        " Portão/zona no cabeçalho da OT e fila RF do portão por tipo
        IF lv_lgtor IS NOT INITIAL.
          TRY.
              lv_queue = zcl_sepex_wm=>aplicar_portao_ot( iv_lgnum     = i_lgnum
                                                          iv_tanum     = lv_tanum
                                                          iv_lgtor     = lv_lgtor
                                                          iv_lgbzo     = lv_lgbzo
                                                          iv_fila_pref = ls_criada-pref
                                                          iv_commit    = space ).
              lo_log->add_msg( iv_msgty = 'I' iv_msgno = '040' iv_msgv1 = lv_tanum
                               iv_msgv2 = lv_lgtor iv_msgv3 = lv_lgbzo iv_msgv4 = lv_queue ).
            CATCH zcx_sepex INTO lx_portao.
              " Falha no portão/fila não desfaz a OT (já gravada pela
              " L_TO_CREATE_MULTIPLE): fica como aviso no log
              ls_ret = lx_portao->get_bapiret( ).
              ls_ret-type = 'W'.
              lo_log->add_bapiret( ls_ret ).
          ENDTRY.
        ENDIF.

        " Itens da OT criada -> ZSEPEX_T_OT (casa por UD + material + lote,
        " dentro do mesmo tipo: palete inteiro ou avulso)
        lt_ltap = zcl_sepex_wm=>ler_ltap( iv_lgnum = i_lgnum iv_tanum = lv_tanum ).
        LOOP AT lt_ot INTO ls_ot WHERE tanum IS INITIAL
                                   AND inteira = ls_criada-inteira.
          lv_idx = sy-tabix.
          READ TABLE lt_ltap INTO ls_ltap WITH KEY vlenr = ls_ot-vlenr
                                                   matnr = ls_ot-matnr
                                                   charg = ls_ot-charg.
          IF sy-subrc <> 0.
            READ TABLE lt_ltap INTO ls_ltap WITH KEY matnr = ls_ot-matnr
                                                     charg = ls_ot-charg.
          ENDIF.
          IF sy-subrc = 0.
            ls_ot-tanum = ls_ltap-tanum.
            ls_ot-tapos = ls_ltap-tapos.
            ls_ot-vsolm = ls_ltap-vsolm.
            ls_ot-meins = ls_ltap-meins.
            DELETE lt_ltap INDEX sy-tabix.
            MODIFY lt_ot FROM ls_ot INDEX lv_idx.
          ENDIF.
        ENDLOOP.
      ENDLOOP.
      DELETE lt_ot WHERE tanum IS INITIAL.
      zcl_sepex_controle=>gravar_ots( lt_ot ).

      IF ls_cab-status < zif_sepex_const=>gc_status-ot_regul.
        zcl_sepex_controle=>set_status( iv_lgnum = i_lgnum iv_vbeln = i_vbeln
                                        iv_status = zif_sepex_const=>gc_status-ot_regul ).
      ENDIF.
      COMMIT WORK AND WAIT.

      LOOP AT lt_criadas INTO ls_criada.
        lo_log->add_msg( iv_msgno = '046' iv_msgv1 = ls_criada-tanum iv_msgv2 = ls_criada-tipo
                         iv_msgv3 = i_vbeln iv_msgv4 = ls_criada-qtd ).
      ENDLOOP.

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

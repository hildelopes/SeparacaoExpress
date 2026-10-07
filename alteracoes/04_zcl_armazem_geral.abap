*----------------------------------------------------------------------*
* Classe ZCL_ARMAZEM_GERAL - repositório ArmazemGeral
* src/zcl_armazem_geral.clas.abap
*----------------------------------------------------------------------*

*======================================================================*
* A) Definição - seção pública: atributo e métodos
*======================================================================*
    "! Separação Express: a OT de picking da saída é confirmada contra a
    "! posição virtual (ZSEPEX) e a separação física fica para depois
    METHODS set_express
      IMPORTING
        !iv_express TYPE xfeld DEFAULT 'X'.                        " SEPEX

*   CRIAR_POR_TRANSPORTE: novo parâmetro opcional
        !iv_express TYPE xfeld DEFAULT space                       " SEPEX

*   Seção privada:
    DATA mv_express TYPE xfeld.                                    " SEPEX

*======================================================================*
* B) Implementação
*======================================================================*
  METHOD set_express.                                              " SEPEX
    mv_express = iv_express.
    ms_log-zzexpress = iv_express.
  ENDMETHOD.

* CRIAR_POR_TRANSPORTE: após criar o processo (ro_processo), antes de
* executar o fluxo:
    IF iv_express = 'X'.                                           " SEPEX
      ro_processo->set_express( ).
    ENDIF.

* REPROCESSAR: ao carregar o processo (ms_log lido do ZAGT_LOG):
    ro_processo->mv_express = ro_processo->ms_log-zzexpress.      " SEPEX

*======================================================================*
* C) EXECUTAR_PICKING_SAIDA - ramo "ms_config-wm_saida = 'X'", dentro de
*    IF ms_log-tanum IS INITIAL ... ELSE (OT ainda não existe), depois de
*    aplicar_portao_zona( ) e determinar_lotes_remessa( lv_kostk ):
*======================================================================*
          IF mv_express = 'X'.                                     " SEPEX >>>
            " Separação virtual: OT com origem na posição virtual,
            " confirmada; OTs de regularização criadas (reserva das UDs).
            " O processo vai direto a 05 (picking OK); a separação física
            " é acompanhada no ZSEPEX02/03 e confirmada no RF Express.
            DATA: lt_sepex_ret TYPE bapiret2_t,
                  ls_sepex_ret TYPE bapiret2,
                  lv_sepex_tan TYPE tanum.
            CALL FUNCTION 'ZSEPEX_SEPARA_VIRTUAL'
              EXPORTING
                i_lgnum     = ms_config-lgnum_orig
                i_vbeln     = ms_log-vbeln_vl
                i_origem    = zif_sepex_const=>gc_origem-armazem_geral
                i_origem_id = ms_log-guid
                i_tknum     = ms_log-tknum
              IMPORTING
                e_tanum     = lv_sepex_tan
              TABLES
                t_return    = lt_sepex_ret
              EXCEPTIONS
                e_erro      = 1
                OTHERS      = 2.
            IF sy-subrc <> 0.
              zcx_armazem_geral=>raise_from_bapiret( it_return = lt_sepex_ret ).
            ENDIF.
            LOOP AT lt_sepex_ret INTO ls_sepex_ret.
              registrar_bapiret( ls_sepex_ret ).
            ENDLOOP.
            ms_log-tanum = lv_sepex_tan.
            commit_bapi( ).
            registrar_msg( iv_msgno = '008'
                           iv_msgv1 = ms_log-tanum
                           iv_msgv2 = ms_config-lgnum_orig ).
          ELSEIF ms_config-ot_auto = 'X' OR mv_criar_ot = 'X'.    " SEPEX <<< (era IF)
            ms_log-tanum = criar_ot_wm( ... ).                     " inalterado
            ...

*   Depois do bloco, o ler_ot_remessa( ) encontra a OT confirmada e o
*   processo vai para gc_status-picking_ok (msg 010) sem alteração.

*======================================================================*
* D) DETERMINAR_LOTES_REMESSA - descontar o saldo Express pendente
*    (lotes já comprometidos por remessas Express com PGI, cuja
*    regularização física ainda não aconteceu). Inserir onde a rotina
*    desconta as quantidades de lt_vbeln_ok (remessas abertas) do
*    disponível por lote (<...>-disp), para o mesmo material/centro:
*======================================================================*
    " SEPEX >>>
    DATA: lt_sepex TYPE STANDARD TABLE OF zsepex_s_saldo,
          ls_sepex TYPE zsepex_s_saldo.
    CALL FUNCTION 'ZSEPEX_SALDO_PENDENTE'
      EXPORTING
        i_lgnum     = ms_config-lgnum_orig
        i_werks     = ms_config-werks_orig
        i_so_sem_ot = space        " tudo o que ainda não foi fisicamente separado
      TABLES
        t_saldo     = lt_sepex.
    LOOP AT lt_sepex INTO ls_sepex WHERE matnr = ls_lips-matnr.
      READ TABLE lt_lote ASSIGNING FIELD-SYMBOL(<ls_lote_sx>) WITH KEY charg = ls_sepex-charg.
      IF sy-subrc = 0.
        <ls_lote_sx>-disp = <ls_lote_sx>-disp
                          - converter_para_venda( ... ls_sepex-menge na unidade base ... ).
      ENDIF.
    ENDLOOP.
    " SEPEX <<<

*======================================================================*
* E) ZWMR0010 - ZF_SEPARACAO_RETORNO (carga do depositante): repassar o
*    Express para CRIAR_POR_TRANSPORTE( iv_tknum = ... iv_express = p_express ).
*    ZAGR0002 (cockpit): coluna "Express" a partir de ZAGT_LOG-ZZEXPRESS.
*======================================================================*

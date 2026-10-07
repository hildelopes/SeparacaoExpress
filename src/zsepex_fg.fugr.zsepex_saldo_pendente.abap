FUNCTION zsepex_saldo_pendente.
*"----------------------------------------------------------------------
*"*"Interface local:
*"  IMPORTING
*"     REFERENCE(I_LGNUM) TYPE  LGNUM
*"     REFERENCE(I_WERKS) TYPE  WERKS_D OPTIONAL
*"     REFERENCE(I_SO_SEM_OT) TYPE  XFELD DEFAULT 'X'
*"  TABLES
*"      T_SALDO STRUCTURE  ZSEPEX_S_SALDO
*"----------------------------------------------------------------------
* Saldo Express ainda não reservado fisicamente, por material/centro/
* lote. Usado pelo Monitor de Carga (ZF_VALIDA_SALDO_TRANSF /
* ZF_PREENCHE_SIMULACAO) e pela classe do Armazém Geral
* (DETERMINAR_LOTES_REMESSA) para descontar da disponibilidade.
*----------------------------------------------------------------------
  DATA lt_saldo TYPE zsepex_t_saldo_tt.

  CLEAR t_saldo[].
  lt_saldo = zcl_sepex_controle=>saldo_pendente( iv_lgnum     = i_lgnum
                                                 iv_werks     = i_werks
                                                 iv_so_sem_ot = i_so_sem_ot ).
  t_saldo[] = lt_saldo.

ENDFUNCTION.

*----------------------------------------------------------------------*
* FM ZTM_REG_TRANSFERENCIA - repositório ZWMR0010
* Funcoes/ZTM_REG_TRANSFERENCIA/ZTM_REG_TRANSFERENCIA.abap
*----------------------------------------------------------------------*
* 1) Interface (SE37): novo parâmetro de importação, opcional
*"     REFERENCE(I_EXPRESS) TYPE  ZSEPEX_EXPRESS OPTIONAL

* 2) Preenchimento do cabeçalho, após "wa_icentros-automatica = i_auto."
  wa_icentros-automatica   = i_auto.
  wa_icentros-zzexpress    = i_express.          " SEPEX

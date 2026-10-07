"! Separação Express - constantes
INTERFACE zif_sepex_const
  PUBLIC.

  CONSTANTS: BEGIN OF gc_status,
               registrado   TYPE zsepex_status VALUE '0',
               virtual      TYPE zsepex_status VALUE '1',
               ot_regul     TYPE zsepex_status VALUE '2',
               pgi          TYPE zsepex_status VALUE '3',
               em_regul     TYPE zsepex_status VALUE '4',
               concluido    TYPE zsepex_status VALUE '5',
               cancelado    TYPE zsepex_status VALUE '9',
             END OF gc_status.

  CONSTANTS: BEGIN OF gc_origem,
               icentros      TYPE zsepex_origem VALUE 'I',
               armazem_geral TYPE zsepex_origem VALUE 'A',
             END OF gc_origem.

  CONSTANTS: BEGIN OF gc_tipo_vol,
               ud       TYPE zsepex_tipo_vol VALUE 'U',
               etiqueta TYPE zsepex_tipo_vol VALUE 'E',
             END OF gc_tipo_vol.

  "! Atividades do objeto de autorização ZSEPEX_AUT
  CONSTANTS: BEGIN OF gc_actvt,
               liberar     TYPE activ_auth VALUE '01',
               exibir      TYPE activ_auth VALUE '03',
               regularizar TYPE activ_auth VALUE '16',
               desfazer    TYPE activ_auth VALUE '85',
             END OF gc_actvt.

  CONSTANTS: BEGIN OF gc_bal,
               object    TYPE balobj_d  VALUE 'ZSEPEX',
               subobject TYPE balsubobj VALUE 'EXPRESS',
             END OF gc_bal.

  CONSTANTS gc_msgid TYPE symsgid VALUE 'ZSEPEX'.

  "! Subitens de divisão de lote da remessa (LIPS-POSNR >= 900000)
  CONSTANTS gc_posnr_lote TYPE posnr_vl VALUE '900000'.

  "! Indicador de confirmação usado na L_TO_CONFIRM (mesmo valor do
  "! Z_WM_CONFIRMA_ICENTRO em produção)
  CONSTANTS gc_quknz TYPE ltap-quknz VALUE '4'.

ENDINTERFACE.

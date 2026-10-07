# Alterações em objetos existentes (fora do pacote ZSEPEX)

Trechos a aplicar nos programas compartilhados. Cada ponto está marcado com o
comentário `" SEPEX` para localização. Nenhum deles muda o comportamento quando a
carga **não** é Express.

| Arquivo | Objeto | Repositório de origem |
|---|---|---|
| `01_ztm_reg_transferencia.abap` | FM `ZTM_REG_TRANSFERENCIA` | ZWMR0010 |
| `02_zwm_icentros.abap` | Engine `ZWM_ICENTROS` (`LZWM_ICENTROSTOP`) | ZWMR0010 |
| `03_zwmr0010_monitor.abap` | Monitor de Carga `ZWMR0010` | ZWMR0010 |
| `04_zcl_armazem_geral.abap` | Classe `ZCL_ARMAZEM_GERAL` | ArmazemGeral |

Pré-requisito: pacote ZSEPEX ativado (appends `ZSEPEX_A_ICENTROS` em `ZWM_ICENTROS` e
`ZSEPEX_A_ZAGT_LOG` em `ZAGT_LOG` criam o campo `ZZEXPRESS` nas duas tabelas).

# Alterações em objetos existentes (fora do pacote ZSEPEX)

**Aplicadas diretamente nos repositórios de origem (09/10/2026):**

| Repositório | Commit | Como levar ao SAP |
|---|---|---|
| `hildelopes/ZWMR0010` | `e5c9301` | Fontes planos: comparar com a SE38/SE37 (Utilitários → Comparar) e colar os trechos marcados `SEPEX`, ou colar o include inteiro |
| `hildelopes/ArmazemGeral` | `6ddf84c` | abapGit: Pull do repositório ZARMAZEM_GERAL (só `ZCL_ARMAZEM_GERAL` muda) |

Ordem: 1) pacote ZSEPEX ativo; 2) `ZTM_REG_TRANSFERENCIA`; 3) `ZWM_ICENTROS`;
4) `ZWMR0010`; 5) `ZCL_ARMAZEM_GERAL`. Os arquivos abaixo continuam como referência
dos trechos.

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

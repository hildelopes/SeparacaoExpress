# Separação Express (pacote ZSEPEX)

Separação virtual no WM do DPFE (depósito DFC) para faturar as cargas no último dia do
mês sem esperar o picking físico, com regularização física nos dias seguintes por OT
confirmada no RF e conferência de expedição no carregamento. Vale para a transferência
intercentros (engine `ZWM_ICENTROS`, Monitor de Carga `ZWMR0010`) e para a carga do
depositante do Armazém Geral (classe `ZCL_ARMAZEM_GERAL`).

Documentação do desenho em `docs/` (ler na ordem: `04_especificacao_v0.4.md`,
`03_decisoes_e_pendencias.md`, `02_analise_zwmr0010_fluxo_atual.md`,
`05_analise_armazem_geral_express.md`). Apresentação para a Logística em
`docs/apresentacao/separacao_express_fluxo.html`.

## 1. Conteúdo do repositório

```
.abapgit.xml           abapGit: pasta /src/, idioma PT
abaplint.json          verificação de sintaxe (v740sp08) - 0 issues
src/                   pacote ZSEPEX (abapGit)
alteracoes/            trechos a aplicar em ZWMR0010, ZWM_ICENTROS,
                       ZTM_REG_TRANSFERENCIA e ZCL_ARMAZEM_GERAL (marcados "SEPEX")
docs/                  especificação, análises, decisões e apresentação
```

### Dicionário (`src/`)

| Objeto | Tipo | Descrição |
|---|---|---|
| `ZSEPEX_T_PAR` | Tabela (C) | Parâmetros por depósito: tipo/área/posição virtual, tipo de movimento da regularização, OT imediata, dias de alerta, e-mails, ativo |
| `ZSEPEX_T_PAR_LT` | Tabela (C) | Tipos de depósito de origem da regularização, com prioridade (ex.: DIA, DTA, XDC, DII) |
| `ZSEPEX_T_CAB` | Tabela (A) | Processo Express por remessa de saída: origem (I/A), id de origem, carga, grupo, status, datas |
| `ZSEPEX_T_ITM` | Tabela (A) | Itens de lote da remessa: quantidade, OT virtual, quantidade regularizada, status |
| `ZSEPEX_T_OT` | Tabela (A) | Itens das OTs de regularização: UD, quantidades teórica/real/diferença, confirmação |
| `ZSEPEX_T_VOL` | Tabela (A) | Volumes separados (UD inteira ou etiqueta) por carga, para a conferência de expedição (fase 1b) |
| `ZSEPEX_S_SALDO`, `ZSEPEX_T_SALDO_TT` | Estrutura / tipo tabela | Saldo pendente por material/centro/lote (interface da `ZSEPEX_SALDO_PENDENTE`) |
| `ZSEPEX_S_UD`, `ZSEPEX_T_UD_TT` | Estrutura / tipo tabela | UD selecionada para regularização |
| `ZSEPEX_A_ICENTROS`, `ZSEPEX_A_ZAGT_LOG` | Appends | Campo `ZZEXPRESS` em `ZWM_ICENTROS` e `ZAGT_LOG` |
| `ZSEPEX_D_*`, `ZSEPEX_*` | Domínios / elementos | Status (0,1,2,3,4,5,9), origem (I/A), tipo de volume (U/E), dias, quantidade |
| `EZSEPEX_CAB` | Bloqueio | Por depósito + remessa |
| `ZSEPEX_EXP` | Autorização (**criar na SU21, não vem pelo abapGit**) | ACTVT (01 liberar, 03 exibir, 16 regularizar, 85 desfazer) + LGNUM |
| `ZSEPEX` | Mensagens | 000 a 030 |

### Código

| Objeto | Descrição |
|---|---|
| `ZIF_SEPEX_CONST` | Constantes (status, origem, tipo de volume, atividades, BAL) |
| `ZCX_SEPEX` | Exceção T100 (`raise_msg`, `raise_sy`, `raise_from_bapiret`, `get_bapiret`) |
| `ZCL_SEPEX_CONTROLE` | Parâmetros, cabeçalho/itens/OTs, bloqueio, saldo pendente, texto de status |
| `ZCL_SEPEX_UD` | Seleção de UDs do lote (regras da simulação da carga fechada) |
| `ZCL_SEPEX_WM` | OT virtual (`L_TO_CREATE_DN` + `L_TO_CONFIRM`), OT de regularização (`L_TO_CREATE_MULTIPLE`), LTAP, saldo da posição virtual |
| `ZCL_SEPEX_SINC` | Sincroniza itens/OTs/remessa e fecha o processo |
| `ZCL_SEPEX_LOG` | Application Log (objeto `ZSEPEX`, subobjeto `EXPRESS`) |
| `ZCL_SEPEX_AUTH` | Verificação de `ZSEPEX_EXP` |
| `ZSEPEX_FG` | FMs `ZSEPEX_SEPARA_VIRTUAL`, `ZSEPEX_CRIA_OT_REGUL`, `ZSEPEX_SALDO_PENDENTE` (interface clássica para o engine e a classe) |
| `ZSEPEX_R_REGULARIZAR` / **ZSEPEX02** | Itens pendentes; criar OTs de regularização; sincronizar; modo teste |
| `ZSEPEX_R_PENDENCIAS` / **ZSEPEX03** | Pendências com alerta de prazo; versão de fechamento (saldo da posição virtual); e-mail |
| `ZSEPEX_R_SINCRONIZAR` / **ZSEPEX04** | Job de sincronização (SM36) |

Fase 1b (ainda não no repositório): RF Express `ZSEPEXRF` e adaptação do `ZWMRF0002`.

## 2. Instalação

1. Criar o pacote `ZSEPEX` (ou aceitar o proposto no pull).
2. abapGit → New Online → este repositório → branch `main` → Pull. Idioma original PT.
3. Ativar na ordem: domínios → elementos → tabelas/estruturas/appends → tipos de tabela →
   bloqueio → interface → exceção → classes → grupo de funções → programas → transações.

### Passos manuais (uma vez)

| Passo | Transação | O quê |
|---|---|---|
| 0 | **SU21** | **Antes do pull.** Criar o objeto `ZSEPEX_EXP` na classe `AAAB`, texto "Separação Express - execução", campos `ACTVT` e `LGNUM`, atividades permitidas 01, 03, 16, 85. Salvar na request, clicar em "Gerar posteriormente SAP_ALL" (ou `RSUSR406`), logoff/logon. O SUSO não está em `src/` porque o import via abapGit gravou o objeto sem campos e o SAP_ALL regenerado trava a correção (ver `docs/referencia_zsepex_exp.suso.xml` só como referência). Leva o objeto para QAS/PRD pela request de transporte. |
| 1 | **SLG0** | Objeto `ZSEPEX`, subobjeto `EXPRESS` |
| 2 | **SE54** | Gerar manutenção SM30 para `ZSEPEX_T_PAR` e `ZSEPEX_T_PAR_LT` (grupo de funções `ZSEPEX_TMG`) |
| 3 | **SM30** | `ZSEPEX_T_PAR`: `LGNUM = DFC`, `LGTYP_VIRT = 9EX`, `LGBER_VIRT = 001`, `LGPLA_VIRT = EXPRESS`, `BWLVS_REG` = tipo de movimento WM da regularização, `OT_IMEDIATA = X`, `DIAS_ALERTA = 7`, e-mails separados por `;`, `ATIVO = X`. `ZSEPEX_T_PAR_LT`: `DIA`, `DTA`, `XDC`, `DII` com prioridade |
| 4 | **PFCG** | Perfis com `ZSEPEX_EXP` (01 encarregado, 16 regularização, 03 consulta) e transações ZSEPEX02/03/04 |
| 5 | **SM36** | `ZSEPEX_R_SINCRONIZAR` a cada 30 min; `ZSEPEX_R_PENDENCIAS` diário com `P_EMAIL = X` |

### Customizing WM (consultor) e prova em QAS

| # | Item |
|---|---|
| C1 | Tipo de depósito `9EX` no DFC: cópia do 999, estoque negativo permitido, sem UD, estoque misto, fora das estratégias; posição `EXPRESS` (LS01N) |
| C2 | Tipo de movimento WM para a regularização (cópia do 999), destino `9EX`, confirmação exigida |
| C3 | Prova: `L_TO_CREATE_DN` com `IT_DELIT` origem `9EX/EXPRESS` em posição vazia cria quant negativo. Fallback: posição `EXPRESS` no 999 |
| C4 | Prova: `L_TO_CREATE_MULTIPLE` com `T_LTAP_CREAT-VLENR` (UD de origem) e destino `9EX/EXPRESS`, confirmável na LM45 / RF |

### Alterações nos objetos compartilhados

Ver `alteracoes/README.md`. Aplicar depois do pull e da ativação do pacote.

## 3. Regras de negócio implementadas

- O lote fixado na separação virtual é **obrigatório** na regularização (regra 1): as OTs
  de regularização nomeiam UDs do mesmo lote; sem UD do lote, o saldo fica pendente
  (mensagem 027) até o encarregado resolver pela ZSEPEX02.
- OT de regularização aberta reserva as UDs; o saldo Express sem OT é descontado da
  disponibilidade do monitor e da classe (`ZSEPEX_SALDO_PENDENTE`).
- Prazo (`DIAS_ALERTA`) só sinaliza; a separação continua.
- Estorno da saída depois de registrada marca o processo como cancelado (status 9); as OTs
  de regularização abertas devem ser estornadas na LT15.
- Remessa já com saída de mercadoria não aceita separação virtual (mensagem 003).

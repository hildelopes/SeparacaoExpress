# Request DERK989352 — Separação Express: portão/zona e filas na OT de regularização

| Campo | Valor |
|---|---|
| Request (Workbench) | **DERK989352** |
| Proprietário | ABAP02 |
| Descrição | Separacao Express |
| Pacote | ZSEPEX |
| Origem | Repositório `hildelopes/SeparacaoExpress`, branch `main`, commits `2762d65` e `51d32be` (26/11/2026) |
| Caminho | DEV → QAS → PRD |

## 1. O que a request leva

- A OT de regularização do Express passa a nascer com portão/zona da remessa de transferência no
  cabeçalho (`LTAK-LGTOR/LGBZO`) e é dividida em duas, como o Monitor de Carga: paletes inteiros na
  fila `PC_D_<portão>` e frações de palete (avulso) na fila `AV_D_<portão>`.
- ZSEPEX02 ganha as colunas Portão, Zona e Fila RF e o botão **Portão/Zona**, que redefine
  portão/zona nas remessas selecionadas: remessa (só sem saída), cabeçalho Express e OTs abertas.
- Registros antigos sem portão passam a usar o da remessa na próxima criação de OT.

## 2. Objetos da request (TADIR, pacote ZSEPEX)

| PGMID | OBJECT | OBJ_NAME | Alteração |
|---|---|---|---|
| R3TR | DTEL | ZSEPEX_FILA_REG_PREF | novo: prefixo da fila RF por portão (CHAR 10) |
| R3TR | TABL | ZSEPEX_T_PAR | campos `FILA_PAL_PREF`, `FILA_AVS_PREF` |
| R3TR | TABL | ZSEPEX_T_CAB | campos `LGTOR`, `LGBZO` |
| R3TR | TABL | ZSEPEX_T_OT | campo `INTEIRA` |
| R3TR | MSAG | ZSEPEX | mensagens 036 a 046 |
| R3TR | CLAS | ZCL_SEPEX_CONTROLE | método `GRAVAR_PORTAO_ZONA` |
| R3TR | CLAS | ZCL_SEPEX_WM | métodos `LER_PORTAO_REMESSA`, `ATUALIZAR_PORTAO_REMESSA`, `APLICAR_PORTAO_OT` |
| R3TR | FUGR | ZSEPEX_FG | `ZSEPEX_SEPARA_VIRTUAL` (grava portão/zona no cabeçalho), `ZSEPEX_CRIA_OT_REGUL` (duas OTs, portão/fila, novo export `E_TANUM_AVS`) |
| R3TR | PROG | ZSEPEX_R_REGULARIZAR | colunas, botão Portão/Zona, forms `F_PORTAO_ZONA`, `F_POPUP_PORTAO`, `F_APLICAR_PORTAO_REMESSA` |
| R3TR | FUGR | ZSEPEX_TMG | manutenção SM30 da `ZSEPEX_T_PAR` regerada na SE54 (gerada no DEV, entra na request ao salvar) |

Sem alteração em ZWMR0010, ZWM_ICENTROS, ZTM_REG_TRANSFERENCIA e ZCL_ARMAZEM_GERAL.

## 3. Sequência no DEV (antes de liberar)

1. abapGit: Pull do `main` com a request DERK989352 selecionada; ativar na ordem elemento de
   dados → tabelas → mensagens → classes → grupo de funções → programa.
2. SE54: regerar a manutenção SM30 da `ZSEPEX_T_PAR` (grupo `ZSEPEX_TMG`), salvando na mesma
   request.
3. SM30 `ZSEPEX_T_PAR` (customizing, não vai na request Workbench; repetir em QAS e PRD):
   `FILA_PAL_PREF = PC`, `FILA_AVS_PREF = AV`.
4. LRF1: conferir que existem as filas `PC_D_<portão>` e `AV_D_<portão>` para os portões usados
   nas remessas de transferência (hoje 001 a 008). Portão sem fila: a OT fica com portão gravado e
   fila original, mensagem 041 no log.
5. Teste rápido (seção 5) e liberar a request.

## 4. QAS e PRD após a importação

| Passo | Transação | O quê |
|---|---|---|
| 1 | STMS | Importar DERK989352; conferir log de ativação (ZSEPEX_T_PAR, ZSEPEX_T_CAB, ZSEPEX_T_OT só ganham campos, sem conversão) |
| 2 | SM30 | `ZSEPEX_T_PAR`: `FILA_PAL_PREF = PC`, `FILA_AVS_PREF = AV` |
| 3 | LRF1 | Filas `PC_D_<portão>` e `AV_D_<portão>` para todos os portões usados |
| 4 | PFCG | Nada novo: o botão Portão/Zona usa `ZSEPEX_EXP` ACTVT 16 (regularizar) |

## 5. Teste de aceite

| # | Cenário | Esperado |
|---|---|---|
| 1 | SEPARAR Express (ZWMR0010, `P_EXPR`) com portão 001 / zona na tela 0101, remessa com um material em palete fechado e outro em quantidade quebrada | `ZSEPEX_T_CAB-LGTOR/LGBZO` preenchidos; duas OTs de regularização na LT21 com portão/zona no cabeçalho: paletes em `PC_D_001`, avulso em `AV_D_001`; SLG1 com msgs 040 e 046 |
| 2 | LRF1 / LM05 | OTs aparecem nas filas por tipo; destino da OT continua `9EX/EXPRESS` (esperado) |
| 3 | ZSEPEX02, selecionar linhas da remessa, botão Portão/Zona → outro portão | VL03N com o portão novo (remessa sem saída), cabeçalho Express atualizado, LT21 das OTs abertas com portão novo e filas `PC_D_`/`AV_D_` do portão novo; mensagem 036 |
| 4 | Mesmo botão em remessa já com saída de mercadoria | Remessa intacta, mensagem 039, OTs atualizadas |
| 5 | Portão ou zona inválidos no popup | Mensagens 037 / 038, nada gravado |
| 6 | Processo antigo (sem portão no cabeçalho) → ZSEPEX02 Criar OTs | Portão vem da remessa, cabeçalho preenchido, OTs com portão e fila |
| 7 | Usuário só com ACTVT 03 | Botão aparece, ação recusada com a mensagem de autorização |

## 6. Retorno (se precisar desfazer)

Reimportar a versão anterior dos objetos (commit `077278c` do repositório) em nova request. Os
campos novos das tabelas podem ficar; a `ZSEPEX_T_PAR` com prefixos em branco já desliga a troca
de fila, e portão/zona só deixam de ser gravados.

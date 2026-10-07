# Separação Express no Armazém Geral (DPFE 1101 → CFMA 1102)

Fonte: repositório `hildelopes/ArmazemGeral`, commit `7ded585` (pacote `ZARMAZEM_GERAL`,
classe `ZCL_ARMAZEM_GERAL`, programas `ZAGR0001/2/3`, manual `docs/03`).

## 1. O que muda neste cenário

No fluxo intercentros (BAMO/CDII) a transferência é dentro da empresa 1101 e nasce de um
pedido UB. No Armazém Geral a mercadoria em DPFE **pertence à empresa 1102 (CFMA)** como
estoque consignado. A carga do depositante sai do DPFE por um **retorno de armazenagem**,
que é um processo intercompany com NF-e autorizada pela SEFAZ:

| Etapa | Intercentros (`ZWM_ICENTROS`) | Armazém Geral (`ZCL_ARMAZEM_GERAL`, rota R) |
|---|---|---|
| Documento de saída | Pedido UB + remessa de transferência | Ordem de venda **ZRTA** (DPFE 1101 → cliente 1000009 = CFMA) + remessa |
| Limite da quantidade | Estoque do DPFE | **Saldo consignado MSKU** do depositante, por material |
| Lotes | `ZSD_ICENTRO_ESTOQ` antes da OT | `DETERMINAR_LOTES_REMESSA` antes da OT: mais antigo primeiro, descontando outras remessas abertas |
| Picking | OT do grupo de remessas (`L_TO_CREATE_DN` com `REFNR`) | OT da remessa (`L_TO_CREATE_DN` sem grupo), fila `QUEUE_SAI`, criada por `OT_AUTO` ou pelo botão "Criar OT" |
| Confirmação | RF; status `A → S` pelo job | RF (LT12/RF) ou "Confirmar OT(s)" do monitor (marca `OT_CONF_MANUAL`); job `ZAGR0003` leva a `05` |
| Saída | `SAIDA_MERC` → 862 pelo engine | `SAIDA_MERC` → `REPROCESSAR` com `IV_LIBERAR_SAIDA`: PGI (`WS_DELIVERY_UPDATE`), **fatura ZRTA, NF-e** |
| Entrada no destino | 861 no mesmo job | Processo filho **ZRAR** no CFMA, disparado por qRFC quando a **SEFAZ autoriza** a NF-e |
| Lotes nas remessas de venda | `ZFWM_ADD_CHARG_TO_DT` | `DISTRIBUIR_LOTES_CARGA` na entrada ZRAR (mesma técnica), marca `LOTES_VENDA` |
| Liberação do carregamento (VT02N) | `ZWM_ICENTROS` status `F` | `VERIFICAR_CARGA_DT` = Finalizado (entrada concluída + `LOTES_VENDA`) |
| Conferência de expedição | HU da remessa de transferência | Sem grupo de remessas; `ZFWM_CHECK_DT_GRUPO` com `I_VBELN` compara a ZRTA com as remessas de venda |

Os dois fluxos compartilham o mesmo princípio que o Express explora: **o lote é fixado na
remessa antes da OT**, e **a saída só depende do status de picking/WM da remessa**
(`VBUK-KOSTK/LVSTK = C`). A classe checa exatamente isso em `EXECUTAR_PICKING_SAIDA`
antes do PGI.

## 2. Onde o Express entra na classe

O ponto é o ramo `WM_SAIDA = 'X'` de `EXECUTAR_PICKING_SAIDA`. Hoje:

```
aplicar_portao_zona( )
determinar_lotes_remessa( )             " lotes na remessa
IF ot_auto = 'X' OR mv_criar_ot = 'X'
  criar_ot_wm( squit = ot_conf_auto )   " L_TO_CREATE_DN pela estratégia
  atribuir_fila_ot( queue_sai )
ENDIF
ler_ot_remessa( ) → confirmada? status 05 : status 04 (aguarda RF)
```

Com Express:

```
aplicar_portao_zona( )
determinar_lotes_remessa( )
IF mv_express = 'X'
  ZSEPEX_SEPARA_VIRTUAL( lgnum, vbeln )  " OT com origem 9EX/EXPRESS por item de lote,
                                         " confirmada; cria OTs de regularização
  status 05 (picking OK)                 " sem passar por 04
ELSEIF ot_auto = 'X' OR mv_criar_ot = 'X'
  ... (inalterado)
```

Tudo o que vem depois é o fluxo atual: `SAIDA_MANUAL` para em `05` aguardando "Saída de
Merc."; o botão faz PGI, fatura ZRTA e NF-e; a SEFAZ autoriza; a entrada ZRAR distribui os
lotes nas remessas de venda; o VT02N libera o carregamento com `Finalizado`.

Alterações na classe e no monitor:

| Objeto | Alteração |
|---|---|
| `ZAGT_LOG` | Campo `EXPRESS` (append `ZSEPEX_A_ZAGT_LOG`), ao lado de `SAIDA_MANUAL`, `OT_CONF_MANUAL`, `FROTA_PROP` |
| `ZCL_ARMAZEM_GERAL` | Atributo `mv_express`; método `SET_EXPRESS`; parâmetro `iv_express` em `CRIAR_POR_TRANSPORTE`; desvio em `EXECUTAR_PICKING_SAIDA` (acima); `SINCRONIZAR_ITENS_REMESSA` funciona sem mudança, pois lê a LIPS |
| `ZAGR0002` (cockpit) | Coluna `Express` e status "aguardando regularização física" vindo de `ZSEPEX_T_CAB` |
| `ZAGR0003` (job) | Sem alteração: processo Express nunca fica em `04` |
| `ZWMR0010` (`ZF_SEPARACAO_RETORNO`) | Repassa `P_EXPR` para `CRIAR_POR_TRANSPORTE( iv_express )` e grava `ZWMT011` |
| `ZWMRF0002` | Sem alteração (carga dispensada pela `ZWMT011`) |

## 3. O que o pacote ZSEPEX precisa mudar para servir aos dois

A v0.4 amarrou o controle Express ao número do processo `ZWM_ICENTROS`. Para servir ao
Armazém Geral, o controle passa a ser **por remessa de saída do DPFE**, com a origem como
atributo:

| Objeto | Ajuste |
|---|---|
| `ZSEPEX_T_CAB` | Chave `LGNUM + VBELN` (remessa de saída: transferência ou ZRTA). Campos `ORIGEM` (`I` intercentros, `A` armazém geral), `ORIGEM_ID` (número `ZWM_ICENTROS` ou GUID `ZAGT_LOG`), `TKNUM`, `REFNR` (opcional), status, datas |
| `ZSEPEX_T_ITM` | Chave `LGNUM + VBELN + POSNR` (item de lote da remessa) |
| `ZSEPEX_SEPARA_VIRTUAL` | Interface: `I_LGNUM`, `I_VBELN`, `I_REFNR` (opcional), `I_ORIGEM`, `I_ORIGEM_ID`, `I_TKNUM`. Lê os itens de lote da LIPS, monta `IT_DELIT` com origem virtual, `L_TO_CREATE_DN` + `L_TO_CONFIRM`, grava `ZSEPEX_T_CAB/ITM`, chama `ZSEPEX_CRIA_OT_REGUL` se `OT_IMEDIATA`. Independe de qual engine chamou |
| `ZSEPEX_CRIA_OT_REGUL` | Por remessa; mesma lógica de UDs por lote |
| `ZSEPEX_SALDO_PENDENTE` | Por material e lote, somando as duas origens; usado pelo monitor e por `DETERMINAR_LOTES_REMESSA` (ver risco R1) |
| `ZSEPEX_R_PENDENCIAS` | Coluna "Origem" e navegação: intercentros → `ZWM_ICENTROS`, armazém geral → cockpit ZAGT02 |
| `ZSEPEX_R_SINCRONIZAR` | Lê `VBUK-WBSTK` da remessa (vale para as duas origens) e `LTAP` das OTs de regularização |

O hook no `ZWM_ICENTROS` passa a chamar a mesma função com `I_ORIGEM = 'I'` e
`I_REFNR = grupo`; a classe chama com `I_ORIGEM = 'A'` e sem grupo.

## 4. Riscos específicos do Armazém Geral

| # | Risco | Tratamento |
|---|---|---|
| R1 | `DETERMINAR_LOTES_REMESSA` desconta lotes comprometidos por remessas de saída **abertas** (`VBUK-WBSTK <> C`). Depois do PGI Express a remessa fecha e o lote pendente de regularização volta a parecer livre para a próxima ZRTA | Incluir no desconto o saldo de `ZSEPEX_SALDO_PENDENTE` por material e lote |
| R2 | NF-e intercompany autorizada com lote X. Troca de lote na regularização exige ajuste nos dois lados **e** em empresas diferentes | Fase 1: sem troca de lote (só UD do mesmo lote). Ajuste intercompany fica fora do escopo até o fiscal decidir |
| R3 | Entrada ZRAR depende da autorização SEFAZ no dia 31 | Já é assim hoje; o Express não altera. Pendência de SEFAZ aparece no cockpit |
| R4 | `ZFWM_CHECK_DT_GRUPO` com `I_VBELN` compara ZRTA x remessas de venda antes da saída | Sem impacto: lotes virtuais são os da LIPS |
| R5 | Botão "Confirmar OT(s)" do monitor em processo Express | Não há OT aberta do processo (a virtual já está confirmada); as OTs de regularização não têm `LTAK-VBELN` da ZRTA e não aparecem na lista. Sem impacto |
| R6 | "Estornar/Cancelar" pelo cockpit depois da separação virtual | Mesma limitação do intercentros: após a OT virtual, cancelar exige tratar o negativo em `9EX`. Documentar como não reversível pelo cockpit |
| R7 | Saldo consignado MSKU | Não muda: a validação continua por material antes da ordem |

## 5. Decisão

Um único pacote ZSEPEX, com o controle por remessa de saída e dois pontos de entrada:
engine `ZWM_ICENTROS` (intercentros) e classe `ZCL_ARMAZEM_GERAL` (armazém geral). No
Monitor de Carga o encarregado marca o mesmo checkbox `Separação Express`; o monitor já
decide por `ZF_AG_CARGA_DEPOSITANTE` qual dos dois fluxos a carga segue, e o Express
acompanha essa decisão.

## 6. Pendências novas

| ID | Pergunta |
|---|---|
| Q-AG1 | Respondida: OT pelo botão, confirmação no RF, lote definido na remessa. Ponto de desvio confirmado (D14). |
| Q-AG2 | Respondida: conferência quando necessária hoje, e **necessária** para a carga Express (D15). |
| Q-AG3 | Respondida: sim, mesma pressão de prazo. |

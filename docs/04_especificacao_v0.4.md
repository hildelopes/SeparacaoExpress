# Separação Express – Especificação técnica v0.4 (consolidada)

Substitui a v0.3 (`01_especificacao_separacao_express.md`) nos pontos em que divergem.
Baseada na análise do `ZWMR0010` (`02_...`), nas decisões D1 a D12 (`03_...`) e nos
programas `ZWMRF0002` (conferência de expedição) e `Z_WM_CONFIRMA_ICENTRO` (carga fechada).

## 1. Resumo do desenho

A Separação Express é uma **nova variante da ação "Criar Grupo R./Ordem" do Monitor de
Carga** (`ZWMR0010`), ao lado da carga fechada, que ela substitui. No dia do fechamento:

1. O encarregado marca `Separação Express` na tela de seleção e aciona SEPARAR na carga.
2. O monitor registra a transferência intercentros como hoje (`ZTM_REG_TRANSFERENCIA`),
   com a nova marca `EXPRESS`, e cadastra a carga na `ZWMT011` (dispensa de conferência de
   expedição), como a carga fechada já faz.
3. O engine `ZWM_ICENTROS` cria pedido, remessa de transferência (lotes pela
   `ZSD_ICENTRO_ESTOQ`), transporte e grupo como hoje. No ponto em que a carga fechada chama
   `Z_WM_CONFIRMA_ICENTRO`, o Express chama `ZSEPEX_SEPARA_VIRTUAL`: OT da remessa com
   origem na posição virtual `9EX/EXPRESS`, confirmada na hora. Nasce o quant negativo por
   material e lote. Status `S`.
4. Na mesma execução, o Express cria as **OTs de regularização** (bins reais → `9EX/EXPRESS`,
   não confirmadas), que reservam as UDs. Elas ficam aguardando o RF.
5. Saída de mercadoria, entrada no destino, lotes nas remessas de venda e faturamento
   seguem exatamente o fluxo atual (`SAIDA_MERC`, 862, 861, `ZFWM_ADD_CHARG_TO_DT`, VT02N).
6. Nos dias seguintes o operador confirma as OTs de regularização no **RF Express**
   (`ZSEPEXRF`), lendo a UD do palete e, em quantidade parcial, a etiqueta de HU
   pré-impressa. Cada leitura vira um volume da carga. O job de sincronização fecha os
   itens quando o negativo da posição virtual zera.
6a. No carregamento, a conferência de expedição (`ZWMRF0002`) lê os volumes da carga
   Express como lê HUs hoje.
7. O relatório de pendências mostra o que falta separar, por carga, com idade, e envia
   e-mail diário.

Nada muda em tipo de remessa, categoria de item, relevância de picking, movimento 862 ou
interface MM-WM. O único customizing é o tipo de depósito virtual e um tipo de movimento WM.

## 2. Estados do estoque (material M, lote X, quantidade Q)

| Momento | MM DPFE | WM bins (UD) | WM 9EX/EXPRESS | WM 916 | Destino |
|---|---|---|---|---|---|
| Antes | Q | Q | 0 | 0 | 0 |
| Após OT virtual confirmada | Q | Q | −Q | +Q | 0 |
| Após OT de regularização criada | Q | Q (reservado) | −Q | +Q | 0 |
| Após PGI 862 e 861 (fluxo atual) | 0 | Q (reservado) | −Q | 0 | Q |
| Após LM45 | 0 | 0 | 0 | 0 | Q |

Total WM = total MM em todas as linhas. LX23 fecha em zero.

## 3. Customizing (consultor WM, prova de conceito em QAS)

| # | Item | Detalhe |
|---|---|---|
| C1 | Tipo de depósito `9EX` no depósito DFC | Cópia do 999: estoque negativo permitido, sem gestão de UD, estoque misto permitido, sem estratégia de entrada/saída, fora das sequências de busca. Posição fixa `EXPRESS` (LS01N). |
| C2 | Tipo de movimento WM `9EX` (ou `9EX` + `9EY`) | Cópia do 999: origem por estratégia dos tipos `DIA/DTA/XDC/DII`, destino fixo `9EX/EXPRESS`, confirmação exigida, sem lançamento MM. Usado pelas OTs de regularização. |
| C3 | Prova: `L_TO_CREATE_DN` com `IT_DELIT` origem `9EX/EXPRESS` em posição vazia | Deve criar quant negativo. Se recusar, fallback: posição `EXPRESS` em `999` (comportamento já comprovado pela carga fechada em `999/SEPARACAO`), com restrição de LI21 por procedimento. |
| C4 | Prova: `L_TO_CREATE_MULTIPLE` com UD de origem (`VLENR`) por item e destino `9EX/EXPRESS` | Confirmável na LM45. |
| C5 | LM45 com tipo de movimento `9EX` | Fila RF, impressão, diferença para 999 em caso de UD não encontrada. |

## 4. Objetos novos (pacote `ZSEPEX`)

### 4.1 Dicionário

| Objeto | Tipo | Campos principais |
|---|---|---|
| `ZSEPEX_T_PAR` | Tabela | `LGNUM` (chave), `LGTYP_VIRT`, `LGBER_VIRT`, `LGPLA_VIRT`, `BWLVS_REG`, `OT_IMEDIATA`, `DIAS_ALERTA`, `EMAIL_DEST` (string), `AJUSTE_LOTE` (permite 309) |
| `ZSEPEX_T_CAB` | Tabela | `LGNUM`, `VBELN` (chave; remessa de saída do DPFE: transferência ou ZRTA), `ORIGEM` (`I` intercentros, `A` armazém geral), `ORIGEM_ID` (número `ZWM_ICENTROS` ou GUID `ZAGT_LOG`), `TKNUM`, `REFNR`, `STATUS`, `DT_VIRT`, `DT_PGI`, `DT_CONCL`, `ERNAM/ERDAT/ERZET`, `AENAM/AEDAT/AEZET` |
| `ZSEPEX_T_ITM` | Tabela | `LGNUM`, `VBELN`, `POSNR` (chave; item de lote da remessa), `MATNR`, `CHARG`, `MENGE`, `MEINS`, `TANUM_VIRT`, `TAPOS_VIRT`, `QTD_REGUL`, `STATUS` |
| `ZSEPEX_T_OT` | Tabela | `LGNUM`, `TANUM`, `TAPOS` (chave), `VBELN`, `POSNR`, `MATNR`, `CHARG`, `VLENR`, `VSOLM`, `NISTM`, `NDIFA`, `PQUIT`, `AEDAT` |
| `ZSEPEX_T_VOL` | Tabela | `LGNUM`, `VOLUME` (chave; UD ou etiqueta), `TKNUM`, `VBELN`, `POSNR`, `MATNR`, `CHARG`, `MENGE`, `MEINS`, `TANUM`, `TAPOS`, `TIPO` (`U` UD inteira, `E` etiqueta parcial), `ERNAM/ERDAT/ERZET` |
| `ZSEPEX_D_STATUS` | Domínio | `0` Registrado, `1` Separação virtual, `2` OT regularização criada, `3` PGI efetuado, `4` Em regularização, `5` Concluído, `9` Cancelado |
| `ZSEPEX_S_PEND`, `ZSEPEX_S_REG`, `ZSEPEX_S_LOG` | Estruturas | Saídas ALV |

### 4.2 Funções e classes

| Objeto | Responsabilidade |
|---|---|
| `ZSEPEX_SEPARA_VIRTUAL` (FM, grupo `ZSEPEX_FG`) | Interface por remessa: `I_LGNUM`, `I_VBELN`, `I_REFNR` (opcional), `I_ORIGEM`, `I_ORIGEM_ID`, `I_TKNUM`. Lê itens de lote da LIPS, monta `IT_DELIT` com origem virtual, `L_TO_CREATE_DN` + `L_TO_CONFIRM` (padrão dos passos 8 a 10 de `Z_WM_CONFIRMA_ICENTRO`), grava `ZSEPEX_T_CAB/ITM` status 1. Se `OT_IMEDIATA`, chama `ZSEPEX_CRIA_OT_REGUL`. Chamada pelo engine `ZWM_ICENTROS` (origem `I`, uma vez por remessa do grupo) e pela classe `ZCL_ARMAZEM_GERAL` (origem `A`). |
| `ZSEPEX_CRIA_OT_REGUL` (FM) | Para os itens pendentes de um processo: escolhe UDs com as regras de `ZF_PREENCHE_SIMULACAO` e `ZF_FILTRA_LQUA_DISPONIVEL` (mesmo lote do item, `MLGN-LHMG1`, prioridade `999/SEPARACAO`, sem OT aberta, posição não bloqueada), cria OT por remessa com `L_TO_CREATE_MULTIPLE` (itens por UD, destino `9EX/EXPRESS`, `BWLVS_REG`), grava `ZSEPEX_T_OT`, status 2. Saldo não coberto fica pendente com motivo. |
| `ZSEPEX_SALDO_PENDENTE` (FM) | Retorna, por material (e lote), a quantidade Express ainda sem OT de regularização. Usada pelo monitor na validação de saldo. |
| `ZCL_SEPEX_CONTROLE` | Persistência, transições de status, bloqueio `EZSEPEX_CAB` |
| `ZCL_SEPEX_UD` | Seleção de UDs (lógica extraída da simulação do monitor, parametrizada por lote) |
| `ZCL_SEPEX_WM` | Wrappers de `L_TO_CREATE_DN`, `L_TO_CONFIRM`, `L_TO_CREATE_MULTIPLE`, leitura `LTAP/LQUA` |
| `ZCL_SEPEX_MM` | Fase 2: transferências 309 do ajuste de lote |
| `ZCL_SEPEX_LOG` | Application log objeto `ZSEPEX` |
| `ZCL_SEPEX_AUTH` | Objeto `ZSEPEX_AUT` (`LGNUM`, `ACTVT`: 01 liberar, 02 regularizar, 03 exibir, 85 ajustar) |

### 4.3 Programas e transações

| Programa | Transação | Função |
|---|---|---|
| `ZSEPEX_R_REGULARIZAR` | `ZSEPEX02` | ALV dos itens pendentes (por carga, processo, remessa, material, lote): criar OT de regularização, recriar para saldo após diferença, trocar UD, fase 2 ajuste de lote. |
| `ZSEPEX_R_PENDENCIAS` | `ZSEPEX03` | Pendências com idade e destaque acima de `DIAS_ALERTA`, totais por carga e por data de PGI, versão de fechamento com `LQUA` negativa em `9EX`, envio por e-mail (job diário). |
| `ZSEPEX_R_SINCRONIZAR` | `ZSEPEX04` | Job (30 min): lê `LTAP` das OTs de regularização (`PQUIT`, `NISTM`, `NDIFA`), atualiza `QTD_REGUL`, status 4 e 5; lê `VBUK-WBSTK` da remessa de transferência para `DT_PGI` e status 3; detecta estorno de PGI → status 9. |
| `ZSEPEX_R_PARAM` | `ZSEPEX00` | Manutenção de `ZSEPEX_T_PAR` (ou SM30). |
| `ZSEPEX_RF` (pool de módulos, padrão `ZWMRF0002`) | `ZSEPEXRF` | RF de regularização: lista as OTs de regularização da carga ou da OT lida; operador lê a **UD** (validada contra `LTAP-VLENR` do item); quantidade parcial pede a **etiqueta de HU pré-impressa**; confirma o item (`L_TO_CONFIRM`) e grava `ZSEPEX_T_VOL`. Substitui a LM45 no Express, para que a conferência de expedição tenha os volumes. |

### 4.4 Demais

Classe de mensagens `ZSEPEX`, objeto de log `ZSEPEX`, objeto de autorização `ZSEPEX_AUT`,
objeto de bloqueio `EZSEPEX_CAB`, variantes e jobs. Repositório em formato abapGit em `src/`.

## 5. Alterações em objetos existentes

### 5.1 `ZWMR0010` (Monitor de Carga)

| Include | Alteração |
|---|---|
| `ZWMR0010_PARAMETROS` | Checkbox `P_EXPR` "Separação Express" no bloco `B5`, exclusivo com `P_FECH`. |
| `ZWMR0010_ALV` (`USER_COMMAND_OO`) | `SEPARAR` com `P_EXPR` → `ZF_SEPARAR_EXPRESS`. |
| `ZWMR0010_FORM` | Novo `ZF_SEPARAR_EXPRESS`: uma carga, bloqueio `VTTK`, status transporte `2`, não AG, sem processo ativo; tela 0101 de portão/zona; `ZF_PREPARA_ITENS`; `ZF_VALIDA_SALDO_TRANSF` (ver abaixo); `ZF_CRIA_TRANSFERENCIA` com novo parâmetro `P_EXPRESS`; grava `ZWMT011` e `ZSEPEX_T_CAB` status 0. |
| `ZWMR0010_FORM` (`ZF_CRIA_TRANSFERENCIA`) | Parâmetro `P_EXPRESS` repassado a `ZTM_REG_TRANSFERENCIA` (`I_EXPRESS`). |
| `ZWMR0010_FORM` (`ZF_VALIDA_SALDO_TRANSF`, `ZF_PREENCHE_SIMULACAO`) | Descontar o saldo retornado por `ZSEPEX_SALDO_PENDENTE` (Express sem OT de regularização). |
| `ZWMR0010_TOP` / `ZF_MONTA_ALV` | Coluna ícone `EXPRESS` e texto de status Express; hotspot abre `ZSEPEX03` filtrado pela carga. |
| `ZF_ESTORNAR_SEPARACAO` | Sem alteração: estorno só em status `R`, antes da OT virtual. Após a OT virtual o Express não é reversível pelo monitor. |

### 5.2 `ZTM_REG_TRANSFERENCIA`

Novo parâmetro `I_EXPRESS` → novo campo `ZWM_ICENTROS-EXPRESS` (append structure
`ZSEPEX_A_ICENTROS`, para não alterar a tabela padrão do engine).

### 5.3 `ZWM_ICENTROS` (`LZWM_ICENTROSTOP`)

| Ponto | Alteração |
|---|---|
| `ZF_CONFIRMA_ETAPAS`, ramo `(M ou R) e status R/N` | Antes do `ELSEIF automatica`: `ELSEIF wa_icentros-express = abap_true` → `CALL FUNCTION 'ZSEPEX_SEPARA_VIRTUAL'`; sucesso → status `S`; erro → `ZF_LOG_ERROR`. |
| Bloco final da FM (`automatica = X AND status = R`) | Mesmo tratamento para `EXPRESS`, para não esperar a próxima execução do job. |
| `ZF_CRIA_OT`, `ZF_CONTINUA_OT` | `CONTINUE` quando `EXPRESS = X` (igual ao `AUTOMATICA`), evitando OT física duplicada se alguém acionar "Criar OT". |

### 5.4 Conferência de expedição (`ZWMRF0002`) e volumes do Express

A carga Express entra na `ZWMT011` **só para liberar o faturamento no dia 31**. A
conferência de expedição continua obrigatória e acontece no carregamento, nos dias
seguintes. Como a remessa já tem PGI, não há HU SAP: o volume do Express é a **UD** do
palete inteiro ou a **etiqueta de HU pré-impressa** colada em quantidade parcial, ambas
gravadas em `ZSEPEX_T_VOL` pelo RF de regularização (ver 4.3, `ZSEPEX_RF`).

| Ponto do `ZWMRF0002` | Alteração para carga Express (existe `ZSEPEX_T_CAB` com o `TKNUM`) |
|---|---|
| `F_VERIFICA_SAIDA_MERCADORIA` | Não aplicar E05 (saída já efetuada) nem E20 (pendência de OT): a saída é esperada e a OT virtual está confirmada |
| `F_CREATE_NEW_VERSAO` | Montar `ZTWM_CONF_OV_U/D` a partir de `ZSEPEX_T_VOL` (volume, remessa, item, material, lote, quantidade) em vez de `VEKP/VEPO` |
| Leitura do volume (`WA_9001-HU`) | Aceitar UD ou etiqueta; validação contra `ZTWM_CONF_OV_U` como hoje |
| `F_ENCERRAR` | Sem alteração |

`ZWMR0007` (monitor de conferência) não muda: lê as mesmas tabelas.

### 5.5 `ZCL_ARMAZEM_GERAL` (Armazém Geral)

Ver `05_analise_armazem_geral_express.md`: campo `EXPRESS` em `ZAGT_LOG` por append,
atributo e `SET_EXPRESS` na classe, desvio no ramo WM de `EXECUTAR_PICKING_SAIDA` para
`ZSEPEX_SEPARA_VIRTUAL` (status 05 direto), parâmetro em `CRIAR_POR_TRANSPORTE`, coluna
no cockpit. `DETERMINAR_LOTES_REMESSA` passa a descontar `ZSEPEX_SALDO_PENDENTE`.

## 6. Regras de negócio

| Tema | Regra |
|---|---|
| Quem usa | Encarregado ou gestão, só no último dia do fechamento. Autorização `ZSEPEX_AUT` 01. |
| Lote | O lote da remessa de transferência é o determinado pela `ZSD_ICENTRO_ESTOQ`. A OT de regularização nomeia UDs desse lote. Fase 1: troca de UD só dentro do mesmo lote. Fase 2: troca de lote com 309 nos dois centros, habilitada por `AJUSTE_LOTE` após o fiscal aprovar. |
| Prazo | Até 7 dias (`DIAS_ALERTA`). Acima disso só sinaliza; a separação continua. |
| UD não encontrada | Operador confirma com diferença na LM45 (vai para 999). Sincronização marca saldo pendente; Z02 recria OT para o restante em outra UD. Diferença física tratada pelo inventário WM padrão. |
| Carga cancelada após PGI | Fora do Express (VL09, NF, entrada). Sincronização marca status 9 e as OTs de regularização abertas devem ser estornadas por `LT15`; o quant negativo em `9EX` fica para análise. |
| Conferência de expedição | Obrigatória, no carregamento, pelo `ZWMRF0002` adaptado contra os volumes de `ZSEPEX_T_VOL`. A `ZWMT011` só libera o faturamento no dia 31. |

## 7. Plano de testes (QAS)

| # | Cenário | Esperado |
|---|---|---|
| T1 | SEPARAR com `P_EXPR` em carga com 3 remessas de venda, 2 materiais com lote | Processo com `EXPRESS = X`, `ZWMT011` gravada, pedido/remessa/grupo criados, remessa com divisão de lote |
| T2 | Engine em status `R` | OT virtual confirmada, `LQUA` negativa em `9EX/EXPRESS` por material/lote, `VBUK-KOSTK = C` e `LVSTK = C`, status `S`, `ZSEPEX_T_ITM` status 1 |
| T3 | OTs de regularização | Criadas por UD, `LTAP-PQUIT` vazio, UDs com quantidade de saída em aberto; carga fechada/simulação não enxerga essas UDs |
| T4 | `SAIDA_MERC` e job | 862, 861 com lotes, lotes nas remessas de venda, `ZWM_ICENTROS` status `F`, Express status 3 |
| T5 | Faturamento VT02N | Sem exigir conferência (`ZWMT011`) |
| T6 | RF Express total (UD inteira e parcial com etiqueta) | Negativo zerado, status 5, LX23 zero, volumes em `ZSEPEX_T_VOL` |
| T7 | RF Express com UD não encontrada | Diferença em 999, saldo pendente, Z02 recria em outra UD do mesmo lote |
| T7b | Conferência de expedição da carga Express | `ZWMRF0002` lista os volumes, aceita UD e etiqueta, encerra com status 03 |
| T7c | Carga do depositante (ZRTA) com Express | Status 05 direto, Saída de Merc., NF-e, entrada ZRAR e lotes nas remessas de venda como hoje |
| T8 | Outra carga tenta usar UD reservada | Simulação e OT física não escolhem a UD |
| T9 | Validação de saldo pós-PGI Express | Saldo disponível desconta o pendente Express |
| T10 | Estorno antes da OT virtual | `ZWM_ESTORNO_ICENTROS` funciona; Express status 9 |
| T11 | Volume: carga com 30 remessas e 40 materiais | Tempo do engine dentro da janela, sem deadlock |
| T12 | Autorizações | Perfis separados |

## 8. Fases

| Fase | Conteúdo | Pré-requisito |
|---|---|---|
| 0 | Customizing C1, C2 e provas C3 a C5 em QAS | Consultor WM |
| 1 | Dicionário, `ZSEPEX_FG`, classes, hook no engine e na classe do Armazém Geral, checkbox e `ZF_SEPARAR_EXPRESS` no monitor, ajuste de saldo, `ZSEPEX02/03/04`, jobs, autorizações | C3 aprovada |
| 1b | RF Express (`ZSEPEXRF`) e adaptação do `ZWMRF0002` para volumes Express | Fase 1 em QAS |
| 2 | Ajuste de lote com 309 (`AJUSTE_LOTE`), aposentadoria da carga fechada | Fiscal e logística |

## 9. Estrutura do repositório

```
src/                       abapGit, pacote ZSEPEX
  zsepex_t_par.tabl.xml   ...dicionário
  zsepex_fg.fugr.xml      funções
  zcl_sepex_*.clas.*      classes
  zsepex_r_*.prog.*       programas
alteracoes/                trechos a aplicar nos objetos existentes (ZWMR0010, ZWM_ICENTROS,
                           ZTM_REG_TRANSFERENCIA), com marcação "SEPEX" nos comentários
docs/                      especificações e decisões
```

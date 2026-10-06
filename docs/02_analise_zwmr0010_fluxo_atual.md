# Análise do ZWMR0010 (Monitor de Carga) e impacto na Separação Express

Fonte: repositório `hildelopes/ZWMR0010`, commit `e6b8b4d`. Programa `ZWMR0010`
(Monitor WM – GAP WM_Z_008) e grupos de funções `ZWM_ICENTROS`, `ZTM_REG_TRANSFERENCIA`,
`ZWM_IC_EF`, `ZFG_WM_ICENTROS`, `ZSDGF_ICENTRO_ESTOQ`, `ZGFWM_ADD_CHARG`,
`ZGWM_CHECK_DT_GRUPO`.

## 1. O que o monitor faz

O monitor lista **cargas** (transportes `VTTK` com remessas de venda dos centros de
faturamento BAMO/CDII, criadas no `VSTEL` BADF/DFCF). A separação física acontece no
DPFE (depósito WM `LGNUM = DFC`), e o estoque chega ao centro de faturamento por uma
**transferência intercentros gerada pelo próprio monitor**, agregando os materiais de
todas as remessas de venda da carga. Isso confirma o que foi dito: a remessa de
transferência não existe antes; ela nasce no momento da separação.

Objetos de controle do processo:

| Tabela | Conteúdo |
|---|---|
| `ZWM_ICENTROS` | Cabeçalho do processo (número, modo, centro origem/destino, status, `DOCREF` = transporte da carga, flags `ETAPAS2`, `SPLAN`, `AUTOMATICA`, `LOTE_UDT`) |
| `ZWM_IC_ITENS` | Materiais agregados da carga (soma de `LIPS-LFIMG` com `KOMKZ` preenchido) |
| `ZWM_IC_EF` | Etapas (passos) do processo: pedido, remessa, transporte, grupo, saída, entrada, inbound, `CTRL_OT`, `FINALIZADO` |
| `ZTM_REG_TRANSF` | Regras: modo, origem, destino, tipo de material → passos com depósito, local de expedição e flags `AUTO_SAIDA` / `AUTO_ENTRADA` |
| `ZWM_CONF_UD` | Carga fechada: UDs (`LENUM`), posições e lotes escolhidos na simulação |
| `ZWMT011` | Carga fechada: transportes processados |
| `LIKP-ZZICENTROS` | Marca a remessa de transferência para a validação de saldo |
| `VTTK-TEXT4` | Grupo de remessas WM (`REFNR`) gravado no transporte da carga |
| `VTTK-TEXT3` | Posição intermediária (picking em 2 etapas) |

## 2. Fluxo atual, modo `M` (Monitor), passo a passo

```
Monitor "Criar Grupo R./Ordem" (SEPARAR)
  ├─ ZF_CRIA_TRANSFERENCIA: agrega LIPS das remessas de venda da carga por material
  ├─ ZTM_REG_TRANSFERENCIA: grava ZWM_ICENTROS (status 8) + ZWM_IC_ITENS, SPLAN = X
  ├─ ZWM_CADASTRO_ETAPAS: gera ZWM_IC_EF a partir de ZTM_REG_TRANSF (status I)
  └─ ZWM_ICENTROS em background task (fila ZCL_FILA_BCKG)

ZWM_ICENTROS (job, reexecutado até concluir)
  ├─ BAPI_PO_CREATE1: pedido UB DPFE → BAMO/CDII, categoria 7, Incoterm ZSF  (status P)
  ├─ BAPI_OUTB_DELIVERY_CREATE_STO: remessa de transferência (ou SHP_DELIVERY_CREATE_FROM_STO com lote)
  │    ├─ ZF_VERIFICA_REMESSA: remessa deve ter a quantidade do pedido, senão apaga e loga
  │    ├─ UPDATE LIKP-ZZICENTROS = X
  │    ├─ WS_DELIVERY_UPDATE: portão, zona, prioridade
  │    └─ ZSD_ICENTRO_ESTOQ: determina LOTES (MCHB/LQUA, FIFO por validade) e grava a
  │         divisão de lote na remessa de transferência (BAPI_OUTB_DELIVERY_CHANGE)
  ├─ BAPI_SHIPMENT_CREATE: transporte da remessa de transferência
  ├─ ZF_CRIA_GRUPO_UN: WS_LM_GROUP_CREATE (grupo com a remessa de transferência + remessas
  │    de kit ZWMT013), grava REFNR em VTTK-TEXT4; ZWM_2STEP_TO_1STEP           (status R)
  └─ aguarda

Monitor "Criar OT" (SEPARAR_F)  →  ZWM_ICENTROS com I_CRIAOT
  └─ L_TO_CREATE_DN (LGNUM DFC, I_REFNR = grupo, não confirmada)                 (status A)

RF (transações LM) confirma as OTs
  └─ job: todas LTAK do grupo com KQUIT = X                                       (status S)

Monitor "Saída Merc." (SAIDA_MERC), ação manual
  ├─ ZFWM_CHECK_DT_GRUPO: compara qtd por material/lote da remessa de transferência
  │    com as remessas de venda da carga
  └─ status P, limpa SPLAN

ZWM_ICENTROS (job)
  ├─ ZSD_SAIDA_REMESSA: PGI da remessa de transferência (movimento 862)
  ├─ ZF_REALIZA_ENTRADA: BAPI_GOODSMVT_CREATE 861 no centro de faturamento, por item de
  │    divisão de lote da remessa (LIPS POSNR ≥ 900000, CHARG)
  ├─ etapa FINALIZADO                                                             (status Z)
  └─ ZF_AT_REMESSA_VENDA:
       ├─ ZTM_EMBALARDT (desembala as remessas de venda)
       ├─ ZFWM_ADD_CHARG_TO_DT: copia os lotes da LIPS da remessa de transferência para
       │    a divisão de lote das remessas de venda
       └─ ZTM_EMBALARDT (reembala)                                                (status F)

Faturamento das remessas de venda pelo transporte (VT02N)
```

Estorno pelo monitor (`ZWM_ESTORNO_ICENTROS`) só é permitido em status `R`, antes das OTs.

## 3. Carga fechada (`P_FECH`): separação decidida pelo sistema

Já existe no monitor um modo em que o WM é "resolvido" pelo sistema, sem picking físico
prévio:

1. `ZF_SEPARAR_FECHADA` abre a simulação (tela 0300). `ZF_PREENCHE_SIMULACAO` escolhe UDs
   em `LQUA` dos tipos `DIA`, `DTA`, `XDC`, `DII`, `999`, priorizando `999/SEPARACAO`,
   respeitando a quantidade por UD (`MLGN-LHMG1`) e descartando UDs com OT aberta e
   posições bloqueadas (`ZF_FILTRA_LQUA_DISPONIVEL`).
2. `ZF_MASS_TRANSF` valida saldo (`ZF_VALIDA_SALDO_TRANSF`, descontando remessas
   `ZZICENTROS` sem PGI e itens não separados por `VBUP-KOSTA`), cria a transferência com
   `AUTOMATICA = X` e grava `ZWM_CONF_UD`.
3. `ZSD_ICENTRO_ESTOQ` usa os lotes de `ZWM_CONF_UD` na divisão de lote da remessa.
4. `Z_WM_CONFIRMA_ICENTRO` (status `R`):
   bloqueia as posições de origem (LS02N via BDC), move as UDs para `999/SEPARACAO`
   (`L_TO_CREATE_SINGLE`, movimento 999, confirmada), cria a OT da remessa com origem
   `999/SEPARACAO` por item de lote (`L_TO_CREATE_DN` com `IT_DELIT`) e confirma
   (`L_TO_CONFIRM`). Status `S`, e o processo segue igual ao fluxo normal.
5. A separação física depois é guiada por pick list (`ZF_PICKLIST_FECHADA`), sem OT de RF.

Conclusão importante: a carga fechada já prova no ambiente produtivo que OT confirmada
contra posição 999 (estoque negativo permitido) funciona e não gera documento de material.
As premissas P2 e P4 do roteiro estão comprovadas na prática.

## 4. Impacto no desenho da Separação Express

### 4.1 O que muda em relação à especificação v0.3

| Item da v0.3 | Situação após a análise |
|---|---|
| Remessas de transferência já existem antes do fechamento | **Errado.** Nascem no monitor, na ação SEPARAR. O Express entra como variante dessa ação. |
| Z01 escolhe lote por FIFO em LQUA | **Já existe.** `ZSD_ICENTRO_ESTOQ` grava a divisão de lote antes da OT. O Express só reaproveita. |
| Lote vai para a NF e para o destino | Confirmado: 861 e `ZFWM_ADD_CHARG_TO_DT` leem a LIPS da remessa de transferência. A OT virtual deve usar exatamente esses lotes. |
| Dúvida P-HU (embalagem obrigatória) | A embalagem (`ZTM_EMBALARDT`) é nas remessas de **venda**, depois dos lotes. A remessa de transferência sai sem HU hoje. Risco afastado, a confirmar com uma execução em QAS. |
| Z04 sincroniza por LIKP/VBFA | O engine `ZWM_ICENTROS` já controla PGI, entrada e status. O Express não deve duplicar isso. |
| Z05 bloqueio de saldo | Mantido fora do escopo: OT de regularização aberta reserva o quant. Mas ver 4.3. |

### 4.2 Desenho C ajustado ao monitor (proposta)

Variante "Separação Express" da carga fechada, com o mínimo de mudança no engine:

1. **Monitor:** novo checkbox `P_EXPR` (ao lado de `P_FECH`). Ação SEPARAR com `P_EXPR`
   chama `ZF_SEPARAR_EXPRESS`: mesma validação de bloqueio, status do transporte e
   `ZF_VALIDA_SALDO_TRANSF`; sem simulação de UD; portão/zona como hoje.
2. **Registro:** `ZTM_REG_TRANSFERENCIA` com novo parâmetro `I_EXPRESS` → novo campo
   `ZWM_ICENTROS-EXPRESS`. Lotes determinados por `ZSD_ICENTRO_ESTOQ` como no fluxo normal.
3. **Engine:** em `ZWM_ICENTROS`, status `R` com `EXPRESS = X` chama a nova função
   `ZSEPEX_SEPARA_VIRTUAL` (cópia dos passos 8 a 10 de `Z_WM_CONFIRMA_ICENTRO`, sem os
   passos 6 e 7): `L_TO_CREATE_DN` com `IT_DELIT` apontando origem **virtual**
   (tipo `999`, posição `EXPRESS` ou posição = número da remessa; ou novo tipo `9EX`) para
   cada item de lote, e `L_TO_CONFIRM`. Nasce o quant negativo por material/lote na posição
   virtual. Status `S`.
4. **Saída, entrada, lotes nas remessas de venda, faturamento:** sem alteração. O
   encarregado autoriza SAIDA_MERC como hoje.
5. **Controle Express (pacote ZSEPEX):** ao gravar status `S`, a função grava
   `ZSEPEX_T_CAB` (número do processo, transporte, remessa de transferência, grupo) e
   `ZSEPEX_T_ITM` (item de lote: material, lote, quantidade, OT virtual). Status Express
   próprio, independente de `ZWM_ICENTROS`.
6. **Regularização (Z02, `ZSEPEX_R_REGULARIZAR`):** no dia seguinte cria, por item
   pendente, OT de `DIA/DTA/XDC/DII` para a posição virtual (`L_TO_CREATE_SINGLE`,
   movimento 999 ou tipo Z, lote da remessa, estratégia de saída por UD, não confirmada).
   A OT aberta reserva as UDs e aparece em `ZF_FILTRA_LQUA_DISPONIVEL`. O RF confirma por
   número de OT. Job `ZSEPEX_R_SINCRONIZAR` lê `LTAP` e `LQUA` e fecha o item quando o
   negativo da posição virtual zera.
7. **Pendências (Z03):** ALV por carga/remessa/material/lote com idade, e-mail diário,
   versão de fechamento com `LQUA` negativa da posição virtual.
8. **Ajuste de lote:** opção na Z02: lote físico Y no lugar de X → 309 Y→X no DPFE
   (com a mudança de lançamento WM correspondente) e 309 X→Y no centro de faturamento,
   OT de regularização para X.

### 4.3 Riscos específicos descobertos no código

| Risco | Onde | Tratamento proposto |
|---|---|---|
| Após o PGI Express, `ZF_VALIDA_SALDO_TRANSF` deixa de descontar a reserva (filtra `WBSTK <> C` e `KOSTA <> C`), e o saldo físico ainda está nos bins | `ZWMR0010_FORM` 6279 | Descontar também as quantidades pendentes em `ZSEPEX_T_ITM` (status < concluído); mesma regra em `ZF_PREENCHE_SIMULACAO` e no cálculo de disponível do Express |
| Entre o PGI Express e a criação das OTs de regularização, outra carga pode consumir as UDs | janela entre dia 31 e Z02 | Rodar Z02 automaticamente no mesmo job logo após status `S` (criação imediata da OT de regularização, confirmação depois) |
| 999 é o tipo de depósito de diferenças; quants negativos Express se misturam com diferenças reais (LI21/LX23) | `Z_WM_CONFIRMA_ICENTRO` usa `999/SEPARACAO` | Preferir tipo de depósito próprio `9EX` com negativo permitido; se não for possível, posição dedicada em 999 por remessa |
| Estorno após PGI não existe no monitor | `ZF_ESTORNAR_SEPARACAO` só em `R` | Fora do escopo Express; manter processo manual atual (VL09 e NF) |
| `ZFWM_CHECK_DT_GRUPO` compara lotes da remessa de transferência com as remessas de venda | antes da saída | Sem impacto, pois os lotes virtuais são os da LIPS |
| Engine usa `WAIT UP TO` e `COMMIT WORK` por etapa; volume de 1000 t em um dia | `ZWM_ICENTROS` | O Express não acrescenta chamadas de RF; a OT virtual é uma por remessa. Medir em QAS |

### 4.4 Pontos que caem da lista de dúvidas

- P-LOTE: resolvido, `ZSD_ICENTRO_ESTOQ`.
- P-862: 862 saída e 861 entrada, lançados pelo engine; a entrada é imediata no mesmo job.
- P-VT: o PGI é disparado pelo engine após SAIDA_MERC, não pelo VT02N; o VT02N fatura as
  remessas de venda.
- P-HU: embalagem nas remessas de venda, após os lotes; não bloqueia o PGI da transferência.
  Confirmar em QAS.

## 5. Dúvidas restantes antes do desenvolvimento

| ID | Pergunta |
|---|---|
| Q1 | Qual transação RF confirma OT por número hoje (LM05, LM07, Z)? A OT de regularização não terá remessa. |
| Q2 | Na carga fechada atual, como o operador move fisicamente as UDs depois? Só pela pick list? Esse é o problema que o Express resolve? |
| Q3 | Tipos `DIA`, `DTA`, `XDC`, `DII` são todos gerenciados por UD (`LENUM`)? Algum sem UD? |
| Q4 | Posição virtual: criar tipo de depósito `9EX` (customizing) ou usar posição dedicada em `999`? Preferência pelo `9EX`. |
| Q5 | O Express vale também para destino CDII e para os passos CDTR/CFMA, ou só DPFE → BAMO? |
| Q6 | Confirmar em QAS que a remessa de transferência sai sem HU (PGI 862 sem embalagem). |
| Q7 | O ajuste de lote (309 nos dois centros) é aceito pelo fiscal, dado que a NF de transferência fica com o lote original? |

# Separação Express – Especificação técnica revisada (v0.3)

Transferência entre centros a partir do depósito fechado DPFE (WM clássico) para o
centro de faturamento, com saída de mercadoria e NF no último dia do mês e separação
física posterior.

| Item | Valor |
|---|---|
| Versão | 0.3 (revisão do roteiro v0.2 de 01/10/2026) |
| Status | Rascunho para validação com consultor WM antes do desenvolvimento |
| Pacote ABAP | `ZSEPEX` |
| Sintaxe | ABAP 7.40+ |
| Módulos | LE-WM, LE-SHP, MM-IM, SD (faturamento de transferência) |

## 1. Cenário confirmado

| Pergunta | Resposta |
|---|---|
| Sistema | WM clássico (não EWM) |
| Depósito origem | DPFE, 100% WM; 916 e 999 com estoque negativo permitido |
| Documento | Pedido de transferência + remessa de transferência DPFE → centro de faturamento |
| Movimento MM | 862 (tipo Z "SM TF SD/MM"); entrada no destino por 101 contra pedido (WE) |
| Empresa | 1101 para os dois centros; destino sem WM |
| Material | Controlado por lote; EAN; UD (unidade de depósito, SU) na armazenagem; HU na separação |
| Picking | RF (transações LM) |
| Faturamento | Por transporte (VT02N) |
| Volume no fechamento | ~1000 t no último dia; cargas de 5 a 30+ remessas |
| Uso do fluxo | Só no último dia do mês, decidido pelo encarregado ou gestão |
| Prazo separação | Até uma semana; se estourar, separa mesmo assim |
| Divergência de lote/quantidade | Ajuste (sem estorno) |

## 2. Por que o roteiro original não encaixa direto

O roteiro v0.2 (Desenho B) prevê tipo de remessa dedicado sem relevância de picking e
PGI com quant negativo no 916. No cenário confirmado isso traz três problemas:

1. **As remessas do fechamento já existem.** Elas são criadas dias antes, estão em
   transportes (VT) e podem estar parcialmente separadas. Não dá para trocar o tipo de
   remessa de documentos existentes; seria preciso excluir e recriar remessas e
   transportes no dia mais crítico do mês.
2. **RF por remessa deixa de funcionar.** Sem relevância de picking, a OT posterior
   nasce de necessidade de transferência ou documento de material (LT04/LT06), não da
   remessa. O picking por RF passa a ser por OT, HU de separação e lote da remessa
   perdem o vínculo.
3. **Lote.** Com picking desligado, o lote precisa estar na remessa antes do PGI por
   determinação de lote na remessa, que hoje provavelmente ocorre no WM.

## 3. Desenho recomendado (Desenho C: separação virtual)

Ideia: no dia 31 o sistema faz uma **separação virtual** da remessa (OT criada e
confirmada a partir de um tipo de depósito virtual com estoque negativo permitido).
A remessa fica com status de picking completo, o PGI e a NF seguem **exatamente como
hoje** (VT02N). O tipo de depósito virtual acumula quant negativo por remessa. Nos dias
seguintes, OTs de regularização movem o estoque físico dos bins para o tipo virtual,
zerando o negativo. Nenhum lançamento MM adicional, nenhuma mudança em tipo de remessa,
categoria de item, relevância de picking ou interface MM-WM do movimento 862.

### 3.1 Estados do estoque

| Momento | MM (DPFE) | WM DPFE: bins físicos | WM DPFE: tipo virtual (ex. 9EX) | 916 |
|---|---|---|---|---|
| Antes | Q | Q | 0 | 0 |
| Dia 31, após Z01 (OT virtual confirmada) | Q | Q | −Q (bin = nº remessa, lote X) | +Q |
| Dia 31, PGI 862 (processo atual) | 0 | Q | −Q | 0 |
| Dia 1, Z02 cria OT de regularização | 0 | Q (com qtd. de saída em aberto = reserva) | −Q | 0 |
| Confirmação RF da OT de regularização | 0 | 0 | 0 | 0 |

Em todos os momentos, total WM = total MM. LX23 fecha em zero.

### 3.2 Fluxo dia 31

1. Encarregado seleciona as remessas (por transporte ou intervalo) na transação Z01.
2. Z01 valida cada remessa: existe, do DPFE, sem PGI, sem bloqueio, não concluída no WM,
   itens com lote ou com lote determinável, sem registro prévio no controle.
3. Para itens sem lote: Z01 escolhe lote pelo saldo WM disponível (FIFO por data de EM
   dos quants, excluindo quants bloqueados), podendo gerar divisão de lote.
4. Z01 cria a OT da remessa (`L_TO_CREATE_DN`) com origem **manual** no tipo virtual,
   bin dinâmico = número da remessa, lote escolhido, e confirmação imediata.
   O quant negativo nasce no tipo virtual. A remessa fica com picking completo e lote
   gravado nos itens (divisão de lote padrão da confirmação de OT).
5. Z01 grava cabeçalho e itens no controle com status `1 Separação virtual`.
6. PGI e faturamento seguem como hoje pelo transporte (VT02N). Sem programa Z para PGI.
7. Job noturno (Z04 sincronização) lê `LIKP-WBSTK` e grava `DT_PGI`, NF e status
   `2 PGI efetuado`.

### 3.3 Fluxo dias seguintes

1. Z02 (manhã do dia 1, ou sob demanda) cria as OTs de regularização para todos os itens
   com status 2: origem = bins físicos pela estratégia de saída (SU/UD), lote X da
   remessa, quantidade pendente; destino = tipo virtual, bin dinâmico = remessa;
   tipo de movimento WM Z (ex. 9EX "Regularização separação express").
   A OT aberta já **reserva** a quantidade nos bins (quantidade de saída em aberto),
   impedindo que outras remessas consumam o estoque. Isso substitui o Z05 do roteiro.
2. Operador confirma a OT no RF por número de OT (LM05 ou equivalente usado hoje).
   HU de separação: a montagem física da HU segue o processo atual; não há embalagem
   na remessa, pois ela já tem PGI (ver pendência P-HU).
3. Z04 (sincronização, job a cada N minutos ou noturno) lê `LTAP` das OTs de
   regularização, atualiza quantidade regularizada por item, status `3 Em regularização`
   e `4 Concluído` quando o quant negativo do bin da remessa zera.
4. Z03 mostra pendências com idade, destaque acima de 7 dias, versão de fechamento com
   os quants negativos do tipo virtual (`LQUA`) para evidência de auditoria.

### 3.4 Exceções

| Cenário | Tratamento |
|---|---|
| Separação parcial | Confirmação da OT com diferença (padrão, para 999) ou confirmação parcial; Z02 recria OT para o saldo pendente. |
| Lote físico diferente do lote da remessa (ajuste) | Encarregado informa lote Y na Z02. Programa lança no DPFE transferência 309 Y→X (BAPI_GOODSMVT_CREATE) com a OT de mudança de lançamento correspondente, cria OT de regularização para X. No centro de faturamento lança 309 X→Y para alinhar o físico recebido. NF de transferência permanece com lote X; fiscal deve ser informado dessa regra. |
| Material não encontrado | Inventário WM no bin pela rotina padrão, com aprovação. Quant negativo permanece até ajuste. |
| Carga cancelada após PGI e NF | Fora do fluxo Z: estorno pelo processo atual (VL09, cancelamento ou NF de retorno). Z04 detecta estorno do PGI e marca `9 Cancelado`; OT virtual estornada por `LT0G`/estorno de OT. |
| Carga cancelada antes do PGI | Z01 opção "desfazer": estorno da OT virtual (`L_TO_CANCEL` ou retorno ao estoque), remove registro. |
| Pendência acima de 7 dias | Só sinalização no Z03 e e-mail; separação segue. |

## 4. Objetos ABAP (pacote ZSEPEX)

### 4.1 Dicionário

| Objeto | Tipo | Descrição |
|---|---|---|
| `ZSEPEX_T_CAB` | Tabela | Cabeçalho por remessa: `LGNUM`, `VBELN`, `TKNUM`, `WERKS`, `LGORT`, `VBELN_VF`, `DT_SEP_VIRT`, `DT_PGI`, `DT_CONCLUSAO`, `STATUS`, `ERNAM/ERDAT/ERZET`, `AENAM/AEDAT/AEZET` |
| `ZSEPEX_T_ITM` | Tabela | Itens: `VBELN`, `POSNR`, `MATNR`, `CHARG`, `LFIMG`, `MEINS`, `TANUM_VIRT`, `QTD_REGUL`, `STATUS` |
| `ZSEPEX_T_OT` | Tabela | OTs de regularização: `LGNUM`, `TANUM`, `TAPOS`, `VBELN`, `POSNR`, `CHARG`, `VSOLM`, `NISTM`, `STATUS` |
| `ZSEPEX_T_PAR` | Tabela | Parâmetros por `LGNUM`: tipo de depósito virtual, tipo de movimento WM, dias de alerta, destinatários de e-mail |
| `ZSEPEX_D_STATUS` | Domínio | 1 Separação virtual, 2 PGI efetuado, 3 Em regularização, 4 Concluído, 9 Cancelado |
| `ZSEPEX_S_*` | Estruturas | Saídas ALV de Z01, Z02, Z03 |

### 4.2 Programas e transações

| ID | Programa | Transação | Função |
|---|---|---|---|
| Z01 | `ZSEPEX_R_LIBERAR` | `ZSEPEX01` | Seleção, validação, determinação de lote, OT virtual confirmada, gravação do controle. Modo teste. Opção desfazer. |
| Z02 | `ZSEPEX_R_REGULARIZAR` | `ZSEPEX02` | Criação das OTs de regularização por remessa/item; ajuste de lote; recriação de saldo parcial. |
| Z03 | `ZSEPEX_R_PENDENCIAS` | `ZSEPEX03` | ALV de pendências (CL_SALV_TABLE), totais por data e destino, versão de fechamento, envio por e-mail (job). |
| Z04 | `ZSEPEX_R_SINCRONIZAR` | `ZSEPEX04` | Job: atualiza status a partir de `LIKP`, `VBFA`, `LTAP`, `LQUA`. |

### 4.3 Classes

| Classe | Responsabilidade |
|---|---|
| `ZCL_SEPEX_CONTROLE` | Leitura e gravação das tabelas Z, transições de status, bloqueio (`ENQUEUE` objeto `EZSEPEX_CAB`) |
| `ZCL_SEPEX_WM` | Encapsula `L_TO_CREATE_DN`, `L_TO_CREATE_SINGLE`, `L_TO_CONFIRM`, `L_TO_CANCEL`, leitura `LQUA`/`LTAP` |
| `ZCL_SEPEX_LOTE` | Escolha de lote FIFO pelo saldo WM, divisão de lote |
| `ZCL_SEPEX_MM` | Transferências 309 via `BAPI_GOODSMVT_CREATE` para ajuste de lote |
| `ZCL_SEPEX_LOG` | Application log (objeto `ZSEPEX`, SLG1) |
| `ZCL_SEPEX_AUTH` | Verificação do objeto de autorização `ZSEPEX_EXP` (campos `LGNUM`, `ACTVT`) |

### 4.4 Demais

- Classe de mensagens `ZSEPEX`.
- Objeto de log `ZSEPEX` (SLG0).
- Objeto de autorização `ZSEPEX_EXP`: 01 liberar (Z01), 02 regularizar (Z02), 03 exibir (Z03), 85 desfazer.
- Objeto de bloqueio `EZSEPEX_CAB`.
- Variantes e jobs: Z03 diário 06:00 com e-mail; Z04 a cada 30 minutos.
- Repositório em formato abapGit (pasta `src/`), para importação direta no pacote.

## 5. Customizing (consultor WM) e prova de conceito

| # | Item | Validar |
|---|---|---|
| C1 | Tipo de depósito virtual (ex. 9EX) com estoque negativo permitido, sem gestão de UD, fora de todas as sequências de estratégia de saída e entrada | Criação de quant negativo na confirmação de OT com origem manual nesse tipo |
| C2 | Bin dinâmico = número da remessa no tipo virtual | Se não for viável como origem, usar bin fixo por material e controlar remessa só na tabela Z |
| C3 | Tipo de movimento WM Z de regularização (bin → 9EX), com requisito L remessa | Confirmável por RF por número de OT |
| C4 | Processo atual exige embalagem (HU) antes do PGI? Categoria de item com controle de embalagem obrigatório? Depósito HU-managed? | **Se o depósito for HU-managed ou a embalagem for obrigatória, o Desenho C não serve sem HU virtual; ver P-HU** |
| C5 | `L_TO_CREATE_DN` aceita origem manual (tipo/bin/lote) por item via tabela de proposta | Caso contrário usar BDC em LT03 em primeiro plano |
| C6 | Determinação de lote na remessa está ativa? Qual estratégia? | Define se Z01 precisa escolher lote |
| C7 | LX23 e LX24 após ciclo completo | Zero divergência |

Prova de conceito em QAS: C1 a C5 com uma remessa real, antes de qualquer código além do dicionário.

## 6. Pendências de informação

| ID | Pergunta | Impacto |
|---|---|---|
| P-HU | O depósito/centro DPFE usa gestão de HU (HUM) no depósito? A embalagem é obrigatória para o PGI? Como a HU de separação é criada hoje (RF durante a OT, VL02N, ou na expedição)? | Decide se o Desenho C é viável sem criar HU virtual |
| P-LOTE | Hoje o lote entra na remessa na criação (determinação de lote SD) ou só na OT WM? | Escopo da `ZCL_SEPEX_LOTE` |
| P-862 | O 862 foi copiado de 641 (trânsito) ou 647 (uma etapa)? Entrada 101 é feita pelo destino no mesmo dia? | Disponibilidade do estoque no destino no dia 31; fora do escopo Z, mas afeta o resultado esperado |
| P-VT | O PGI é disparado pelo VT02N (status do transporte) ou por VL06G? | Z04 só precisa ler o status; confirmar que nada bloqueia o PGI pós OT virtual |
| P-RF | Qual transação RF é usada hoje (LM03 por remessa, LM05 por OT, outra)? | Treinamento e eventual tela RF Z para a regularização |
| P-FISCAL | Ajuste de lote mantém NF com lote original. Aceitável para fiscal? | Regra do ajuste em Z02 |

## 7. Plano de testes (revisão do roteiro)

| # | Cenário | Resultado esperado |
|---|---|---|
| T1 | Z01 em remessa com lote na remessa | OT virtual confirmada, negativo em 9EX, picking completo, controle status 1 |
| T2 | Z01 em remessa sem lote | Lote FIFO escolhido, divisão de lote gravada na remessa |
| T3 | Z01 em remessa parcialmente separada por RF | OT virtual só para a quantidade em aberto |
| T4 | PGI e NF pelo processo atual após Z01 | Sem mensagem de WM pendente; status 2 após Z04 |
| T5 | Z02 cria OTs de regularização | Quantidade de saída em aberto nos bins; outra remessa não consome o estoque (substitui T7 do roteiro) |
| T6 | Confirmação RF total | 9EX zerado para a remessa, status 4, LX23 zero |
| T7 | Confirmação parcial e recriação de saldo | Status 3, saldo pendente correto |
| T8 | Ajuste de lote Y no lugar de X | 309 nos dois centros, OT de regularização para X, 9EX zerado |
| T9 | Desfazer antes do PGI | OT virtual estornada, sem registro, remessa volta ao status anterior |
| T10 | Estorno de PGI após NF (processo atual) | Z04 marca 9 Cancelado |
| T11 | Volume de fechamento (30 remessas × N itens) | Z01 em LUW por remessa, sem deadlock, tempo dentro da janela |
| T12 | Autorizações | Perfis separados para liberar, regularizar e exibir |

## 8. Fallback: Desenho B do roteiro

Se a prova de conceito C1/C2/C5 falhar, volta-se ao Desenho B (tipo de remessa sem
relevância de picking, negativo em 916, OT por LT06/LT04). Nesse caso o escopo cresce:
recriação das remessas do fechamento, determinação de lote na remessa, interface MM-WM do
movimento 862 (`OMLR`/`T321`), RF por OT sem vínculo à remessa, e o bloqueio de saldo
(Z05) volta a ser necessário.

# Decisões tomadas e pendências abertas

Registro vivo. Cada resposta do negócio ou do consultor entra aqui com a data.

## Decisões (06/10/2026)

| # | Tema | Decisão |
|---|---|---|
| D1 | RF para confirmar OT de regularização | **LM45** (confirmação por número de OT). A OT de regularização não precisa de remessa vinculada. |
| D2 | Carga fechada | O Express substitui a carga fechada. Hoje a movimentação física depois da carga fechada é manual, sem OT. O Express resolve isso com OT de regularização confirmada no RF. |
| D3 | Tipos de depósito de origem | `DIA`, `DTA`, `XDC`, `DII` são todos gerenciados por UD (`LENUM`). A OT de regularização sai por UD inteira ou parcial, pela estratégia de saída. |
| D4 | Posição virtual | **Recomendação: tipo de depósito novo `9EX`** (cópia do 999: estoque negativo permitido, sem UD, sem estratégias, estoque misto permitido), com uma posição fixa `EXPRESS`. Motivo: o 999 é a interface de diferenças; quants negativos do Express no 999 apareceriam na LI21 e poderiam ser lançados como diferença de inventário no MM por engano. Custo: uma entrada de customizing (consultor WM) e uma posição em LS01N. Alternativa sem customizing: posição `EXPRESS` no 999, com restrição de uso da LI21 por procedimento. |
| D5 | Abrangência | DPFE para **qualquer** centro de destino (BAMO, CDII, CDTR, CFMA). O ponto de entrada no engine (`ZWM_ICENTROS`, status `R`) vale para todos os passos que têm remessa no DFC. |
| D6 | HU | A HU existe **só na remessa de transferência**. A remessa de venda recebe o lote automaticamente no fim da transferência e não tem HU. |
| D7 | Quem cria a HU | O RF, na confirmação da OT de picking, a partir da UD lida. As etiquetas de HU já estão impressas e são coladas conforme a necessidade. Pode haver várias HUs na mesma separação. |
| D8 | PGI sem HU | Confirmado pela carga fechada: ela não cria HU e o PGI 862 acontece. Logo o PGI não exige embalagem. Pendência Q-HU2 encerrada. |
| D9 | Para que serve a HU | Conferência de expedição Z (monitor `ZWMR0007`, transação ZWM007, tabelas `ZTWM_CONF_OV_H/U/D`): a conferência de carregamento é por carga (`TKNUM`) e por HU (`EXIDV`), com material, lote e quantidade conferida por item de remessa. Na carga fechada não há HU e a conferência é manual por pick list, pois são cargas de um único material. |

| D10 | RF de picking | LM05 existe no coletor, mas o picking normal com HU usa o RF padrão do depósito. Casos isolados confirmam OT direto no SAP sem HU. Para o Express vale o que for definido aqui. |
| D11 | Conferência de expedição | É obrigatória para faturar, mas a tabela `ZWMT011` cadastra cargas dispensadas (controle manual hoje; a carga fechada já grava). O Express grava a carga na `ZWMT011` no registro, dispensando a conferência na fase 1. |
| D12 | RF `ZWMRF0002` | É a conferência de expedição (transação ZWMRF002). Monta a lista de HUs por `VEKP` com objeto = remessa de transferência do grupo da carga e exige `KOSTK = C` e `LVSTK = C` nas remessas. Com PGI já lançado não aceita conferência para tipo de transporte de transferência. Confirma que a HU só nasce embalada na remessa de transferência antes do PGI. |

| D13 | Armazém Geral | O Express também vale para a carga do depositante (DPFE 1101 → CFMA 1102, retorno ZRTA pela classe `ZCL_ARMAZEM_GERAL`). O controle do pacote ZSEPEX passa a ser por remessa de saída, com a origem como atributo (`05_analise_armazem_geral_express.md`). |

| D14 | Armazém Geral, ponto de desvio | Confirmado (07/10): a ordem ZRTA nasce sem lote, o lote é definido na remessa, a OT sai pelo botão "Criar OT" e a confirmação é no RF. O Express entra no mesmo ponto da classe. A ZRTA tem a mesma pressão de prazo no fechamento. |
| D15 | Conferência de expedição no Express | **Obrigatória.** A `ZWMT011` serve só para liberar o faturamento no dia 31 sem a conferência; a conferência acontece no carregamento, nos dias seguintes, contra os volumes separados na regularização. Substitui a opção C registrada acima. |
| D16 | Identidade do volume no Express | Sem HU SAP: a remessa já tem PGI e não aceita embalagem, e HU sem objeto exige depósito gerenciado por HU. O volume passa a ser a **UD** (etiqueta que o palete já tem) para palete inteiro e a **etiqueta de HU pré-impressa** para quantidade parcial, gravadas na tabela `ZSEPEX_T_VOL` pelo RF de regularização. A conferência (`ZWMRF0002`) lê essa tabela para carga Express. |

## O problema da HU no Express

Hoje a HU nasce na confirmação da OT de picking (RF) e é **embalada na remessa de
transferência**. A conferência de expedição (ZWM007) lê essas HUs por carga. No Express a
ordem se inverte: o PGI 862 da remessa de transferência acontece no dia 31 e a separação
física vem depois. Uma remessa com saída de mercadoria lançada **não aceita mais embalagem**.
Então a HU física criada na regularização não pode ser ligada à remessa de transferência.

Caminhos possíveis, a decidir com a resposta das pendências abaixo:

| Opção | Como | Impacto |
|---|---|---|
| A | A OT de regularização, ao ser confirmada, cria a HU **sem objeto** (HU avulsa com conteúdo material, lote, quantidade) e grava a ligação HU → carga/remessa na tabela `ZSEPEX_T_HU`. A conferência de expedição passa a aceitar HUs ligadas pela tabela Express. | Alteração no RF de confirmação (ou tela RF Z para o Express) e no RF de conferência de expedição. |
| B | Para carga Express, a conferência de expedição usa as UDs lidas na confirmação da OT de regularização (LTAP) em vez de HU. | Alteração só na conferência de expedição; sem HU física. Perde a etiqueta de HU no palete. |
| C | Carga Express sem conferência de expedição, como a carga fechada hoje (pick list). | Sem desenvolvimento no RF. Perde o controle de carregamento, que é justamente o problema da carga fechada. |

## Pendências abertas

| ID | Pergunta | Por que importa |
|---|---|---|
| Q-RF1 | Respondida (D10). | |
| Q-RF2 | Respondida (D12): `ZWMRF0002`, HU por `VEKP/VEPO` da remessa de transferência. | |
| Q-RF3 | Respondida (D11 e D15): obrigatória; `ZWMT011` libera o faturamento, a conferência é feita no carregamento pela opção B (volume por UD ou etiqueta). | |
| Q-LOTE | Regra de ajuste quando a UD do lote X não é encontrada na regularização (ver explicação abaixo). | Define a opção de ajuste da Z02. |

## A pergunta do lote, explicada

No dia 31 o sistema define o lote da remessa de transferência (por exemplo, lote **X**).
Esse lote vai para o PGI 862, para a entrada 861 no centro de faturamento e para a NF de
transferência. Nos dias seguintes a OT de regularização manda o operador buscar UDs do
lote X. Pode acontecer de o lote X não estar fisicamente disponível e o operador separar
lote **Y**.

Nesse caso o sistema fica assim:

| Onde | Livros | Físico |
|---|---|---|
| DPFE | Lote X saiu, lote Y ainda em estoque | Lote Y saiu, lote X ainda em estoque |
| Centro de faturamento | Recebeu lote X | Recebeu lote Y |
| NF de transferência | Lote X | Mercadoria enviada: lote Y |

A correção proposta ("ajuste") é uma transferência de lote a lote (movimento 309) nos dois
centros: no DPFE de Y para X, e no centro de faturamento de X para Y. Isso alinha o estoque
sem estornar PGI nem NF. A NF continua com o lote X. A pergunta é só esta: **o fiscal aceita
que a NF de transferência fique com o lote X enquanto o lote físico enviado foi Y?** Se não
aceitar, a regra passa a ser: o operador não pode trocar o lote, e a Z02 só permite trocar
a UD dentro do mesmo lote.

Observação: como a OT de regularização nomeia a UD e a LM45 exige a leitura dessa UD, a
troca de lote só acontece por decisão do encarregado na Z02, nunca por engano no RF.

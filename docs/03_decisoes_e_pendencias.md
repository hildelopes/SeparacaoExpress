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

## Pendências abertas

| ID | Pergunta | Por que importa |
|---|---|---|
| Q-HU1 | **Como a HU é criada na remessa de transferência hoje?** (a) no RF durante a confirmação da OT (HU de picking a partir da UD lida), (b) pela função `ZTM_EMBALARDT` a partir das UDs das OTs confirmadas, ou (c) manualmente na VL02N? | No Express, no dia 31 não existe OT física nem UD lida. Se a HU for criada a partir das UDs das OTs, a rotina não terá dados. Se for obrigatória para o PGI, o Express precisa criar uma HU "virtual" ou a embalagem precisa ficar opcional. |
| Q-HU2 | O PGI 862 da remessa de transferência exige embalagem completa? (controle de embalagem da categoria de item, ou depósito 1030 gerenciado por HU) | Se exigir, o PGI do dia 31 falha sem HU. |
| Q-HU3 | Na carga fechada atual, quem cria a HU da remessa de transferência, já que não há picking no RF? | Mostra o caminho que o Express pode reaproveitar. |
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

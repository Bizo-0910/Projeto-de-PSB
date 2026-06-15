# Projeto de PSB
Projeto desenvolvido para a disciplina de Programação de Software Básico com o intuito de simular um jogo de _blackjack_ (vinte-e-um) com Arduino.

## Equipe
- Ana Beatriz
- Beatriz Oliveira
- Gabriel Assis
- Nadson Sousa

## Sobre o _Blackjack_
_Blackjack_, às vezes também chamado de vinte-e-um, é um dos mais famosos jogos de carteado em cassinos - e um dos poucos em que há uma chance real de se vencer a banca, através da contagem de cartas -. Seu nome surge da mão mais forte do jogo: um ás e uma carta de valor 10, que, juntas, somam 21 pontos.
### Objetivo
Atingir uma soma de valores de cartas superior à da banca, sem passar de 21.

### Valoração
Cartas numeradas têm o valor escrito nelas; valetes, damas e reis valem 10; o ás vale 11 ou 1, a depender dos valores das demais cartas.

### Estouro
Uma mão de soma superior a 21 é um "estouro" (_bust_) e perde automaticamente.

Regras mais detalhadas estão no documento "Conceitos iniciais"

## Materiais utilizados
1. 1 Arduino UNO;
2. 10 resistores 200ohms;
3. 2 resistores 1kohm;
4. 2 transistores BC337;
5. 40 _jumpers_;
6. 2 _displays_ de sete segmentos;
7. 3 LEDs
8. 4 botões
9. 2 _protoboards_

## Imagens do diagrama
### 1. SimulIDE
<img src=".//blackjack.png" alt="diagrama">

### 2. Tinkercad
<img src=".//tinkercad.png" alt="diagrama">

## Guia de uso
### Inputs

* **Botão 1 (Hit):** Pede mais uma carta.
* **Botão 2 (Stand / Espiar):** Encerra o seu turno. *Dica:* Se você segurar este botão durante o seu turno, o display mostrará temporariamente a carta aberta do Dealer.
* **Botão 3 (Double Down):** Pede apenas mais **uma** carta final e encerra o seu turno automaticamente.
* **Botão 4 (Reset / Surrender):** Desiste da rodada atual ou reinicia o jogo após o Game Over.
* **Display:** Mostra a soma atual da sua mão (ou a do Dealer, dependendo da fase do jogo).

### Estrutura das Rodadas

**1. O Início**
Assim que o Arduino é ligado, a rodada começa automaticamente. O display numérico exibirá o valor inicial da sua mão. O Dealer (a máquina) também já recebeu as cartas dele, mas a pontuação total dele está oculta.

**2. Turno do Jogador**
O objetivo é chegar o mais próximo possível de **21 pontos** sem ultrapassar esse limite.

* Pressione **Hit** para comprar mais cartas. Se a soma das suas cartas passar de 21, você "estoura" (Bust) e perde a rodada instantaneamente.
* *Nota sobre o Ás:* O sistema calcula o valor do Ás (1 ou 11) de forma automática para evitar que você estoure.
* Se estiver satisfeito com a sua pontuação, pressione **Stand** para passar a vez.

**3. Turno do Dealer**
Assim que você pressiona *Stand*, o Arduino assume o controle.

* O display passará a mostrar a pontuação do Dealer.
* A máquina jogará sozinha com base em regras fixas de cassino: ela comprará cartas automaticamente (com pequenos intervalos de suspense) até que a pontuação dela seja **maior ou igual a 17**.
* Se a máquina passar de 21, ela "estoura" e o jogador vence.

**4. Fim de Jogo**
Quando o Dealer finaliza o turno dele, o sistema compara as pontuações e acende um dos LEDs indicadores:

* **1 LED aceso:** Vitória.
* **2 LEDs acesos:** Empate (Push). As pontuações foram iguais.
* **3 LEDs acesos:** Derrota (O Dealer fez mais pontos, ou você estourou durante o seu turno).

**5. Nova Rodada**
Após o fim do jogo, os botões de ação são desativados. Para iniciar uma nova rodada e limpar o placar, pressione o **Botão 4 (Reset)**. Os LEDs se apagarão e uma nova mão será sorteada.
## Funcionamento
### Multiplexação dos Displays

Foram selecionados dois displays de 7 segmentos (Cátodo Comum) que compartilham as mesmas trilhas de dados (pinos `D2` a `D8`). Para que eles mostrem números diferentes sem entrarem em conflito, foi utilizada a multiplexação.

### Controles do Usuário

Os botões de ação estão ligados às portas analógicas (`A0` a `A3`).

* Utilizamos os resistores do microcontrolador para garantir leituras estáveis (quando não apertados, leem `HIGH`; quando apertados e ligados ao GND, leem `LOW`).
* O código possui rotinas de atraso para evitar que o ruído do clique do botão registre múltiplas jogadas acidentalmente.

### 4. Fluxo do Jogo

O laço principal (`LOOP`) aguarda as decisões do jogador e calcula as pontuações:

1. **Sorteio de Cartas:** O programa possui um contador cíclico que roda a enquanto o jogador não aperta nenhum botão. O milissegundo do clique determina a carta sorteada.
2. **Turno do Jogador:** O jogador pode pedir carta (*Hit*), dobrar (*Double*), manter (*Stand*) ou resetar (*Surrender*). O código trata automaticamente a regra do Ás (valendo 1 ou 11 para evitar o estouro de 21 pontos).
3. **Turno do Dealer:** Ao clicar em *Stand*, a máquina assume. Ela revela sua carta oculta e obrigatoriamente compra cartas até atingir um valor mínimo de segurança (17 pontos) ou estourar (Bust).
4. **Fim de Jogo:** As pontuações são comparadas e um dos 3 LEDs de status é acionado via Porta B (`D11` a `D13`): um led para Vitória, dois leds para Empate (Push) e três leds para Derrota. O sistema então trava em estado de *Game Over* até que o botão de Reset seja pressionado para a próxima rodada.

## Uso de interrupções e multiplexação

### O Timer0

Para que os dois displays pareçam acesos ao mesmo tempo, eles precisam piscar alternadamente de maneira muito rápida.

No bloco `INICIAR`, o **Timer0** nativo do ATmega328P é configurado para atuar como o "Event Loop" da renderização:

* O relógio interno do Arduino roda a **16 MHz**.
* Aplicamos um *Prescaler* de **64** no registrador `TCCR0B`.
* O Timer0 é de 8 bits, ou seja, ele "transborda" (Overflow) ao chegar em 255.
* **Frequência da Interrupção:** `16.000.000 Hz / (64 * 256) ≈ 976 Hz`.

Isso significa que, de forma totalmente autônoma, o hardware gera um sinal de alerta ~1000 vezes por segundo, interrompendo qualquer coisa que o laço principal (`LOOP`) esteja fazendo.

### Context Switch

Quando o Overflow acontece, o código salta para o vetor de interrupção `ISR_TIMER0_OVF`. Como essa interrupção congela a lógica do jogo no meio do processamento, a primeira regra é preservar os dados.

O código faz um *Push* de todos os registradores utilizados (`R16`, `R17`, `R18`, `R24`) e do **Registrador de Status (`SREG`)**. Após desenhar na tela, o sistema faz um *Pop* invertido, restaurando a memória para que o jogo continue exatamente de onde parou, sem corrupção de variáveis.

### Interrupção

A cada disparo do Timer0, são executadas as seguintes etapas:

1. **Prevenção de Ghosting:** Antes de trocar os dados, a porta B é manipulada (`ANDI R16, 0b11111001`) para cortar o sinal de ambos os transistores instantaneamente. Isso impede que o número de um display "vaze" visualmente para o outro.
2. **Alternância de Estado:** A flag `mux_flag` sofre uma operação *XOR* (`EOR mux_flag, R17`) para inverter seu valor entre `0` e `1`, decidindo se este ciclo desenhará a Unidade ou a Dezena.
3. **Decodificação na Memória Flash:** O ponteiro `Z` (ZH:ZL) é direcionado para a tabela e utiliza a instrução `LPM` para buscar o mapa binário do dígito exato.
4. **Acionamento Condicional:** Os pinos do `PORTD` (Segmentos A-F) são atualizados. Em seguida, o `PORTB` atualiza o segmento G e emite um pulso `HIGH` para ligar exclusivamente o transistor do display selecionado.

## Circuito Físico
<img src=".//img1.jpg" alt="img">
<img src=".//img2.jpg" alt="img">
<img src=".//img3.jpg" alt="img">
<img src=".//img4.jpg" alt="img">
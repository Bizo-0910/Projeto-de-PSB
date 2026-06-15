.nolist
.include "m328Pdef.inc"
.list

; =========================================================
; MAPEAMENTO DE HARDWARE
; =========================================================
; Entradas: Botões nas Portas Analógicas (Porta C)
.equ BTN_HIT   = PC0  ; Pino A0 - Pedir carta
.equ BTN_STAND = PC1  ; Pino A1 - Parar / Vez do Dealer
.equ BTN_DBL   = PC2  ; Pino A2 - Dobrar a aposta (pede 1 carta e para)
.equ BTN_RESET = PC3  ; Pino A3 - Reiniciar jogo / Desistir

; Saídas de Controle (Porta B - Pinos 13 a 9)
.equ TRANS_DEZ = PB5  ; Pino 13 - Aciona o display das dezenas
.equ TRANS_UNI = PB4  ; Pino 12 - Aciona o display das unidades
.equ LED_3     = PB3  ; Pino 11 - LED de Vitória
.equ LED_2     = PB2  ; Pino 10 - LED de Empate
.equ LED_1     = PB1  ; Pino 9  - LED de Derrota

; Definição de Variáveis nos Registradores
.def rand          = R25 ; Gerador de números (1 a 13)
.def carta         = R22 ; Valor da carta comprada na rodada atual
.def soma          = R16 ; Pontuação total do jogador
.def dealer_upcard = R23 ; Carta visível do Dealer
.def dealer_soma   = R18 ; Pontuação total do Dealer
.def flag_ace_p    = R10 ; Flag que indica se o jogador tem um Ás valendo 11
.def flag_ace_d    = R11 ; Flag que indica se o Dealer tem um Ás valendo 11

; Registradores da ISR (Interrupt Service Routine - Multiplexação)
.def padrao_dez    = R6  ; Guarda os bits do 7-seg para a dezena
.def padrao_uni    = R7  ; Guarda os bits do 7-seg para a unidade
.def flag_mux      = R8  ; Alterna entre 0 e 1 para trocar o display ativo

.org 0x000
    RJMP INICIAR ; Vetor de Reset: Pula para a configuração inicial

.org 0x020                 
    RJMP ISR_TIMER0_OVF  ; Vetor de Interrupção do Timer0 (Ocorre quando o Timer0 transborda) 

; =========================================================
; CONFIGURAÇÃO INICIAL (SETUP)
; =========================================================
.org 0x030
INICIAR:
    ; 1. Configura Porta D (Pinos 0 a 7) como saídas para os segmentos do display
    LDI R17, 0xFF
    OUT DDRD, R17

    ; 2. Configura Porta C (A0 a A3) como entradas para os botões
    LDI R17, 0b00000000
    OUT DDRC, R17
    ; Ativa os resistores de Pull-Up internos da Porta C (Garante nível ALTO quando não pressionado)
    LDI R17, 0b00001111
    OUT PORTC, R17

    ; 3. Configura Porta B (Pinos 13, 12, 11, 10, 9 como saídas)
    LDI R17, 0b00111110
    OUT DDRB, R17
    ; Garante que todos os transistores e LEDs comecem desligados (nível BAIXO)
    LDI R17, 0b00000000
    OUT PORTB, R17

    ; 4. Inicializa variáveis do jogo com zero
    CLR R1
    CLR soma
    MOV flag_ace_p, R1
    MOV flag_ace_d, R1
    MOV flag_mux, R1
    LDI rand, 1 ; Começa o "dado" de cartas em 1

    ; Define a primeira carta do Dealer (fixada em 7 para o início, mas atualizada depois)
    LDI dealer_upcard, 7
    MOV dealer_soma, dealer_upcard

    ; 5. Configura o Timer0 para a Multiplexação dos Displays
    LDI R17, 0x00
    OUT TCCR0A, R17 ; Modo Normal de operação
    LDI R17, 0x03
    OUT TCCR0B, R17 ; Prescaler de 64 (Define a velocidade de transbordo/frequência de atualização)
    LDI R17, 0x01
    STS TIMSK0, R17 ; Habilita a interrupção por transbordo (Overflow) do Timer0
    SEI             ; Habilita interrupções globais (o display começa a piscar aqui)

    ; Prepara o primeiro valor (0) para ser desenhado
    MOV R21, soma
    RCALL ATUALIZA_DISPLAYS

; =========================================================
; LOOP PRINCIPAL DO JOGO
; =========================================================
LOOP:
    ; Fica incrementando a variável 'rand' rapidamente para gerar aleatoriedade
    ; Como o loop roda milhares de vezes por segundo, o clique humano pega um número imprevisível
    INC rand
    CPI rand, 14
    BRNE VERIFICA_BOTOES
    LDI rand, 1 ; Se chegou a 14, volta para 1 (Cartas de 1 a 13)

VERIFICA_BOTOES:
    ; Verifica se algum botão foi pressionado (Nível lógico vai para 0 devido ao Pull-Up)
    SBIS PINC, BTN_HIT
    RJMP LOGICA_HIT

    SBIS PINC, BTN_STAND
    RJMP LOGICA_STAND_ESPIAR

    SBIS PINC, BTN_DBL
    RJMP LOGICA_DOUBLE

    SBIS PINC, BTN_RESET
    RJMP LOGICA_SURRENDER

    RJMP LOOP ; Se nada foi pressionado, continua rodando o dado

; =========================================================
; LÓGICAS DE AÇÃO DOS BOTÕES
; =========================================================

; --- AÇÃO: COMPRAR CARTA (HIT) ---
LOGICA_HIT:
    RCALL ATRASO_DEBOUNCE ; Filtra o ruído mecânico do botão
    MOV carta, rand       ; Pega o número aleatório atual

    CPI carta, 11
    BRLO TRATA_AS_HIT     ; Se a carta for de 1 a 10, checa se é um Ás
    LDI carta, 10         ; Se for 11, 12 ou 13 (Valete, Dama, Rei), vale 10
    RJMP ADICIONA_SOMA_HIT

TRATA_AS_HIT:
    CPI carta, 1
    BRNE ADICIONA_SOMA_HIT ; Se não for Ás (1), apenas soma
    CPI soma, 11
    BRSH ADICIONA_SOMA_HIT ; Se for Ás, mas a soma já for >= 11, o Ás vale 1 para não estourar
    LDI carta, 11          ; Caso contrário, o Ás vale 11
    LDI R17, 1
    MOV flag_ace_p, R17    ; Marca que o jogador tem um Ás flexível valendo 11

ADICIONA_SOMA_HIT:
    ADD soma, carta        ; Adiciona a carta à pontuação
    CPI soma, 22
    BRLO SAFE_HIT          ; Se for 21 ou menos, está salvo

    ; Lógica de Salvação do Ás (Bust Prevention)
    LDI R17, 1
    CP flag_ace_p, R17
    BRNE BUST_TRUE         ; Se não tem um Ás flexível e passou de 21, perdeu (Bust)
    SUBI soma, 10          ; Se tem o Ás, transforma ele de 11 para 1 (subtrai 10)
    MOV flag_ace_p, R1     ; Limpa a flag (já usou a salvação do Ás)
    RJMP SAFE_HIT

BUST_TRUE:
    RJMP GAME_OVER_DERROTA ; Fim de jogo por estourar 21

SAFE_HIT:
    MOV R21, soma
    RCALL ATUALIZA_DISPLAYS ; Atualiza o valor no display

ESPERA_SOLTAR_HIT:
    ; Trava a execução até o jogador soltar o botão para não registrar múltiplos cliques
    SBIS PINC, BTN_HIT
    RJMP ESPERA_SOLTAR_HIT
    RCALL ATRASO_DEBOUNCE
    RJMP LOOP

; --- AÇÃO: DOBRAR (DOUBLE DOWN) ---
; Mesma lógica do HIT, mas força a ida para o STAND (passa a vez) logo após comprar UMA carta.
LOGICA_DOUBLE:
    RCALL ATRASO_DEBOUNCE
    MOV carta, rand

    CPI carta, 11
    BRLO TRATA_AS_DBL
    LDI carta, 10
    RJMP ADICIONA_SOMA_DBL

TRATA_AS_DBL:
    CPI carta, 1
    BRNE ADICIONA_SOMA_DBL
    CPI soma, 11
    BRSH ADICIONA_SOMA_DBL
    LDI carta, 11
    LDI R17, 1
    MOV flag_ace_p, R17

ADICIONA_SOMA_DBL:
    ADD soma, carta
    CPI soma, 22
    BRLO SAFE_DBL

    LDI R17, 1
    CP flag_ace_p, R17
    BRNE DBL_BUST_TRUE
    SUBI soma, 10
    MOV flag_ace_p, R1
    RJMP SAFE_DBL

DBL_BUST_TRUE:
    RJMP GAME_OVER_DERROTA

SAFE_DBL:
    MOV R21, soma
    RCALL ATUALIZA_DISPLAYS

ESPERA_SOLTAR_DBL:
    SBIS PINC, BTN_DBL
    RJMP ESPERA_SOLTAR_DBL
    RCALL ATRASO_DEBOUNCE
    RJMP ACAO_STAND ; << DIFERENÇA AQUI: Vai para a vez do Dealer em vez de voltar para o LOOP

; --- AÇÃO: DESISTIR (SURRENDER) ---
LOGICA_SURRENDER:
    RCALL ATRASO_DEBOUNCE
ESPERA_SOLTAR_SURRENDER:
    SBIS PINC, BTN_RESET
    RJMP ESPERA_SOLTAR_SURRENDER
    RCALL ATRASO_DEBOUNCE
    RJMP GAME_OVER_DERROTA ; Entrega o jogo imediatamente

; --- AÇÃO: PARAR (STAND) E INTELIGÊNCIA DO DEALER ---
LOGICA_STAND_ESPIAR:
    RCALL ATRASO_DEBOUNCE
    RCALL ATRASO_MEDIO

    ; Permite "espiar" a carta do dealer pressionando o botão brevemente, ou passa a vez se segurar.
    SBIC PINC, BTN_STAND
    RJMP ACAO_STAND

LOGICA_ESPIAR:
    MOV R21, dealer_upcard
    RCALL ATUALIZA_DISPLAYS ; Mostra a carta do Dealer no display
ESPERA_SOLTAR_STAND:
    SBIS PINC, BTN_STAND
    RJMP ESPERA_SOLTAR_STAND
    RCALL ATRASO_DEBOUNCE
    MOV R21, soma
    RCALL ATUALIZA_DISPLAYS ; Volta a mostrar a sua pontuação
    RJMP LOOP

ACAO_STAND:
; O turno do jogador acabou. A IA do Dealer assume.
LOOP_IA_DEALER:
    MOV R21, dealer_soma
    RCALL ATUALIZA_DISPLAYS ; Mostra os pontos do Dealer enquanto ele joga
    RCALL ATRASO_LONGO_RAND ; Adiciona um delay dramático simulando a "compra"

    CPI dealer_soma, 17
    BRSH FIM_RODADA         ; Regra de Cassino: Dealer para se tiver 17 ou mais

    ; Dealer compra uma carta
    MOV carta, rand
    CPI carta, 11
    BRLO TRATA_AS_IA
    LDI carta, 10
    RJMP ADD_IA

TRATA_AS_IA:
    ; Tratamento do Ás para o Dealer
    CPI carta, 1
    BRNE ADD_IA
    CPI dealer_soma, 11
    BRSH ADD_IA
    LDI carta, 11
    LDI R17, 1
    MOV flag_ace_d, R17

ADD_IA:
    ADD dealer_soma, carta
    CPI dealer_soma, 22
    BRLO LOOP_IA_DEALER ; Se tiver 21 ou menos, volta para avaliar se tem 17+

    ; Salvação do Ás para o Dealer
    LDI R17, 1
    CP flag_ace_d, R17
    BRNE IA_BUST_TRUE
    SUBI dealer_soma, 10
    MOV flag_ace_d, R1
    RJMP LOOP_IA_DEALER

IA_BUST_TRUE:
    ; Se o Dealer estourou (>21), a rodada acaba (vitória do jogador se não tiver estourado antes)
    RJMP FIM_RODADA

; =========================================================
; VERIFICAÇÃO DE RESULTADOS E RESET
; =========================================================
FIM_RODADA:
    MOV R21, dealer_soma
    RCALL ATUALIZA_DISPLAYS

    CPI dealer_soma, 22
    BRSH GAME_OVER_VITORIA ; Dealer estourou, jogador vence

    ; Compara as somas se ambos sobreviveram
    CP soma, dealer_soma
    BREQ GAME_OVER_EMPATE  ; Empate (Push)
    BRLO GAME_OVER_DERROTA ; Jogador tem menos, Dealer vence
    RJMP GAME_OVER_VITORIA ; Jogador tem mais, Jogador vence

GAME_OVER_VITORIA:
    ; Acende todos os LEDs de status
    SBI PORTB, LED_1
    SBI PORTB, LED_2
    SBI PORTB, LED_3
    RJMP TRAVA_GAME_OVER

GAME_OVER_EMPATE:
    ; Acende os LEDs 1 e 2
    SBI PORTB, LED_1
    SBI PORTB, LED_2
    RJMP TRAVA_GAME_OVER

GAME_OVER_DERROTA:
    ; Acende apenas o LED 1
    SBI PORTB, LED_1
    RJMP TRAVA_GAME_OVER

TRAVA_GAME_OVER:
    ; Loop infinito aguardando o jogador apertar RESET para uma nova partida
    SBIC PINC, BTN_RESET
    RJMP TRAVA_GAME_OVER

    RCALL ATRASO_DEBOUNCE
ESPERA_RESET_SOLTAR:
    SBIS PINC, BTN_RESET
    RJMP ESPERA_RESET_SOLTAR
    RCALL ATRASO_DEBOUNCE

    ; Limpa a rodada (apaga LEDs e zera variáveis)
    CBI PORTB, LED_1
    CBI PORTB, LED_2
    CBI PORTB, LED_3

    CLR soma
    MOV flag_ace_p, R1
    MOV flag_ace_d, R1

    ; Dá uma nova carta inicial para o Dealer
    MOV dealer_upcard, rand
    CPI dealer_upcard, 11
    BRLO TRATA_AS_RESET
    LDI dealer_upcard, 10
    RJMP SET_DEALER_SOMA

TRATA_AS_RESET:
    CPI dealer_upcard, 1
    BRNE SET_DEALER_SOMA
    LDI dealer_upcard, 11
    LDI R17, 1
    MOV flag_ace_d, R17

SET_DEALER_SOMA:
    MOV dealer_soma, dealer_upcard

    MOV R21, soma
    RCALL ATUALIZA_DISPLAYS
    RJMP LOOP

; =========================================================
; DRIVERS DE EXIBIÇÃO REFATORADOS (CONVERSÃO BCD)
; =========================================================
; Converte o número hexadecimal (R21) em dois dígitos (Dezena e Unidade)
ATUALIZA_DISPLAYS:
    CLR R20               ; R20 será o contador de dezenas
DIVIDE_POR_10:
    CPI R21, 10           ; Verifica se o valor é menor que 10
    BRLO FIM_DIVISAO      ; Se for, o que sobrou é a unidade
    SUBI R21, 10          ; Subtrai 10 da unidade
    INC R20               ; Incrementa o contador de dezenas
    RJMP DIVIDE_POR_10    ; Repete até restar menos de 10
FIM_DIVISAO:
    RCALL PREPARA_SEGMENTOS
    RET

; Busca na tabela (TAB_7SEG) os bytes necessários para acender os displays
PREPARA_SEGMENTOS:
    ; Prepara ponteiro Z para buscar a dezena
    LDI ZL, LOW(TAB_7SEG << 1)
    LDI ZH, HIGH(TAB_7SEG << 1)
    ADD ZL, R20
    CLR R1
    ADC ZH, R1
    LPM padrao_dez, Z     ; Carrega o padrão de bits da dezena em padrao_dez

    ; Prepara ponteiro Z para buscar a unidade
    LDI ZL, LOW(TAB_7SEG << 1)
    LDI ZH, HIGH(TAB_7SEG << 1)
    ADD ZL, R21
    ADC ZH, R1
    LPM padrao_uni, Z     ; Carrega o padrão de bits da unidade em padrao_uni
    RET

; =========================================================
; ROTINA DE INTERRUPÇÃO (TIMER0) - MULTIPLEXAÇÃO
; =========================================================
; Esta rotina é chamada automaticamente pelo hardware várias vezes por segundo
ISR_TIMER0_OVF:
    ; Salva o estado atual do programa para não interferir na lógica principal
    PUSH R16               
    IN R16, SREG
    PUSH R16               

    ; ANTI-GHOSTING SEGURO: Desliga ambos os displays temporariamente
    CBI PORTB, TRANS_DEZ
    CBI PORTB, TRANS_UNI

    ; Alterna a flag_mux entre 0 e 1 usando XOR (Ou Exclusivo)
    LDI R16, 1
    EOR flag_mux, R16
    SBRC flag_mux, 0       ; Pula a próxima instrução se o bit 0 for zero
    RJMP MOSTRA_UNIDADE

MOSTRA_DEZENA:
    OUT PORTD, padrao_dez  ; Envia o padrão de segmentos para a Porta D
    SBI PORTB, TRANS_DEZ   ; Liga o transistor das dezenas
    RJMP FIM_ISR

MOSTRA_UNIDADE:
    OUT PORTD, padrao_uni  ; Envia o padrão de segmentos para a Porta D
    SBI PORTB, TRANS_UNI   ; Liga o transistor das unidades

FIM_ISR:
    ; Restaura o estado do programa
    POP R16
    OUT SREG, R16          
    POP R16
    RETI                   ; Retorna da interrupção

; =========================================================
; ROTINAS DE ATRASO (DELAYS BLOQUEANTES)
; =========================================================
; Estes loops aninhados "queimam" ciclos de clock para criar pausas perceptíveis
ATRASO_DEBOUNCE:
    PUSH R17
    PUSH R18
    PUSH R19
    LDI R17, 10
D1: LDI R18, 255
D2: LDI R19, 255
D3: DEC R19
    BRNE D3
    DEC R18
    BRNE D2
    DEC R17
    BRNE D1
    POP R19
    POP R18
    POP R17
    RET

ATRASO_MEDIO:
    PUSH R17
    PUSH R18
    PUSH R19
    LDI R17, 60
M1: LDI R18, 255
M2: LDI R19, 255
M3: DEC R19
    BRNE M3
    DEC R18
    BRNE M2
    DEC R17
    BRNE M1
    POP R19
    POP R18
    POP R17
    RET

ATRASO_LONGO_RAND:
    ; Além de pausar, continua incrementando a seed de aleatoriedade 'rand' 
    ; para o dealer ter cartas imprevísiveis
    PUSH R17
    PUSH R18
    PUSH R19
    LDI R17, 180
L1: LDI R18, 255
L2: LDI R19, 255
L3: INC rand
    CPI rand, 14
    BRNE L3_NEXT
    LDI rand, 1
L3_NEXT:
    DEC R19
    BRNE L3
    DEC R18
    BRNE L2
    DEC R17
    BRNE L1
    POP R19
    POP R18
    POP R17
    RET

; =========================================================
; TABELA DE CONVERSÃO HEX -> 7 SEGMENTOS
; =========================================================
; Tabela Ajustada para Pinos 1 a 7 (Shift Left)
; Mapeamento: Bit1=A(Pino1), Bit2=B(Pino2), Bit3=C(Pino3), Bit4=D(Pino4), Bit5=E(Pino5), Bit6=F(Pino6), Bit7=G(Pino7)
TAB_7SEG: 
    .DB 0x7E, 0x0C, 0xB6, 0x9E, 0xCC, 0xDA, 0xFA, 0x0E, 0xFE, 0xDE

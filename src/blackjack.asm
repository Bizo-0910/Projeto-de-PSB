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

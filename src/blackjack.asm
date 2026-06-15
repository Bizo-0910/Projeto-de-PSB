

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

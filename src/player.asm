    STRUCT player_state_t
flags            BYTE 0
last_int_counter BYTE 0
subseconds_l     BYTE 0
subseconds_h     BYTE 0
seconds_l        BYTE 0
seconds_h        BYTE 0
minutes_l        BYTE 0
minutes_h        BYTE 0
    ENDS

PLAYER_FLAG_TITLE_SET equ 0



player_loop:
    ld de, var_player_state        ;
    ld b, player_state_t           ;
    xor a                          ;
.init_state:
    ld (de), a                     ;
    inc de                         ;
    djnz .init_state               ;
    ld (uart_txbuf_len), a         ;
    call player_reset_chip         ;
    call vis_init                  ;
    call file_get_current_file_name;
    call player_set_filename       ;
    call file_get_current_file_size;
    call player_set_size           ;
    call smf_get_num_tracks        ;
    call player_set_tracks         ;
    call smf_get_ppqn              ;
    call player_set_ppqn           ;
    call smf_get_tempo             ;
    call player_set_tempo          ;
    ld a, (var_int_counter)        ;
    ld (var_player_state.last_int_counter), a ;
.loop:
    call vis_process_frame         ;
    call player_update_timer       ;
    ld hl, var_player_state.last_int_counter ; if (last_int_counter != current_int_counter) - skip halt
    ld a, (var_int_counter)        ; ...
    cp (hl)                        ; ...
    jr nz, 1f                      ; ...
    xor a : out (#fe), a           ;
    halt                           ;
    inc a : out (#fe), a           ;
1:  inc (hl)                       ; increment last_int_counter
    call uart_flush_txbuf          ;
    call input_process             ;
    ld a, (var_input_key)          ;
    cp INPUT_KEY_BACK              ;
    jr z, .end                     ;
    cp INPUT_KEY_ACT               ;
    jr z, .load_next_file          ;
.process_tracks:
    call smf_get_first_track       ;
    jr z, .load_next_file          ;
.process_current_track:
    call smf_process_track         ; A = status, HL = track position, BC = data len
    jp c, .next_track              ; if C == 1 (delayed) then go to the next track
    jp z, .next_track              ; if Z == 1 (no data) then go to the next track
.status_check:
    cp #ff                         ; do not send meta events to midi device
    jp nz, .vis                    ; ...
    call smf_handle_meta           ; ... instead, process it locally. HL = next track position
    jp .process_current_track      ; ...
.vis:
    call vis_process_command       ;
.status_send:
    ld ixh, b : ld ixl, c          ; IX = data len
    call uart_putc_txbuf           ; send status
.data_send:
    ld a, ixh                      ; if len == 0 then go for next status
    or ixl                         ; ...
    jr z, .process_current_track   ; ...
    call file_get_next_byte        ; A = data
    call uart_putc_txbuf           ; send data
    dec ix                         ; len--
    jp .data_send                  ; ...
.next_track:
    call smf_get_next_track        ;
    jr z, .loop                    ;
    jp .process_current_track      ;
.load_next_file:
    ld a, 1                          ;
    ld (var_player_nextfile_flag), a ;
.end:
    call uart_flush_txbuf            ;
    ; jp player_reset_chip           ;


player_reset_chip:
    ld a, #ff                      ; issue reset status
    di : call uart_putc : ei       ; ...
    halt                           ; wait 20ms just for safety
    ld ixl, #b0                    ; set controller message for channels #0..#f
    ld a, ixl                      ;
.loop:
    di : call uart_putc : ei       ;
    ld a, 123                      ; 121 = all controllers off (this message clears all the controller values for this channel, back to their default values)
    di : call uart_putc : ei       ;
    xor a                          ; 0 = value
    di : call uart_putc : ei       ;
    inc ixl                        ;
    ld a, ixl                      ;
    cp #c0                         ;
    jp nz, .loop                   ;
    ret                            ;


; IN  - BC - string len
; IN  - HL - file position
; OUT - AF - garbage
; OUT - B  - garbage
; OUT - DE - garbage
; OUT - HL - garbage
; OUT - IX - garbage
player_set_title:
    ld ix, var_player_state.flags            ; if title already has been set - exit
    bit PLAYER_FLAG_TITLE_SET, (ix)          ; ...
    ret nz                                   ; ...
    set PLAYER_FLAG_TITLE_SET, (ix)          ; ...
    ld ix, var_tmp32                         ;
.check_len:
    ex de, hl                                ; if (len > LAYOUT_TITLE_LEN) len = LAYOUT_TITLE_LEN
    ld hl, LAYOUT_TITLE_LEN                  ; ...
    xor a                                    ; ... reset C flag
    sbc hl, bc                               ; ...
    ex de, hl                                ; ...
    ld b, c                                  ;
    jr z, .loadstring                        ; ... if (len == LAYOUT_TITLE_LEN) goto .loadstring
1:  jp nc, .loadstring                       ; ... if (len <  LAYOUT_TITLE_LEN) goto .loadstring
    ld c, LAYOUT_TITLE_LEN                   ; ... if (len >  LAYOUT_TITLE_LEN)
    ld (ix+LAYOUT_TITLE_LEN-1), udg_ellipsis ; ...
    ld b, LAYOUT_TITLE_LEN-1                 ;
.loadstring:
    push bc                                  ;
    call file_get_next_byte                  ; A = char
    pop bc                                   ;
    ld (ix), a                               ; *var_tmp32++ = A
    inc ix                                   ; ...
    djnz .loadstring                         ; repeat while (--len)
.append_trailing_spaces:
    ld a, LAYOUT_TITLE_LEN                   ; clear trailing characters
    sub c                                    ; ...
    jr z, .printstring                       ; ... check len == LAYOUT_TITLE_LEN
    ld b, a                                  ; ...
    ld a, ' '                                ; ...
1:  ld (ix), a                               ; ...
    inc ix                                   ; ...
    djnz 1b                                  ; repeat while (--len)
.printstring:
    ld b, LAYOUT_TITLE_LEN                   ;
    LD_SCREEN_ADDRESS hl, LAYOUT_TITLE       ;
    ld ix, var_tmp32                         ;
    call print_stringl                       ;
    ret                                      ;


; IN  - A  - tracks value
; OUT - AF - garbage
; OUT - BC - garbage
; OUT - DE - garbage
player_set_tracks:
    push hl                              ;
    LD_SCREEN_ADDRESS hl, LAYOUT_TRACKS  ;
    call print_hex                       ;
    pop hl                               ;
    ret                                  ;

; IN  - BC - ppqn value
; OUT - AF - garbage
; OUT - BC - garbage
; OUT - DE - garbage
player_set_ppqn:
    push hl                              ;
    push bc                              ;
    LD_SCREEN_ADDRESS hl, LAYOUT_PPQN    ;
    ld a, b                              ;
    call print_hex                       ;
    pop bc                               ;
    ld a, c                              ;
    call print_hex                       ;
    pop hl                               ;
    ret                                  ;

; IN - AIX - tempo value
; OUT - AF - garbage
; OUT - BC - garbage
; OUT - DE - garbage
player_set_tempo:
    push hl                              ;
    LD_SCREEN_ADDRESS hl, LAYOUT_TEMPO   ;
    call print_hex                       ;
    ld a, ixh                            ;
    call print_hex                       ;
    ; ld a, ixl                          ; ignore lowest byte
    ; call print_hex                     ;
    pop hl                               ;
    ret                                  ;

; IN  - IX - pointer to string
; OUT - AF - garbage
; OUT - BC - garbage
; OUT - DE - garbage
; OUT - IX - garbage
player_set_filename:
    push hl                                                   ;
    LD_SCREEN_ADDRESS hl, LAYOUT_FILENAME                     ;
    call print_string0                                        ;
.fill_tail_with_spaces:
    ld a, l                                                   ; if (printed_chars < total chars) - fill tail with spaces
    and #1f                                                   ; ... screen address (HL): 010yyyyy yyyxxxxx
    cp (low LAYOUT_FILENAME)+LAYOUT_FILENAME_LEN              ; ...
    jr nc, 1f                                                 ; ...
    ld a, ' '                                                 ; ...
    call print_char                                           ; ...
    inc l                                                     ; ...
    jr .fill_tail_with_spaces                                 ; ...
1:  pop hl                                                    ;
    ret                                                       ;

; IN  - BC - size value
; OUT - AF - garbage
; OUT - BC - garbage
; OUT - DE - garbage
player_set_size:
    push hl                              ;
    push bc                              ;
    LD_SCREEN_ADDRESS hl, LAYOUT_SIZE    ;
    ld a, b                              ;
    call print_hex                       ;
    pop bc                               ;
    ld a, c                              ;
    call print_hex                       ;
    pop hl                               ;
    ret                                  ;


player_update_timer:
    ld a, (var_player_state.subseconds_l)
    inc a ; 50 hz
    cp 5 : jr z, .subseconds_l_roll
        ld (var_player_state.subseconds_l), a
        ret
.subseconds_l_roll:
    xor a
    ld (var_player_state.subseconds_l), a
    LD_SCREEN_ADDRESS hl, LAYOUT_TIME_SUBSECONDS
    ld a, (var_player_state.subseconds_h)
    inc a
    cp 10 : jr z, .subseconds_h_roll
        ld (var_player_state.subseconds_h), a
        add '0'
        jp print_char
.subseconds_h_roll:
    xor a
    ld (var_player_state.subseconds_h), a
    add '0'
    call print_char
    LD_SCREEN_ADDRESS hl, LAYOUT_TIME_SECONDS+1
    ld a, (var_player_state.seconds_l)
    inc a
    cp 10 : jr z, .seconds_l_roll
        ld (var_player_state.seconds_l), a
        add '0'
        jp print_char
.seconds_l_roll:
    xor a
    ld (var_player_state.seconds_l), a
    add '0'
    call print_char
    LD_SCREEN_ADDRESS hl, LAYOUT_TIME_SECONDS+0
    ld a, (var_player_state.seconds_h)
    inc a
    cp 6 : jr z, .seconds_h_roll
        ld (var_player_state.seconds_h), a
        add '0'
        jp print_char
.seconds_h_roll:
    xor a
    ld (var_player_state.seconds_h), a
    add '0'
    call print_char
    LD_SCREEN_ADDRESS hl, LAYOUT_TIME_MINUTES+1
    ld a, (var_player_state.minutes_l)
    inc a
    cp 10 : jr z, .minutes_l_roll
        ld (var_player_state.minutes_l), a
        add '0'
        jp print_char
.minutes_l_roll:
    xor a
    ld (var_player_state.minutes_l), a
    add '0'
    call print_char
    LD_SCREEN_ADDRESS hl, LAYOUT_TIME_MINUTES+0
    ld a, (var_player_state.minutes_h)
    inc a
    cp 10 : jr z, .minutes_h_roll
        ld (var_player_state.minutes_h), a
        add '0'
        jp print_char
.minutes_h_roll:
    xor a
    ld (var_player_state.minutes_h), a
    add '0'
    jp print_char

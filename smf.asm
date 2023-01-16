    STRUCT chunk_header_t
id            DWORD
len           DWORD
    ENDS

    STRUCT chunk_mthd_t
header        chunk_header_t
format        WORD
num_tracks    WORD
division      WORD
    ENDS

    STRUCT chunk_mtrk_t
header        chunk_header_t
data          BLOCK 0
    ENDS

    STRUCT smf_file_t
num_tracks        BYTE
track_pos         WORD
track_pos_end     WORD
last_status       BYTE
ppqn              WORD
tempo             DWORD
tick_duration     WORD
int_acked_counter WORD
    ENDS


default_tempo = 500000     ; defined by MIDI standard



; IN  - HL - position of beginning of file
; OUT -  F - Z = 0 on success, 1 on error
; OUT - HL - position of next byte after end of chunk
; OUT - AF - garbage
; OUT - BC - garbage
smf_parse_file_header:
    call file_get_next_byte : cp 'M' : ret nz ; chunk_header_t.id[0]
    call file_get_next_byte : cp 'T' : ret nz ; chunk_header_t.id[1]
    call file_get_next_byte : cp 'h' : ret nz ; chunk_header_t.id[2]
    call file_get_next_byte : cp 'd' : ret nz ; chunk_header_t.id[3]
    call file_get_next_byte : cp 0   : ret nz ; chunk_header_t.len[0]
    call file_get_next_byte : cp 0   : ret nz ; chunk_header_t.len[1]
    call file_get_next_byte : cp 0   : ret nz ; chunk_header_t.len[2]
    call file_get_next_byte : cp 6   : ret nz ; chunk_header_t.len[3]
    call file_get_next_byte : cp 0   : ret nz ; chunk_mthd_t.format[0]
    call file_get_next_byte : cp 0   : ret nz ; chunk_mthd_t.format[1]
    call file_get_next_byte : cp 0   : ret nz ; chunk_mthd_t.num_tracks[0]
    call file_get_next_byte : ld (var_smf_file.num_tracks), a ; chunk_mthd_t.num_tracks[1]
    call file_get_next_byte : ld (var_smf_file.ppqn+1), a ; chunk_mthd_t.division[0]
    call file_get_next_byte : ld (var_smf_file.ppqn+0), a ; chunk_mthd_t.division[1]
    ret

; IN  - HL - position in file
; OUT -  F - Z = 0 on success, 1 on error
; OUT - HL - position of next byte after end of chunk
; OUT - AF - garbage
; OUT - BC - garbage
smf_parse_track_header:
    call file_get_next_byte : cp 'M' : ret nz ; chunk_header_t.id+0
    call file_get_next_byte : cp 'T' : ret nz ; chunk_header_t.id+1
    call file_get_next_byte : cp 'r' : ret nz ; chunk_header_t.id+2
    call file_get_next_byte : cp 'k' : ret nz ; chunk_header_t.id+3
    call file_get_next_byte : cp 0 : ret nz   ; chunk_header_t.len+0
    call file_get_next_byte : cp 0 : ret nz   ; chunk_header_t.len+1
    call file_get_next_byte : ld b, a         ; chunk_header_t.len+2
    call file_get_next_byte : ld c, a         ; chunk_header_t.len+3
    ld (var_smf_file.track_pos), hl           ; save position to begin of track data
    add hl, bc                                ; save position to end of track data
    ld (var_smf_file.track_pos_end), hl       ; ...
    jr c, .len_overflow                       ; check if track is bigger than file
    xor a                                     ; set Z flag
    ret
.len_overflow:
    or 1                                      ; reset Z flag
    ret

; OUT -  F - Z = 0 on success, 1 on error
; OUT - HL - file position of first track data byte
smf_parse:
    ld bc, (default_tempo>> 0)&0xFFFF : ld (var_smf_file.tempo+0), bc
    ld bc, (default_tempo>>16)&0xFFFF : ld (var_smf_file.tempo+2), bc
    ld hl, 0
    call smf_parse_file_header
    ret nz
    call smf_parse_track_header
    ret nz
    call smf_update_tick_duration
    ld hl, (var_smf_file.track_pos)
    xor a ; reset Z flag
    ret


; IN  - HL - track position
; OUT - BC - int value (limited to 0x3FFF, should be enought)
; OUT - HL - next track position
; OUT - IX - pointer to last data byte
; OUT - AF - garbage
smf_parse_varint:
    call file_get_next_byte   ; A = byte - fvvvvvvV - f - flag, v - value
    ld b, 0                   ;
    ld c, a                   ;
    rlca                      ; if (flag == 0) - no more bytes, exit
    ret nc                    ; ...
    res 7, c                  ; len = ((len & 0x7F) << 7)
    ld b, c                   ; ...
    ld c, 0                   ; ...
    srl b                     ; ... B = 00vvvvvv; Cflag = bit0
    rr c                      ; ... C = V0000000
    call file_get_next_byte   ; A = byte - fvvvvvvv
    rlca                      ;
    jr c, .have_more_bytes    ;
    srl a                     ; A = 0vvvvvvv
    or c                      ; A = Vvvvvvvv, len = len | (byte & 0x7F)
    ld c, a                   ; ...
    ret                       ;
.have_more_bytes:
    ld bc, #3fff              ; set max value 0x3FFF, all other bytes will be skipped
.loop:
    call file_get_next_byte   ; loop until all varint bytes skipped
    rlca                      ; ...
    jr c, .loop               ; ...
    ret                       ;


; IN  - HL - track position
; OUT -  A - status byte
; OUT - BC - data len
; OUT - HL - next track position
; OUT - DE - time delta
; OUT -  F - garbage
; OUT - IX - garbage
smf_get_next_status:
    ex hl, de                                 ; check if end of track reached
    ld hl, (var_smf_file.track_pos_end)       ; ...
    or a                                      ; clear C flag
    sbc hl, de                                ; if (HL==DE) Z=1,C=0; if (HL<DE) Z=0,C=1; if (HL>DE) Z=0,C=0
    ex hl, de                                 ; ...
    jr z, .eof                                ; ...
    jr c, .eof                                ; ...
.parse_time_delta:
    call smf_parse_varint                     ; BC = time delta
    ld d, b : ld e, c                         ; DE = BC
.parse_status_byte:
    call file_get_next_byte                   ; A = byte
    bit 7, a                                  ; if this isn't status byte - reuse last one ("Running Status")
    jr nz, .is_meta_event                     ; ...
    ld a, (var_smf_file.last_status)          ; ...
    dec hl                                    ; ...
.is_meta_event:
    cp #ff                                    ; A == 0xFF?
    jr nz, .is_sysex                          ; ... no
    push de                                   ;
    push hl                                   ; save HL (next track position)
    inc hl                                    ; "FF cc ll... dd..." - cc - command, ll - length, dd - data
    call smf_parse_varint                     ; BC = ll - length of dd, HL = next track position (pointing to dd)
    pop de                                    ; DE = prev track position
    or a                                      ; reset C flag
    sbc hl, de                                ; get length of cc and ll (HL = HL - DE - C flag)
    add hl, bc                                ; sum length of cc/ll and dd
    ld b, h : ld c, l                         ; BC = total data len
    ex hl, de                                 ; restore HL (next track position)
    pop de                                    ;
    ld a, #ff                                 ; restore status byte = 0xFF
    ret
.is_sysex:
    cp #f0                                    ; check 0xF0 <= byte < 0xF8
    jr c, .is_note                            ; ...
    jr z, .is_sysex_yes                       ; ...
    cp #f8                                    ; ...
    jr nc, .eof                               ; ...
.is_sysex_yes:
    push af                                   ;
    call smf_parse_varint                     ;
    pop af                                    ;
    ret                                       ;
.is_note:
    ld (var_smf_file.last_status), a          ;
    ld ixl, a                                 ;
    and #f0                                   ; "sssscccc" - s - status byte, c - channel number
    ld bc, 2                                  ;
    cp #90 : jr nz, 1f         : or ixl : ret ; note on
1:  cp #80 : jr nz, 1f         : or ixl : ret ; note off
1:  cp #a0 : jr nz, 1f         : or ixl : ret ; key after-touch
1:  cp #b0 : jr nz, 1f         : or ixl : ret ; control change
1:  cp #c0 : jr nz, 1f : dec c : or ixl : ret ; program (patch) change
1:  cp #d0 : jr nz, 1f : dec c : or ixl : ret ; channel after-touch (aka "channel pressure")
1:  cp #e0 : jr nz, 1f         : or ixl : ret ; pitch wheel change
.eof:
1:  xor a                                     ; not valid command, set to zero
    ret


; TODO: SMPTE; negative 'division' field value

; OUT - IX - tick duration
; OUT - AF - garbage
; OUT - BC - garbage
; OUT - DE - garbage
; OUT - HL - garbage
smf_update_tick_duration:                     ; tick_duration = tempo / ppqn / machine_constant, where machine_constant = (1000 * int_len_ms / 256)
    ld a, (var_smf_file.tempo+2)              ; ACIX = tempo
    ld c, a                                   ; ...
    xor a                                     ; ... tempo is 24 bit value
    ld ix, (var_smf_file.tempo)               ; ...
    ld de, (var_smf_file.ppqn)                ;
    call div32by16                            ; ACIX = tempo/ppqn
    ld a, (var_int_is_48_8_hz)                ; DE = machine_constant
    or a                                      ; ...
    jr nz, .int_48_8_hz                       ; ...
.int_50_0_hz:
    ld de, 78                                 ; ... 1000 * (1000/50) / 256
    jp 1f                                     ;
.int_48_8_hz:
    ld de, 80                                 ; ... 1000 * (1000/48.8) / 256
1:  xor a                                     ; ACIX = tempo / ppqn / machine_constant
    call div32by16                            ; ...
    or c                                      ; if (ACIX > 0xFFFF) ACIX = 0xFFFF
    jp z, .save                               ; ...
    ld ix, #ffff                              ; ...
.save:
    ld (var_smf_file.tick_duration), ix       ;
    ret                                       ;


; IN  - DE - ticks count
; OUT - F  - C=1 when delay is going on; C=0 when delay is expired
; OUT - A  - garbage
; OUT - BC - garbage
; OUT - DE - garbage
; OUT - HL - garbage
smf_delay:
    ld bc, (var_smf_file.tick_duration)       ; HLDE (wait_duration) = ticks_count * tick_duration
    call mult_de_bc                           ; ...
    ex de, hl                                 ; ...
    ld a, h                                   ; if (wait_duration > 65535) wait_duration = 65535
    or l                                      ; ...
    jr z, 1f                                  ; ...
    ld de, #ffff                              ; ...
1:  ld hl, (var_int_counter)                  ; HL (elapsed_counter) = (current_counter-acked_counter)
    ld bc, (var_smf_file.int_acked_counter)   ; ...
    sbc hl, bc                                ; ...
    sbc hl, de                                ; if (elapsed_counter < wait_duration) { return; } | if (HL==DE) Z=1,C=0; if (HL<DE) Z=0,C=1; if (HL>DE) Z=0,C=0
    ret c                                     ; ...
    ex de, hl                                 ; acked_counter += wait_duration
    add hl, bc                                ; ...
    ld (var_smf_file.int_acked_counter), hl   ; ...
    or a                                      ; reset C flag
    ret                                       ;


; IN  - BC - data len
; IN  - HL - track position
; OUT - HL - next track position
; OUT - AF - garbage
; OUT - BC - garbage
; OUT - DE - garbage
; OUT - IX - garbage
smf_handle_meta:
    ld a, b                      ; if (len == 0) - exit
    or c                         ; ...
    ret z                        ; ...
    call file_get_next_byte      ; A = cmd
    dec bc                       ; ...
.tempo:
    cp #51                       ; tempo
    jr nz, .title                ; ...
    ld a, b                      ; len should == 4
    or a                         ; ...
    jr nz, .exit                 ; ...
    ld a, c                      ; ...
    cp 4                         ; ...
    jr nz, .exit                 ; ...
    inc hl                       ; skip ll
    dec bc                       ; ...
    call file_get_next_byte      ; tempo = tt tt tt
    dec bc                       ; ...
    ld (var_smf_file.tempo+2), a ; ... MIDI is big endian, Z80 is little endian
    call file_get_next_byte      ; ...
    dec bc                       ; ...
    ld (var_smf_file.tempo+1), a ; ...
    call file_get_next_byte      ; ...
    dec bc                       ; ...
    ld (var_smf_file.tempo+0), a ; ...
    push bc                      ;
    push hl                      ;
    call smf_update_tick_duration;
    pop hl                       ;
    pop bc                       ;
    jp .exit                     ;
.title:
    cp #03                       ; track title
    jr nz, .exit                 ; ...
    inc hl                       ; skip ll
    dec bc                       ; ...
    push bc                      ;
    push hl                      ;
    call player_set_title        ;
    pop hl                       ;
    pop bc                       ;
    ; jp .exit                     ;
.exit:
    add hl, bc                   ; next position += remaining data len
    ret                          ;

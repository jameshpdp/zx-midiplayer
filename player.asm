player_loop:
    di
    ld hl, 0
    ld a, #ff                      ; issue reset status
    call uart_putc                 ; ...
.next_status:
    call smf_get_next_status       ; A = status, HL = track position, BC = data len, DE = time delta
    or a                           ; if status = 0 then end
    jr z, .end                     ; ...
    ld ixl, a                      ; save A
    call smf_delay
.status_check:
    ld a, ixl                      ; restore A (status)
    cp #ff                         ; do not send meta events to midi device
    jr nz, .status_send            ; ...
    call smf_handle_meta           ; ... instead, process it locally. HL = next track position
    jr .next_status                ; ...
.status_send:
    ld iyh, b : ld iyl, c          ; IY = data len
    call uart_putc                 ; send status
.data_send:
    ld a, iyh                      ; if len == 0 then go for next status
    or iyl                         ; ...
    jr z, .next_status             ; ...
    call smf_get_next_byte         ; A = data
    call uart_putc                 ; send data
    dec iy                         ; len--
    jr .data_send                  ; ...
.end:
    ld a, #ff                      ; issue reset status
    call uart_putc                 ; ...
    ret


; IN  - BC - string len
; IN  - IX - pointer to string
; OUT - AF - garbage
; OUT - DE - garbage
; OUT - HL - garbage
; OUT - IX - garbage
player_set_title:
    ld a, b                      ; len = min(len, LAYOUT_TITLE_LEN)
    or a                         ; ...
    jr z, 1f                     ; ...
    ld b, LAYOUT_TITLE_LEN       ; ...
    jr 2f                        ; ...
1:  ld a, c                      ; ...
    cp LAYOUT_TITLE_LEN          ; ...
    jr c, 2f                     ; ...
    ld c, LAYOUT_TITLE_LEN       ; ...
2:  ld hl, LAYOUT_TITLE          ; print title
    ld b, c                      ; ...
    call print_stringl           ; ...
    ret

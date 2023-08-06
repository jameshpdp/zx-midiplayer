settings_magic equ "zxmi"

    STRUCT settings_t
magic       DD
output      DB
divmmc      DB
zxmmc       DB
zcontroller DB
extraram    DB
_reserv     BLOCK 256-8, 0
    ENDS


; OUT -  F - Z when ok, NZ when not ok
; OUT - SP[0:sizeof(settings_t)-1] - loaded setting (only when ok)
settings_load0:
    ld de, (var_settings_sector)                              ; error if var_setting_sector == 0
    ld a, d                                                   ; ...
    or e                                                      ; ...
    jr nz, 1f                                                 ; ...
    or 1                                                      ; ... set NZ flag
    ret                                                       ; ...
1:  ld c, trdos_fun_select_drive                              ; select drive A/B/C/D
    ld a, (var_boot_drive)                                    ; ...
    call trdos_exec_fun                                       ; ...
    ret nz                                                    ; ... exit on error
    ld c, trdos_fun_reconfig_floppy                           ; ... init floppy disk parameters
    call trdos_exec_fun                                       ; ...
    ret nz                                                    ; ... exit on error
    pop bc                                                    ; allocate stack
    ld hl, -settings_t                                        ; ...
    add hl, sp                                                ; ...
    ld sp, hl                                                 ; ...
    push bc                                                   ; ...
    ld c, trdos_fun_read_block                                ; read settings
    ld de, (var_settings_sector)                              ; ... src
    ld b, 1                                                   ; ... one sector
    call trdos_exec_fun                                       ; ...
    jp nz, .err                                               ; ... reset settings in case of error
    ld hl, 2                                                  ; compare magic dword
    add hl, sp                                                ; ...
    ld a, (settings_magic >>  0) & 0xff : cpi : jr nz, .err   ; ...
    ld a, (settings_magic >>  8) & 0xff : cpi : jr nz, .err   ; ...
    ld a, (settings_magic >> 16) & 0xff : cpi : jr nz, .err   ; ...
    ld a, (settings_magic >> 24) & 0xff : cpi : jr nz, .err   ; ...
    ret                                                       ;
.err:
    pop de                                                    ; deallocate stack
    ld hl, settings_t                                         ; ...
    add hl, sp                                                ; ...
    ld sp, hl                                                 ; ...
    or 1                                                      ; set NZ flag
    ex de, hl                                                 ;
    jp (hl)                                                   ;


; OUT -  F - Z when ok, NZ when not ok
settings_load:
    call settings_load0                                       ;
    ret nz                                                    ;
    ld hl, 0                                                  ;
    add hl, sp                                                ;
    ld de, var_settings                                       ;
    ld bc, settings_t                                         ;
    ldir                                                      ;
    ld sp, hl                                                 ;
    ret                                                       ;


; OUT -  F - Z when ok, NZ when not ok
settings_save:
    call settings_load0                                       ; check if user didn't changed floppy disk
    ret nz                                                    ; ...
    ld hl, settings_t                                         ; deallocate stack
    add hl, sp                                                ; ...
    ld sp, hl                                                 ; ...
1:  ld hl, var_settings.magic                                 ; set magic dword
    ld (hl), (settings_magic >>  0) & 0xff : inc hl           ; ...
    ld (hl), (settings_magic >>  8) & 0xff : inc hl           ; ...
    ld (hl), (settings_magic >> 16) & 0xff : inc hl           ; ...
    ld (hl), (settings_magic >> 24) & 0xff                    ; ...
1:  ld c, trdos_fun_write_block                               ; write settings
    ld hl, var_settings                                       ; ... src
    ld de, (var_settings_sector)                              ; ... dst
    ld b, 1                                                   ; ... one sector
    jp trdos_exec_fun                                         ; ...


settings_apply:
    ret



settings_menu_ok_cb:
    call settings_apply                                       ;
    ld iy, right_menu                                         ;
    ld (iy+menu_t.generator_fun+0), low  menu_dummy_generator ;
    ld (iy+menu_t.generator_fun+1), high menu_dummy_generator ;
    ld (iy+menu_t.context+0),       low  menu_dummy_callback  ;
    ld (iy+menu_t.context+1),       high menu_dummy_callback  ;
    call menu_init                                            ;
    call menu_draw                                            ;
    jp menu_main_right_toggle                                 ;


settings_menu_save_cb:
    call settings_save               ;
    ld a, LAYOYT_OK_FE               ;
    jr z, 1f                         ;
    ld a, LAYOYT_ERR_FE              ;
1:  out (#fe), a                     ;
    ret                              ;


; IN  - DE - *settings_menuentry_t
settings_menu_val_cb:
    ex de, hl                        ;
    inc hl                           ;
    ld e, (hl)                       ; de = ptr
    inc hl                           ; ...
    ld d, (hl)                       ; ...
    ld a, (de)                       ; a = *ptr
    inc hl                           ;
    add a, a                         ;
    adc a, l                         ;
    ld l, a                          ;
    jr nc, 1f                        ;
    inc h                            ;
1:  ld a, (hl) : ld ixl, a           ;
    inc hl                           ;
    ld a, (hl) : ld ixh, a           ;
    ret                              ;


; IN  - DE - *settings_menuentry_t
settings_menu_cb:
    ex de, hl                        ;
    ld c, (hl)                       ; c = max
    inc hl                           ;
    ld a, (hl)                       ; hl = ptr
    inc hl                           ; ...
    ld h, (hl)                       ; ...
    ld l, a                          ; ...
    ld a, (hl)                       ; a = *ptr
    inc a                            ; a++
    cp c                             ; if (a > max) a = 0
    jr c, 1f                         ; ...
    xor a                            ; ...
1:  ld (hl), a                       ; *ptr = a
    ex de, hl                        ;
    jp menugen_callback_redraw_value ;


settings_menuentry_output:
    DB 2
    DW var_settings.output
    DW str_128.end
    DW str_shama.end
settings_menuentry_divmmc:
    DB 2
    DW var_settings.divmmc
    DW str_off.end
    DW str_on.end
settings_menuentry_zxmmc:
    DB 2
    DW var_settings.zxmmc
    DW str_off.end
    DW str_on.end
settings_menuentry_zcontroller:
    DB 2
    DW var_settings.zcontroller
    DW str_off.end
    DW str_on.end
settings_menuentry_extraram:
    DB 4
    DW var_settings.extraram
    DW str_off.end
    DW str_pentagon.end
    DW str_scorpion.end
    DW str_profi.end

settings_menu_entries:
    menugen_t 7
    menugen_entry_t str_output       settings_menu_val_cb settings_menu_cb settings_menuentry_output
    menugen_entry_t str_divmmc       settings_menu_val_cb settings_menu_cb settings_menuentry_divmmc
    menugen_entry_t str_zxmmc        settings_menu_val_cb settings_menu_cb settings_menuentry_zxmmc
    menugen_entry_t str_zcontroller  settings_menu_val_cb settings_menu_cb settings_menuentry_zcontroller
    menugen_entry_t str_extraram     settings_menu_val_cb settings_menu_cb settings_menuentry_extraram
    menugen_entry_t str_save         0 settings_menu_save_cb
    menugen_entry_t str_ok           0 settings_menu_ok_cb
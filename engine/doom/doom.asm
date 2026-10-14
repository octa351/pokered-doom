; DOOM minigame (main menu entry): a tiny 20-column raycaster using BG tiles for walls,
; OBJs for Pokemon enemies and the gun, and the game's own VBlank/wTileMap/OAM plumbing.
; Tiles/tables come from tools/gen_doom.py, music from engine/doom/doom_music.asm.

INCLUDE "gfx/doom/doom_consts.asm"

; engine variables: offsets into wDoomVars (which overlays wOverworldMap)
DEF DV_PX     EQU 0    ; player x, 8.8 tiles (lo, hi); x/y words stay adjacent: x lo, x hi, y lo, y hi
DEF DV_PY     EQU 2
DEF DV_ANG    EQU 4    ; 0..63
DEF DV_HP     EQU 5
DEF DV_AMMO   EQU 6
DEF DV_COOL   EQU 7
DEF DV_FLASH  EQU 8
DEF DV_HURT   EQU 9
DEF DV_STATE  EQU 10   ; 0 playing, 1 won, 2 lost
DEF DV_TIMER  EQU 11
DEF DV_COL    EQU 12   ; current column
DEF DV_RAYP   EQU 13   ; dw ray table pointer
DEF DV_SLOTS  EQU 15   ; next free OAM slot
DEF DV_TMP    EQU 16   ; enemy loop counter
DEF DV_TMP2   EQU 17   ; contact damage tick
DEF DV_RELX   EQU 18   ; enemy position relative to the player, 1/16 tile
DEF DV_RELY   EQU 19
DEF DV_COS    EQU 20
DEF DV_SIN    EQU 21
DEF DV_PASS   EQU 30   ; enemy OAM pass: 1 near, 0 far
DEF DV_SAVE   EQU 24   ; 6 bytes: LCDC BGP OBP0 OBP1 autoBG updateSprites
DEF DV_COLN   EQU 32   ; 20 bytes: wall steps per column (0 = no wall in range)
DEF DV_E0     EQU 52   ; 4 bytes of sprite-emit scratch
DEF DV_ENEMY  EQU 56   ; 6 enemies x 8 bytes
DEF DE_HP     EQU 4
DEF DE_SPR    EQU 5
DEF DE_DEPTH  EQU 6    ; projected depth in 1/16 tile (0 = not visible)
DEF DE_SX     EQU 7    ; projected screen x
DEF DOOM_NENEMY EQU 6
DEF DOOM_LCDC EQU LCDC_ON | LCDC_BLOCK01 | LCDC_BG_9C00 | LCDC_OBJ_8 | LCDC_OBJ_ON | LCDC_BG_ON

DoomGame::
	ld hl, wDoomVars + DV_SAVE
	ldh a, [rLCDC]
	ld [hli], a
	ldh a, [rBGP]
	ld [hli], a
	ldh a, [rOBP0]
	ld [hli], a
	ldh a, [rOBP1]
	ld [hli], a
	ldh a, [hAutoBGTransferEnabled]
	ld [hli], a
	ld a, [wUpdateSpritesEnabled]
	ld [hl], a
	call DisableLCD
	ld hl, DoomTiles
	ld de, vChars0
	ld bc, DOOM_TILE_COUNT * 16
	call CopyData
	ld a, %11100100
	ldh [rBGP], a
	ldh [rOBP0], a
	ldh [rOBP1], a
	xor a
	ldh [hSCX], a
	ldh [hSCY], a
	call ClearSprites
	ld a, $ff
	ld [wUpdateSpritesEnabled], a ; keeps the overworld sprite code away from our OAM
	ld a, 1
	ldh [hAutoBGTransferEnabled], a
	ld hl, wDoomVars + DV_PX
	xor a
	ld [hli], a
	ld a, DOOM_PLAYER_X
	ld [hli], a
	xor a
	ld [hli], a
	ld a, DOOM_PLAYER_Y
	ld [hli], a
	xor a
	ld [hli], a ; angle
	ld a, 100
	ld [hli], a ; hp
	ld a, 60
	ld [hli], a ; ammo
	xor a
	ld [hli], a ; cool
	ld [hli], a ; flash
	ld [hli], a ; hurt
	ld [hli], a ; state
	ld [hl], a  ; timer
	ld hl, wDoomVars + DV_COLN
	ld b, DOOM_NCOLS
.clrcol
	ld [hli], a
	dec b
	jr nz, .clrcol
	ld hl, wDoomVars + DV_ENEMY
	ld de, DoomEnemyStart
	ld b, DOOM_NENEMY
.spawn
	ld c, 4
.pos
	ld a, [de]
	inc de
	ld [hli], a
	dec c
	jr nz, .pos
	ld a, 3
	ld [hli], a ; hp
	ld a, DOOM_NENEMY
	sub b
	ld [hli], a ; sprite index
	xor a
	ld [hli], a
	ld [hli], a
	dec b
	jr nz, .spawn
	ld a, DOOM_LCDC
	ldh [rLCDC], a
	callfar DoomMusicStart
.loop
	call DelayFrame
	call Joypad
	ldh a, [hJoyPressed]
	and PAD_B | PAD_SELECT
	jr nz, .exit
	call DoomUpdate
	call DoomRender
	ld a, [wDoomVars + DV_STATE]
	and a
	jr z, .loop
	ld hl, wDoomVars + DV_TIMER
	dec [hl]
	jr nz, .loop
	ld a, [wDoomVars + DV_STATE]
	cp 1
	call z, DoomWin
.exit
	callfar DoomMusicStop
	call DisableLCD
	call ClearSprites
	call LoadTextBoxTilePatterns
	call LoadFontTilePatterns
	ld hl, wTileMap
	ld bc, SCREEN_AREA
	ld a, ' '
	call FillMemory
	xor a
	ldh [rBGP], a ; white until the menu has redrawn
	ldh [rOBP0], a
	ldh [rOBP1], a
	ld a, [wDoomVars + DV_SAVE + 4]
	ldh [hAutoBGTransferEnabled], a
	ld a, [wDoomVars + DV_SAVE + 5]
	ld [wUpdateSpritesEnabled], a
	ld a, [wDoomVars + DV_SAVE]
	ldh [rLCDC], a
	ld c, 4
	call DelayFrames
	ld hl, wDoomVars + DV_SAVE + 1
	ld a, [hli]
	ldh [rBGP], a
	ld a, [hli]
	ldh [rOBP0], a
	ld a, [hl]
	ldh [rOBP1], a
	ret

; level cleared: Pokemon victory fanfare + congratulations box (font replaces our tiles; the game is over anyway)
DoomWin:
	callfar DoomMusicStop
	call DisableLCD
	call ClearSprites
	call LoadTextBoxTilePatterns
	call LoadFontTilePatterns
	ld hl, wTileMap
	ld bc, SCREEN_AREA
	ld a, ' '
	call FillMemory
	hlcoord 1, 4
	ld b, 8
	ld c, 16
	call TextBoxBorder
	hlcoord 3, 6
	ld de, DoomWinText
	call PlaceString
	ld a, DOOM_LCDC & ~LCDC_BLOCK01 ; the game's own tile addressing (font/text box tiles)
	ldh [rLCDC], a
	ld a, SFX_STOP_ALL_MUSIC
	ld [wNewSoundID], a
	call PlaySoundWaitForCurrent
	ld c, BANK(Music_DefeatedTrainer)
	ld a, MUSIC_DEFEATED_GYM_LEADER
	call PlayMusic
	ld c, 60
	call DelayFrames
	ld b, 6 ; ~6 s of fanfare, or A/B/Start
.wait
	ld c, 60
.sec
	push bc
	call DelayFrame
	call Joypad
	pop bc
	ldh a, [hJoyPressed]
	and PAD_A | PAD_B | PAD_START
	jr nz, .done
	dec c
	jr nz, .sec
	dec b
	jr nz, .wait
.done
	ld a, SFX_STOP_ALL_MUSIC
	ld [wNewSoundID], a
	jp PlaySound

DoomWinText:
	db   "FELICIDADES!"
	next "HAS COMPLETADO"
	next "EL NIVEL!@"

; ---------------------------------------------------------------- input + logic
DoomUpdate:
	ld a, [wDoomVars + DV_STATE]
	and a
	ret nz
	ldh a, [hJoyHeld]
	ld d, a
	ld a, [wDoomVars + DV_ANG]
	bit B_PAD_LEFT, d
	jr z, .noleft
	dec a
.noleft
	bit B_PAD_RIGHT, d
	jr z, .noright
	inc a
.noright
	and DOOM_NANGLES - 1
	ld [wDoomVars + DV_ANG], a
	ld e, 0 ; movement: 0 none, 1 forward, 2 back
	bit B_PAD_UP, d
	jr z, .noup
	ld e, 1
.noup
	bit B_PAD_DOWN, d
	jr z, .nodown
	ld e, 2
.nodown
	ld a, e
	and a
	jr z, .moved
	ld a, [wDoomVars + DV_ANG]
	ld c, a
	ld b, 0
	ld hl, DoomCos
	add hl, bc
	ld a, [hl]
	call .delta
	ld hl, wDoomVars + DV_PX
	ld b, 0
	push de
	call TryMoveAxis
	pop de
	ld a, [wDoomVars + DV_ANG]
	ld c, a
	ld b, 0
	ld hl, DoomSin
	add hl, bc
	ld a, [hl]
	call .delta
	ld hl, wDoomVars + DV_PX
	ld b, 2
	call TryMoveAxis
.moved
	ld hl, wDoomVars + DV_COOL
	ld a, [hl]
	and a
	jr z, .c0
	dec [hl]
.c0
	inc hl
	ld a, [hl]
	and a
	jr z, .f0
	dec [hl]
.f0
	call DoomEnemies
	ldh a, [hJoyPressed]
	bit B_PAD_A, a
	jr z, .nofire
	ld a, [wDoomVars + DV_COOL]
	and a
	jr nz, .nofire
	ld a, [wDoomVars + DV_AMMO]
	and a
	jr z, .nofire
	dec a
	ld [wDoomVars + DV_AMMO], a
	ld a, 6
	ld [wDoomVars + DV_COOL], a
	ld a, 3
	ld [wDoomVars + DV_FLASH], a
	call DoomShoot
.nofire
	ld hl, wDoomVars + DV_ENEMY + DE_HP
	ld de, 8
	ld b, DOOM_NENEMY
	ld c, 0
.cnt
	ld a, [hl]
	or c
	ld c, a
	add hl, de
	dec b
	jr nz, .cnt
	ld a, c
	and a
	jr nz, .alive
	ld a, 1
	jr .setstate
.alive
	ld a, [wDoomVars + DV_HP]
	and a
	jr z, .lose
	ld a, [wDoomVars + DV_AMMO]
	and a
	ret nz
	ld a, [wDoomVars + DV_COOL]
	ld b, a
	ld a, [wDoomVars + DV_FLASH]
	or b
	ret nz
.lose
	ld a, 2
.setstate
	ld [wDoomVars + DV_STATE], a
	ld a, 40
	ld [wDoomVars + DV_TIMER], a
	ret
.delta ; a = cos/sin (+-64) -> step (+-32), negated when moving backwards (e == 2)
	sra a
	bit 1, e
	ret z
	cpl
	inc a
	ret

; hl = struct (x lo, x hi, y lo, y hi), b = axis offset (0 x / 2 y), a = signed delta (1/256 tile).
; Moves along the axis unless the new cell is a wall.
TryMoveAxis:
	ld e, a
	ld a, l
	ldh [hMultiplyBuffer], a
	ld a, h
	ldh [hMultiplyBuffer + 1], a
	ld a, b
	ldh [hMultiplyBuffer + 2], a
	ld c, b
	ld b, 0
	add hl, bc
	ld a, [hl]
	ldh [hMultiplicand], a
	ld a, e
	add a
	sbc a
	ld d, a ; sign extension
	ld a, [hl]
	add e
	ld [hli], a
	ld a, [hl]
	ldh [hMultiplicand + 1], a
	adc d
	ld [hl], a
	ldh a, [hMultiplyBuffer]
	ld l, a
	ldh a, [hMultiplyBuffer + 1]
	ld h, a
	inc hl
	ld a, [hli] ; x hi
	ld b, a
	inc hl
	ld a, [hl] ; y hi
	swap a
	or b
	ld l, a
	ld h, HIGH(DoomMap)
	ld a, [hl]
	and a
	ret z
	ldh a, [hMultiplyBuffer] ; blocked: undo
	ld l, a
	ldh a, [hMultiplyBuffer + 1]
	ld h, a
	ldh a, [hMultiplyBuffer + 2]
	ld c, a
	ld b, 0
	add hl, bc
	ldh a, [hMultiplicand]
	ld [hli], a
	ldh a, [hMultiplicand + 1]
	ld [hl], a
	ret

; ---------------------------------------------------------------- enemies
; chase the player, hurt them when adjacent, project onto the screen (depth/sx)
DoomEnemies:
	ld hl, wDoomVars + DV_ENEMY
	ld a, DOOM_NENEMY
	ld [wDoomVars + DV_TMP], a
.next
	push hl
	call .one
	pop hl
	ld de, 8
	add hl, de
	ld a, [wDoomVars + DV_TMP]
	dec a
	ld [wDoomVars + DV_TMP], a
	jr nz, .next
	ret

.one ; hl = enemy
	push hl
	ld de, DE_HP
	add hl, de
	ld a, [hl]
	pop hl
	and a
	jr nz, .alive
	ld de, DE_DEPTH
	add hl, de
	xor a
	ld [hl], a
	ret
.alive
	push hl
	ld b, 0
	call .chase
	pop hl
	push hl
	ld b, 2
	call .chase
	pop hl
	push hl
	call .proj
	pop hl
	ld de, DE_DEPTH
	add hl, de
	ld [hli], a
	ld [hl], c
	ret

; hl = enemy -> a = depth (0 = not visible), c = screen x
.proj
	ld a, [hli]
	ld c, a
	ld a, [hli]
	ld b, a ; bc = enemy x
	ld a, [wDoomVars + DV_PX]
	ld e, a
	ld a, [wDoomVars + DV_PX + 1]
	ld d, a
	ld a, c
	sub e
	ld e, a
	ld a, b
	sbc d
	ld d, a
	call .rel8
	jp c, .cull
	ld [wDoomVars + DV_RELX], a
	ld a, [hli]
	ld c, a
	ld a, [hl]
	ld b, a ; bc = enemy y
	ld a, [wDoomVars + DV_PY]
	ld e, a
	ld a, [wDoomVars + DV_PY + 1]
	ld d, a
	ld a, c
	sub e
	ld e, a
	ld a, b
	sbc d
	ld d, a
	call .rel8
	jp c, .cull
	ld [wDoomVars + DV_RELY], a
	; contact damage when |relx| + |rely| < 14
	call .abs
	ld b, a
	ld a, [wDoomVars + DV_RELX]
	call .abs
	add b
	cp 14
	jr nc, .nohit
	ld a, [wDoomVars + DV_TMP2]
	inc a
	ld [wDoomVars + DV_TMP2], a
	and 3
	jr nz, .nohit ; hurt every 4th frame in contact
	ld a, [wDoomVars + DV_HP]
	sub 2
	jr nc, .alive2
	xor a
.alive2
	ld [wDoomVars + DV_HP], a
	ld a, 6
	ld [wDoomVars + DV_HURT], a
.nohit
	ld a, [wDoomVars + DV_ANG]
	ld e, a
	ld d, 0
	ld hl, DoomCos
	add hl, de
	ld a, [hl]
	ld [wDoomVars + DV_COS], a
	ld hl, DoomSin
	add hl, de
	ld a, [hl]
	ld [wDoomVars + DV_SIN], a
	; depth = (relx*cos + rely*sin) >> 6
	ld a, [wDoomVars + DV_RELX]
	ld b, a
	ld a, [wDoomVars + DV_COS]
	ld c, a
	call MulS8
	push hl
	ld a, [wDoomVars + DV_RELY]
	ld b, a
	ld a, [wDoomVars + DV_SIN]
	ld c, a
	call MulS8
	pop de
	add hl, de
	call Sra6
	ld a, h
	and a
	jr nz, .cull
	ld a, l
	cp 4
	jr c, .cull
	cp 128
	jr nc, .cull
	ldh [hDivisor], a
	; lateral = (rely*cos - relx*sin) >> 6
	ld a, [wDoomVars + DV_RELY]
	ld b, a
	ld a, [wDoomVars + DV_COS]
	ld c, a
	call MulS8
	push hl
	ld a, [wDoomVars + DV_RELX]
	ld b, a
	ld a, [wDoomVars + DV_SIN]
	cpl
	inc a
	ld c, a
	call MulS8
	pop de
	add hl, de
	call Sra6
	ld a, h
	ldh [hDividend], a ; sign
	bit 7, h
	jr z, .lpos
	ld a, l
	cpl
	ld l, a
	ld a, h
	cpl
	ld h, a
	inc hl
.lpos
	ld b, 7 ; |lat| * 128 / depth
.shl
	add hl, hl
	dec b
	jr nz, .shl
	ldh a, [hDivisor]
	ld e, a
	call DivU16By8
	ld a, h
	and a
	jr nz, .cull
	ld a, l
	cp 80
	jr nc, .cull
	ld b, a
	ldh a, [hDividend]
	bit 7, a
	ld a, 80
	jr nz, .neg
	add b
	jr .sx
.neg
	sub b
.sx
	ld c, a
	ldh a, [hDivisor]
	ret
.cull
	xor a
	ld c, a
	ret

.abs
	bit 7, a
	ret z
	cpl
	inc a
	ret

; de = signed 8.8 difference -> a = de / 16 (signed byte), or carry set if out of +-8 tiles
.rel8
	ld a, d
	add 8
	cp 16
	jr c, .rin
	scf
	ret
.rin
	ld b, 4
.rs
	sra d
	rr e
	dec b
	jr nz, .rs
	ld a, e
	and a
	ret

; one axis of the chase: hl = enemy, b = axis offset. Steps 7/256 tile toward the player when farther than $40
.chase
	push hl
	push bc
	ld c, b
	ld b, 0
	add hl, bc
	ld a, [hli]
	ld e, a
	ld a, [hl]
	ld d, a ; de = enemy coordinate
	ld hl, wDoomVars + DV_PX
	add hl, bc
	ld a, [hli]
	ld c, a
	ld a, [hl]
	ld b, a ; bc = player coordinate
	ld a, c
	sub e
	ld c, a
	ld a, b
	sbc d
	ld b, a ; bc = player - enemy
	bit 7, b
	jr z, .cpos
	ld a, c
	cpl
	ld c, a
	ld a, b
	cpl
	ld b, a
	inc bc
	ld e, -7
	jr .cmag
.cpos
	ld e, 7
.cmag
	ld a, b
	and a
	jr nz, .cgo
	ld a, c
	cp $40
	jr c, .cstay
.cgo
	pop bc
	pop hl
	ld a, e
	jp TryMoveAxis
.cstay
	pop bc
	pop hl
	ret

; player shot: the nearest visible enemy under the crosshair that isn't hidden by a wall
DoomShoot:
	ld a, [wDoomVars + DV_COLN + 10]
	add a ; wall depth in 1/16 tile
	jr nz, .haswall
	ld a, 250
.haswall
	add 3
	ldh [hDividend + 3], a ; farthest accepted depth
	ld a, 255
	ldh [hDividend], a ; best depth so far
	ld hl, wDoomVars + DV_ENEMY
	ld b, DOOM_NENEMY
.loop
	push hl
	ld de, DE_DEPTH
	add hl, de
	ld a, [hli]
	and a
	jr z, .skip
	ld d, a
	ld a, [hl]
	sub 80
	jr nc, .abs
	cpl
	inc a
.abs
	ld e, a ; |sx - 80|
	ld a, d
	cp 80
	ld a, 12 ; near sprites are wider
	jr c, .tol
	ld a, 8
.tol
	cp e
	jr c, .skip
	jr z, .skip
	ldh a, [hDividend + 3]
	cp d
	jr c, .skip ; wall in front
	ldh a, [hDividend]
	cp d
	jr c, .skip
	jr z, .skip
	ld a, d
	ldh [hDividend], a
	pop hl
	push hl
	ld a, l
	ldh [hMultiplyBuffer], a
	ld a, h
	ldh [hMultiplyBuffer + 1], a
.skip
	pop hl
	ld de, 8
	add hl, de
	dec b
	jr nz, .loop
	ldh a, [hDividend]
	cp 255
	ret z
	ldh a, [hMultiplyBuffer]
	ld l, a
	ldh a, [hMultiplyBuffer + 1]
	ld h, a
	ld de, DE_HP
	add hl, de
	dec [hl]
	ret

; ---------------------------------------------------------------- math
; signed 8x8 -> 16: hl = b * c
MulS8:
	ld a, b
	xor c
	ldh [hMultiplyBuffer + 3], a
	bit 7, b
	jr z, .bp
	xor a
	sub b
	ld b, a
.bp
	bit 7, c
	jr z, .cp
	xor a
	sub c
	ld c, a
.cp
	ld hl, 0
	ld d, 0
	ld e, b
	ld b, 8
.loop
	srl c
	jr nc, .skip
	add hl, de
.skip
	sla e
	rl d
	dec b
	jr nz, .loop
	ldh a, [hMultiplyBuffer + 3]
	bit 7, a
	ret z
	ld a, l
	cpl
	ld l, a
	ld a, h
	cpl
	ld h, a
	inc hl
	ret

Sra6:
	ld b, 6
.l
	sra h
	rr l
	dec b
	jr nz, .l
	ret

; hl = hl / e (e < 128), quotient in hl
DivU16By8:
	xor a
	ld b, 16
.loop
	add hl, hl
	rla
	cp e
	jr c, .skip
	sub e
	inc l
.skip
	dec b
	jr nz, .loop
	ret

; ---------------------------------------------------------------- rendering
DoomRender:
	ld a, [wDoomVars + DV_STATE]
	cp 2
	jr z, .lost
	call DoomWalls
	call DoomOAM
	ld a, [wDoomVars + DV_STATE]
	cp 1
	jr nz, .hud
	ld a, [wDoomVars + DV_TIMER]
	bit 2, a
	jr z, .hud
	jr .blank
.lost
	call ClearSprites
.blank
	ld hl, wTileMap
	ld bc, DOOM_NCOLS * DOOM_VROWS
	ld a, DOOM_T_BLACK
	call FillMemory
.hud
	jp DoomHUD

DoomWalls:
	; ray table pointer for this angle: DoomRays + angle * 40
	ld a, [wDoomVars + DV_ANG]
	ld l, a
	ld h, 0
	add hl, hl
	add hl, hl
	add hl, hl
	ld d, h
	ld e, l
	add hl, hl
	add hl, hl
	add hl, de
	ld de, DoomRays
	add hl, de
	ld a, l
	ld [wDoomVars + DV_RAYP], a
	ld a, h
	ld [wDoomVars + DV_RAYP + 1], a
	xor a
	ld [wDoomVars + DV_COL], a
.col
	ld a, [wDoomVars + DV_RAYP]
	ld l, a
	ld a, [wDoomVars + DV_RAYP + 1]
	ld h, a
	ld a, [hli]
	ldh [hProduct], a
	add a
	sbc a
	ldh [hProduct + 1], a
	ld a, [hli]
	ldh [hProduct + 2], a
	add a
	sbc a
	ldh [hProduct + 3], a
	ld a, l
	ld [wDoomVars + DV_RAYP], a
	ld a, h
	ld [wDoomVars + DV_RAYP + 1], a
	ld a, [wDoomVars + DV_PX]
	ld c, a
	ld a, [wDoomVars + DV_PX + 1]
	ld b, a
	ld a, [wDoomVars + DV_PY]
	ld e, a
	ld a, [wDoomVars + DV_PY + 1]
	ld d, a
	xor a
	ldh [hDividend], a
	ld h, HIGH(DoomMap)
.march ; step the ray 1/8 tile at a time until it enters a wall cell
	ldh a, [hProduct]
	add c
	ld c, a
	ldh a, [hProduct + 1]
	adc b
	ld b, a
	ldh a, [hProduct + 2]
	add e
	ld e, a
	ldh a, [hProduct + 3]
	adc d
	ld d, a
	swap a
	or b
	ld l, a
	ld a, [hl]
	and a
	jr nz, .hit
	ldh a, [hDividend]
	inc a
	ldh [hDividend], a
	cp DOOM_MAXN
	jr nz, .march
	xor a ; no wall within range
	ld c, a
	jr .have
.hit
	ldh a, [hDividend]
	inc a
	ld c, a
	ld a, b
	xor d
	and 1
	ld b, a ; cell parity
.have
	ld a, [wDoomVars + DV_COL]
	ld e, a
	ld d, 0
	ld hl, wDoomVars + DV_COLN
	add hl, de
	ld [hl], c
	; pattern pointer = DoomPat + (parity * 81 + n) * 15
	ld l, c
	ld h, 0
	ld a, c
	and a
	jr z, .noparity
	bit 0, b
	jr z, .noparity
	ld bc, DOOM_MAXN + 1
	add hl, bc
.noparity
	ld b, h
	ld c, l
	add hl, hl
	add hl, hl
	add hl, hl
	add hl, hl
	ld a, l
	sub c
	ld l, a
	ld a, h
	sbc b
	ld h, a
	ld bc, DoomPat
	add hl, bc
	; destination: wTileMap + col, stride 20
	ld a, [wDoomVars + DV_COL]
	add LOW(wTileMap)
	ld e, a
	ld a, HIGH(wTileMap)
	adc 0
	ld d, a
REPT DOOM_VROWS
	ld a, [hli]
	ld [de], a
	ld a, e
	add SCREEN_WIDTH
	ld e, a
	ld a, d
	adc 0
	ld d, a
ENDR
	ld hl, wDoomVars + DV_COL
	inc [hl]
	ld a, [hl]
	cp DOOM_NCOLS
	jp nz, .col
	ret

DoomOAM:
	; gun: 4x4 tiles, slots 0-15
	ld hl, wShadowOAM
	ld a, [wDoomVars + DV_FLASH]
	and a
	ld b, 88 + 16
	jr z, .gunY
	ld b, 84 + 16
.gunY
	ld c, 0 ; tile index
	ld d, 4 ; rows
.grow
	ld e, 4
	ld a, 64 + 8
	ldh [hDividend], a
.gcol
	ld a, b
	ld [hli], a
	ldh a, [hDividend]
	ld [hli], a
	add 8
	ldh [hDividend], a
	ld a, DOOM_T_GUN
	add c
	ld [hli], a
	inc c
	xor a
	ld [hli], a
	dec e
	jr nz, .gcol
	ld a, b
	add 8
	ld b, a
	dec d
	jr nz, .grow
	; muzzle flash: 2x2 tiles, slots 16-19
	ld a, [wDoomVars + DV_FLASH]
	and a
	jr nz, .flash
	ld b, 16
	xor a
.noflash
	ld [hli], a
	dec b
	jr nz, .noflash
	jr .enemies
.flash
	ld b, 70 + 16
	ld c, 0
	ld d, 2
.frow
	ld e, 2
	ld a, 72 + 8
	ldh [hDividend], a
.fcol
	ld a, b
	ld [hli], a
	ldh a, [hDividend]
	ld [hli], a
	add 8
	ldh [hDividend], a
	ld a, DOOM_T_FLASH
	add c
	ld [hli], a
	inc c
	xor a
	ld [hli], a
	dec e
	jr nz, .fcol
	ld a, b
	add 8
	ld b, a
	dec d
	jr nz, .frow
.enemies
	; slots 20-39: near enemies first, then far ones; unused slots hidden
	ld hl, wShadowOAM + 20 * 4
	ld b, 20 * 4
	xor a
.hide
	ld [hli], a
	dec b
	jr nz, .hide
	ld a, 20
	ld [wDoomVars + DV_SLOTS], a
	ld a, 1
	ld [wDoomVars + DV_PASS], a
.pass
	ld hl, wDoomVars + DV_ENEMY
	ld b, DOOM_NENEMY
.each
	push bc
	push hl
	call TryEmit
	pop hl
	pop bc
	ld de, 8
	add hl, de
	dec b
	jr nz, .each
	ld hl, wDoomVars + DV_PASS
	ld a, [hl]
	and a
	ret z
	dec [hl]
	jr .pass

; hl = enemy; emits its OAM tiles when it belongs to the current pass, is not behind a wall and slots remain
TryEmit:
	ld de, DE_SPR
	add hl, de
	ld a, [hli]
	ld b, a ; sprite index
	ld a, [hli]
	ld d, a ; depth
	ld a, [hl]
	ld e, a ; screen x
	ld a, d
	and a
	ret z
	cp 80
	ld c, 1 ; near class
	jr c, .cls
	ld c, 0
.cls
	ld a, [wDoomVars + DV_PASS]
	cp c
	ret nz
	push bc
	push de
	ld a, e
	srl a
	srl a
	srl a
	ld e, a
	ld d, 0
	ld hl, wDoomVars + DV_COLN
	add hl, de
	ld a, [hl]
	pop de
	pop bc
	and a
	jr z, .visible
	add a
	cp d
	ret c ; a wall is nearer than the enemy
.visible
	ld a, c
	add 2
	ld d, a ; dim 2 (far) or 3 (near)
	cp 3
	ld a, 4
	jr nz, .need
	ld a, 9
.need
	ld [wDoomVars + DV_E0 + 3], a
	ld hl, wDoomVars + DV_SLOTS
	add [hl]
	cp 41
	ret nc ; out of OAM slots
	; tile = DOOM_T_ENEMY + sprite * 13 (+ 4 for the near version)
	ld a, b
	add a
	add a
	ld h, a
	add a
	add h
	add b
	add DOOM_T_ENEMY
	bit 0, c
	jr z, .far
	add 4
.far
	ld [wDoomVars + DV_E0], a
	; oam x of the first column = sx - 4*dim + 8
	ld a, d
	add a
	add a
	ld h, a
	ld a, e
	sub h
	add 8
	ld [wDoomVars + DV_E0 + 1], a
	; oam y of the first row = 60 + 16 - 3*dim
	ld a, d
	add a
	add d
	ld h, a
	ld a, 76
	sub h
	ld [wDoomVars + DV_E0 + 2], a
	ld a, [wDoomVars + DV_SLOTS]
	ld l, a
	ld h, 0
	add hl, hl
	add hl, hl
	ld bc, wShadowOAM
	add hl, bc
	ld b, d ; rows
.row
	ld a, [wDoomVars + DV_E0 + 1]
	ld e, a
	ld c, d ; columns
.ecol
	ld a, [wDoomVars + DV_E0 + 2]
	ld [hli], a
	ld a, e
	ld [hli], a
	add 8
	ld e, a
	ld a, [wDoomVars + DV_E0]
	ld [hli], a
	inc a
	ld [wDoomVars + DV_E0], a
	xor a
	ld [hli], a
	dec c
	jr nz, .ecol
	ld a, [wDoomVars + DV_E0 + 2]
	add 8
	ld [wDoomVars + DV_E0 + 2], a
	dec b
	jr nz, .row
	ld a, [wDoomVars + DV_E0 + 3]
	ld hl, wDoomVars + DV_SLOTS
	add [hl]
	ld [hl], a
	ret

DoomHUD:
	ld hl, wTileMap + DOOM_VROWS * SCREEN_WIDTH
	ld bc, 3 * SCREEN_WIDTH
	ld a, DOOM_T_BLACK
	call FillMemory
	; face (3x3) at column 1
	ld a, [wDoomVars + DV_HURT]
	ld b, DOOM_T_FACE
	and a
	jr z, .face
	ld b, DOOM_T_FACE_HURT
	dec a
	ld [wDoomVars + DV_HURT], a
.face
	ld a, [wDoomVars + DV_STATE]
	cp 2
	jr nz, .face2
	ld b, DOOM_T_FACE_HURT
.face2
	ld a, b
	ld hl, wTileMap + DOOM_VROWS * SCREEN_WIDTH + 1
	ld c, 3
.frow
	ld e, 3
.fcol
	ld [hli], a
	inc a
	dec e
	jr nz, .fcol
	ld de, SCREEN_WIDTH - 3
	add hl, de
	dec c
	jr nz, .frow
	; hp digits (columns 5-7, first HUD row)
	ld a, [wDoomVars + DV_HP]
	ld hl, wTileMap + DOOM_VROWS * SCREEN_WIDTH + 5
	ld b, 0
.h100
	cp 100
	jr c, .h100d
	sub 100
	inc b
	jr .h100
.h100d
	push af
	ld a, DOOM_T_DIGIT
	add b
	ld [hli], a
	pop af
	call DrawTwoDigits
	; hp bar: 6 tiles of 8 px at columns 5-10, second HUD row
	ld a, [wDoomVars + DV_HP]
	srl a
	cp 48
	jr c, .bar
	ld a, 48
.bar
	ld c, a
	ld hl, wTileMap + (DOOM_VROWS + 1) * SCREEN_WIDTH + 5
	ld b, 6
.bl
	ld a, c
	cp 8
	jr c, .bpart
	ld a, 8
.bpart
	push af
	add DOOM_T_BAR
	ld [hli], a
	pop af
	ld d, a
	ld a, c
	sub d
	ld c, a
	dec b
	jr nz, .bl
	; ammo: 3 bullet icons (columns 12-14) + two digits
	ld hl, wTileMap + DOOM_VROWS * SCREEN_WIDTH + 12
	ld a, DOOM_T_BULLET
	ld [hli], a
	ld [hli], a
	ld [hli], a
	inc hl
	ld a, [wDoomVars + DV_AMMO]
	; fallthrough

; a = 0..99 -> two digit tiles at hl
DrawTwoDigits:
	ld b, 0
.t
	cp 10
	jr c, .d
	sub 10
	inc b
	jr .t
.d
	push af
	ld a, DOOM_T_DIGIT
	add b
	ld [hli], a
	pop af
	add DOOM_T_DIGIT
	ld [hli], a
	ret

; enemy start positions, 8.8 (x lo, x hi, y lo, y hi)
DoomEnemyStart:
	db $80, 1,  $80, 1
	db $80, 13, $80, 1
	db $80, 7,  $00, 6
	db $00, 3,  $00, 12
	db $00, 12, $00, 12
	db $00, 8,  $00, 13

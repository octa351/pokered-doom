; DOOM minigame music: E1M1 on GB channels, driven from VBlank (home/vblank.asm) at 60 Hz.
; Voice state in wDoomMusicVars: 4 x [ptr lo, ptr hi, wait]. Stream = (value, frames_to_next) pairs.
; values: $FE nop, $FF loop; pulses/bass 0 = off, else MIDI note; drums 1 kick 2 snare 3 tom 4 hat.

MACRO DoomVoiceInit ; \1 state offset, \2 stream
	ld hl, wDoomMusicVars + \1
	ld a, LOW(\2)
	ld [hli], a
	ld a, HIGH(\2)
	ld [hli], a
	ld [hl], 1 ; first tick fires event 0
ENDM

MACRO DoomVoiceStep ; \1 state offset, \2 stream, \3 apply routine (a = value; must keep de)
	ld hl, wDoomMusicVars + \1
	ld a, [hli]
	ld e, a
	ld a, [hli]
	ld d, a
	dec [hl]
	jr nz, .skip\@
	push hl
.event\@
	ld a, [de]
	inc de
	cp $FF
	jr nz, .play\@
	ld de, \2
	jr .event\@
.play\@
	cp $FE
	jr z, .next\@
	call \3
.next\@
	ld a, [de]
	inc de
	pop hl
	ld [hl], a ; wait
	dec hl
	ld [hl], d
	dec hl
	ld [hl], e
.skip\@
ENDM

DoomMusicStart::
	xor a
	ld [wDoomMusicOn], a
	ldh [rNR12], a
	ldh [rNR22], a
	ldh [rNR42], a
	ldh [rNR30], a
	ld a, $80
	ldh [rNR52], a
	ld a, $77
	ldh [rNR50], a
	ld a, $FF
	ldh [rNR51], a
	ld hl, AUD3WAVERAM
	ld de, DoomWave
	ld b, 16
.wave
	ld a, [de]
	inc de
	ld [hli], a
	dec b
	jr nz, .wave
	DoomVoiceInit 0, DoomStreamPulse1
	DoomVoiceInit 3, DoomStreamPulse2
	DoomVoiceInit 6, DoomStreamBass
	DoomVoiceInit 9, DoomStreamDrums
	ld a, 1
	ld [wDoomMusicOn], a
	ret

DoomMusicStop::
	xor a
	ld [wDoomMusicOn], a
	ldh [rNR12], a
	ldh [rNR22], a
	ldh [rNR42], a
	ldh [rNR30], a
	ret

DoomMusicTick::
	DoomVoiceStep 0, DoomStreamPulse1, DoomPlayPulse1
	DoomVoiceStep 3, DoomStreamPulse2, DoomPlayPulse2
	DoomVoiceStep 6, DoomStreamBass, DoomPlayBass
	DoomVoiceStep 9, DoomStreamDrums, DoomPlayDrum
	ret

DoomNoteFreq: ; a = MIDI note 24..96 -> bc = period (c low, b high)
	sub 24
	add a
	ld c, a
	ld b, 0
	ld hl, DoomFreqTable
	add hl, bc
	ld a, [hli]
	ld c, a
	ld b, [hl]
	ret

DoomPlayPulse1:
	and a
	jr z, .off
	call DoomNoteFreq
	ld a, $40 ; 25% duty
	ldh [rNR11], a
	ld a, $F2 ; vol 15, decay
	ldh [rNR12], a
	ld a, c
	ldh [rNR13], a
	ld a, b
	or $80
	ldh [rNR14], a
	ret
.off
	ldh [rNR12], a
	ret

DoomPlayPulse2:
	and a
	jr z, .off
	call DoomNoteFreq
	ld a, $80 ; 50% duty
	ldh [rNR21], a
	ld a, $A2 ; quieter
	ldh [rNR22], a
	ld a, c
	ldh [rNR23], a
	ld a, b
	or $80
	ldh [rNR24], a
	ret
.off
	ldh [rNR22], a
	ret

DoomPlayBass: ; wave channel sounds one octave lower than a pulse at the same period
	and a
	jr z, .off
	add 12
	call DoomNoteFreq
	ld a, $80
	ldh [rNR30], a
	ld a, $20 ; 100% volume
	ldh [rNR32], a
	ld a, c
	ldh [rNR33], a
	ld a, b
	or $80
	ldh [rNR34], a
	ret
.off
	ldh [rNR30], a
	ret

DoomPlayDrum:
	dec a
	add a
	ld c, a
	ld b, 0
	ld hl, DoomDrums
	add hl, bc
	ld a, [hli]
	ldh [rNR42], a
	ld a, [hl]
	ldh [rNR43], a
	ld a, $80
	ldh [rNR44], a
	ret

DoomDrums: ; NR42 envelope, NR43 noise
	db $F1, $A3 ; kick
	db $D1, $53 ; snare
	db $B2, $7A ; tom
	db $81, $29 ; hat

DoomWave: ; 4-bit triangle
	db $01, $23, $45, $67, $89, $AB, $CD, $EF, $FE, $DC, $BA, $98, $76, $54, $32, $10

INCLUDE "gfx/doom/doom_music_data.asm"

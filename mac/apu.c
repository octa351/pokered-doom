// Minimal DMG APU: 2 square (ch1 w/ sweep), wave, noise -> SDL_QueueAudio.
#include "rt.h"
#include <SDL.h>
#include <string.h>
#include <stdio.h>

typedef struct { int en, dac, len, len_en, vol, env_init, env_dir, env_per, env_t, timer, step, freq, duty;
                 int sw_per, sw_dir, sw_shift, sw_t, shadow, sw_en; } Ch;
static Ch c[4];
static u8 nr[0x30], wave[16];
static int seq_clk, seq_step, power = 1, smp_clk, wave_idx, wave_timer, noise_timer, lfsr = 0x7FFF;
static SDL_AudioDeviceID dev;
static short buf[1024 * 2]; static int nbuf;
static const u8 DUTY[4] = {0x01, 0x81, 0x87, 0x7E};
static const u8 RMASK[0x30] = {  // readback OR masks for FF10..FF3F
    0x80,0x3F,0x00,0xFF,0xBF, 0xFF,0x3F,0x00,0xFF,0xBF, 0x7F,0xFF,0x9F,0xFF,0xBF, 0xFF,0xFF,0x00,0x00,0xBF,
    0x00,0x00,0x70, 0xFF,0xFF,0xFF,0xFF,0xFF,0xFF,0xFF,0xFF,0xFF };

void apu_init(void) {
    SDL_AudioSpec w = {.freq = 44100, .format = AUDIO_S16SYS, .channels = 2, .samples = 1024};
    dev = SDL_OpenAudioDevice(NULL, 0, &w, NULL, 0);
    if (dev) SDL_PauseAudioDevice(dev, 0);
}

static int sweep_calc(Ch *x) {
    int d = x->shadow >> x->sw_shift, f = x->sw_dir ? x->shadow - d : x->shadow + d;
    if (f > 2047) x->en = 0;
    return f;
}
static void trigger(int i) {
    Ch *x = &c[i];
    x->en = x->dac;
    if (!x->len) x->len = i == 2 ? 256 : 64;
    x->vol = x->env_init; x->env_t = x->env_per ? x->env_per : 8;
    if (i == 3) { lfsr = 0x7FFF; }
    if (i == 2) wave_idx = 0;
    if (i == 0) {
        x->shadow = x->freq; x->sw_t = x->sw_per ? x->sw_per : 8; x->sw_en = x->sw_per || x->sw_shift;
        if (x->sw_shift) sweep_calc(x);
    }
}
static int period(int i) {
    switch (i) { case 2: return (2048 - c[2].freq) * 2;
    case 3: { int r = nr[0x12] & 7, s = nr[0x12] >> 4; return (r ? r * 16 : 8) << s; }
    default: return (2048 - c[i].freq) * 4; }
}

void apu_write(u16 a, u8 v) {
    int r = a - 0xFF10;
    if (a >= 0xFF30) { wave[a - 0xFF30] = v; return; }
    if (a == 0xFF26) { power = v >> 7; if (!power) { memset(c, 0, sizeof c); memset(nr, 0, sizeof nr); } return; }
    if (!power) return;
    nr[r] = v;
    switch (a) {
    case 0xFF10: c[0].sw_per = v >> 4 & 7; c[0].sw_dir = v >> 3 & 1; c[0].sw_shift = v & 7; break;
    case 0xFF11: c[0].duty = v >> 6; c[0].len = 64 - (v & 63); break;
    case 0xFF16: c[1].duty = v >> 6; c[1].len = 64 - (v & 63); break;
    case 0xFF1B: c[2].len = 256 - v; break;
    case 0xFF20: c[3].len = 64 - (v & 63); break;
    case 0xFF12: case 0xFF17: case 0xFF21: { int i = a == 0xFF12 ? 0 : a == 0xFF17 ? 1 : 3;
        c[i].env_init = v >> 4; c[i].env_dir = v >> 3 & 1; c[i].env_per = v & 7; c[i].dac = (v & 0xF8) != 0; if (!c[i].dac) c[i].en = 0; break; }
    case 0xFF1A: c[2].dac = v >> 7; if (!c[2].dac) c[2].en = 0; break;
    case 0xFF13: c[0].freq = (c[0].freq & 0x700) | v; break;
    case 0xFF18: c[1].freq = (c[1].freq & 0x700) | v; break;
    case 0xFF1D: c[2].freq = (c[2].freq & 0x700) | v; break;
    case 0xFF14: case 0xFF19: case 0xFF1E: case 0xFF23: { int i = a == 0xFF14 ? 0 : a == 0xFF19 ? 1 : a == 0xFF1E ? 2 : 3;
        if (i < 3) c[i].freq = (c[i].freq & 0xFF) | (v & 7) << 8;
        c[i].len_en = v >> 6 & 1; if (v & 0x80) trigger(i); break; }
    }
}
u8 apu_read(u16 a) {
    if (a >= 0xFF30) return wave[a - 0xFF30];
    if (a == 0xFF26) return 0x70 | power << 7 | c[0].en | c[1].en << 1 | c[2].en << 2 | c[3].en << 3;
    return nr[a - 0xFF10] | RMASK[a - 0xFF10];
}

static void seq_tick(void) {
    int s = seq_step++ & 7;
    if (!(s & 1)) for (int i = 0; i < 4; i++) if (c[i].len_en && c[i].len && !--c[i].len) c[i].en = 0;
    if ((s == 2 || s == 6) && c[0].sw_en && c[0].sw_per) {
        Ch *x = &c[0];
        if (!--x->sw_t) { x->sw_t = x->sw_per ? x->sw_per : 8;
            int f = sweep_calc(x);
            if (f <= 2047 && x->sw_shift) { x->shadow = x->freq = f; sweep_calc(x); } }
    }
    if (s == 7) for (int i = 0; i < 4; i++) { Ch *x = &c[i]; if (i == 2 || !x->env_per) continue;
        if (!--x->env_t) { x->env_t = x->env_per; if (x->env_dir && x->vol < 15) x->vol++; else if (!x->env_dir && x->vol > 0) x->vol--; } }
}

static int out(int i) {
    Ch *x = &c[i]; if (!x->en || !x->dac) return 0;
    switch (i) {
    case 0: case 1: return (DUTY[x->duty] >> (7 - (x->step & 7)) & 1) ? x->vol : 0;
    case 2: { int s = wave[wave_idx >> 1]; s = (wave_idx & 1) ? s & 15 : s >> 4; int sh = nr[0x0C] >> 5 & 3; return sh ? s >> (sh - 1) : 0; }
    default: return (lfsr & 1) ? 0 : x->vol;
    }
}

void apu_step(int t) {
    if (!power) return;
    seq_clk += t; while (seq_clk >= 8192) { seq_clk -= 8192; seq_tick(); }
    for (int i = 0; i < 2; i++) { c[i].timer -= t; while (c[i].timer <= 0) { c[i].timer += period(i); c[i].step++; } }
    wave_timer -= t; while (wave_timer <= 0) { wave_timer += period(2); wave_idx = (wave_idx + 1) & 31; }
    noise_timer -= t; while (noise_timer <= 0) { noise_timer += period(3);
        int x = (lfsr ^ lfsr >> 1) & 1; lfsr = lfsr >> 1 | x << 14; if (nr[0x12] & 8) lfsr = (lfsr & ~0x40) | x << 6; }
    smp_clk += t * 44100;
    if (smp_clk >= 4194304) {
        smp_clk -= 4194304;
        int l = 0, r = 0;
        for (int i = 0; i < 4; i++) { int o = out(i); if (nr[0x15] >> (4 + i) & 1) l += o; if (nr[0x15] >> i & 1) r += o; }
        l = l * ((nr[0x14] >> 4 & 7) + 1) * 40; r = r * ((nr[0x14] & 7) + 1) * 40;
        buf[nbuf++] = l; buf[nbuf++] = r;
        if (nbuf >= 1024 * 2) { static FILE *dump; if (!dump && getenv("APU_DUMP")) dump = fopen(getenv("APU_DUMP"), "wb"); if (dump) fwrite(buf, 1, sizeof buf, dump); if (dev && SDL_GetQueuedAudioSize(dev) < 44100 / 5 * 4) SDL_QueueAudio(dev, buf, sizeof buf); nbuf = 0; }
    }
}

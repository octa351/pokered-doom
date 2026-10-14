// Game Boy hardware runtime + SDL2 frontend for the recompiled Pokemon Red.
#include "rt.h"
#include <SDL.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>

extern int (*const run_bank[])(void);
void apu_init(void); void apu_write(u16 a, u8 v); u8 apu_read(u16 a); void apu_step(int t);

u8 A, B, C, D, E, H, L, zf, nf, hf, cf, ime, ime_delay, g_if, g_ie;
u16 SP, pc;
int rom_bank = 1;

static u8 *rom; static size_t rom_size;
static u8 vram[0x2000], wram[0x2000], oam[0xA0], hram[0x80], sram[0x8000], io[0x80];
static int ram_bank, ram_en;
static u8 joy_sel, keys = 0xFF;      // keys: active low, bit0..3 = R,L,U,D ; bit4..7 = A,B,Select,Start
static u8 lcdc = 0x91, stat, scy, scx, ly, lyc, bgp = 0xFC, obp0 = 0xFF, obp1 = 0xFF, wy, wx;
static u8 tima, tma, tac; static u16 div16;
static int line_clk, timer_clk, win_line, stat_prev, serial_clk;
static u32 fb[160 * 144];
static u8 bgpix[160];
static SDL_Window *win; static SDL_Renderer *ren; static SDL_Texture *tex;
const u32 SHADE[4] = {0xFFE0F8D0, 0xFF88C070, 0xFF346856, 0xFF081820};
static const char *SAVE = "pokered.sav";

void fatal_op(int op) { fprintf(stderr, "illegal opcode %02X at pc=%04X bank=%d\n", op, pc, rom_bank); exit(1); }
static void quit(int code);

static void save_ram(void) { FILE *f = fopen(SAVE, "wb"); if (f) { fwrite(sram, 1, sizeof sram, f); fclose(f); } }

// ---- memory ----
u8 rd(u16 a) {
    if (a < 0x4000) return rom[a];
    if (a < 0x8000) return rom[(size_t)rom_bank * 0x4000 + a - 0x4000];
    if (a < 0xA000) return vram[a - 0x8000];
    if (a < 0xC000) return (ram_en && ram_bank < 4) ? sram[ram_bank * 0x2000 + a - 0xA000] : 0xFF;
    if (a < 0xE000) return wram[a - 0xC000];
    if (a < 0xFE00) return wram[a - 0xE000];
    if (a < 0xFEA0) return oam[a - 0xFE00];
    if (a < 0xFF00) return 0xFF;
    if (a < 0xFF80) {
        switch (a) {
        case 0xFF00: { u8 r = 0x0F; if (!(joy_sel & 0x10)) r &= keys & 15; if (!(joy_sel & 0x20)) r &= keys >> 4; return 0xC0 | joy_sel | r; }
        case 0xFF04: return div16 >> 8;
        case 0xFF05: return tima; case 0xFF06: return tma; case 0xFF07: return 0xF8 | tac;
        case 0xFF0F: return 0xE0 | g_if;
        case 0xFF40: return lcdc;
        case 0xFF41: { int m = !(lcdc & 0x80) ? 0 : ly >= 144 ? 1 : line_clk < 80 ? 2 : line_clk < 252 ? 3 : 0;
                       return 0x80 | (stat & 0x78) | ((lcdc & 0x80) && ly == lyc ? 4 : 0) | m; }
        case 0xFF42: return scy; case 0xFF43: return scx; case 0xFF44: return ly; case 0xFF45: return lyc;
        case 0xFF47: return bgp; case 0xFF48: return obp0; case 0xFF49: return obp1;
        case 0xFF4A: return wy; case 0xFF4B: return wx;
        }
        if (a >= 0xFF10 && a < 0xFF40) return apu_read(a);
        return io[a - 0xFF00];
    }
    if (a < 0xFFFF) return hram[a - 0xFF80];
    return g_ie;
}

static void do_dma(u8 hi) { for (int i = 0; i < 0xA0; i++) oam[i] = rd((hi << 8) | i); }

static void lcd_stat_check(void) {
    int m = !(lcdc & 0x80) ? 0 : ly >= 144 ? 1 : line_clk < 80 ? 2 : line_clk < 252 ? 3 : 0;
    int cur = (lcdc & 0x80) && (((stat & 0x40) && ly == lyc) || ((stat & 8) && m == 0) || ((stat & 0x10) && m == 1) || ((stat & 0x20) && m == 2));
    if (cur && !stat_prev) g_if |= 2;
    stat_prev = cur;
}

void wr(u16 a, u8 v) {
    if (a < 0x2000) { int en = (v & 15) == 0x0A; if (ram_en && !en) save_ram(); ram_en = en; return; }
    if (a < 0x4000) { rom_bank = (v & 0x7F) ? (v & 0x7F) : 1; rom_bank %= (rom_size / 0x4000); return; }
    if (a < 0x6000) { ram_bank = v; return; }
    if (a < 0x8000) return;
    if (a < 0xA000) { vram[a - 0x8000] = v; return; }
    if (a < 0xC000) { if (ram_en && ram_bank < 4) sram[ram_bank * 0x2000 + a - 0xA000] = v; return; }
    if (a < 0xE000) { wram[a - 0xC000] = v; return; }
    if (a < 0xFE00) { wram[a - 0xE000] = v; return; }
    if (a < 0xFEA0) { oam[a - 0xFE00] = v; return; }
    if (a < 0xFF00) return;
    if (a < 0xFF80) {
        switch (a) {
        case 0xFF00: joy_sel = v & 0x30; return;
        case 0xFF02: io[2] = v; if ((v & 0x81) == 0x81) serial_clk = 4096; return;
        case 0xFF04: div16 = 0; return;
        case 0xFF05: tima = v; return; case 0xFF06: tma = v; return; case 0xFF07: tac = v & 7; return;
        case 0xFF0F: g_if = v & 31; return;
        case 0xFF40: if ((lcdc ^ v) & 0x80) { ly = 0; line_clk = 0; win_line = 0; } lcdc = v; return;
        case 0xFF41: stat = v & 0x78; lcd_stat_check(); return;
        case 0xFF42: scy = v; return; case 0xFF43: scx = v; return; case 0xFF44: return;
        case 0xFF45: lyc = v; lcd_stat_check(); return;
        case 0xFF46: do_dma(v); return;
        case 0xFF47: bgp = v; return; case 0xFF48: obp0 = v; return; case 0xFF49: obp1 = v; return;
        case 0xFF4A: wy = v; return; case 0xFF4B: wx = v; return;
        }
        if (a >= 0xFF10 && a < 0xFF40) { apu_write(a, v); return; }
        io[a - 0xFF00] = v; return;
    }
    if (a < 0xFFFF) { hram[a - 0xFF80] = v; return; }
    g_ie = v;
}

// ---- PPU ----
static u8 tile_px(int tile_addr, int x, int y) {   // 2bpp pixel from vram offset
    u8 lo = vram[tile_addr + y * 2], hi = vram[tile_addr + y * 2 + 1];
    return ((hi >> (7 - x)) & 1) << 1 | ((lo >> (7 - x)) & 1);
}
static void render_line(void) {
    u32 *row = fb + ly * 160;
    if (!(lcdc & 0x80)) return;
    int win_on = (lcdc & 0x20) && ly >= wy && wx < 167, win_used = 0;
    for (int x = 0; x < 160; x++) {
        u8 c = 0; int bg_en = lcdc & 1;
        if (bg_en) {
            int mapbase, px, py;
            if (win_on && x >= wx - 7) { mapbase = (lcdc & 0x40) ? 0x1C00 : 0x1800; px = x - (wx - 7); py = win_line; win_used = 1; }
            else { mapbase = (lcdc & 8) ? 0x1C00 : 0x1800; px = (x + scx) & 255; py = (ly + scy) & 255; }
            int t = vram[mapbase + (py >> 3) * 32 + (px >> 3)];
            int ta = (lcdc & 0x10) ? t * 16 : 0x1000 + (int8_t)t * 16;
            c = tile_px(ta, px & 7, py & 7);
        }
        bgpix[x] = c;
        row[x] = SHADE[bgp >> (c * 2) & 3];
    }
    if (win_used) win_line++;
    if (lcdc & 2) {
        int h = (lcdc & 4) ? 16 : 8, n = 0, idx[10];
        for (int i = 0; i < 40 && n < 10; i++) { int sy = oam[i * 4] - 16; if (ly >= sy && ly < sy + h) idx[n++] = i; }
        // lower x wins, then lower index: draw in reverse priority order
        for (int a = 0; a < n; a++) for (int b = a + 1; b < n; b++)
            if (oam[idx[b] * 4 + 1] > oam[idx[a] * 4 + 1] || (oam[idx[b] * 4 + 1] == oam[idx[a] * 4 + 1] && idx[b] < idx[a])) { int t = idx[a]; idx[a] = idx[b]; idx[b] = t; }
        for (int k = 0; k < n; k++) {
            u8 *o = oam + idx[k] * 4; int sy = o[0] - 16, sx = o[1] - 8, t = o[2], fl = o[3];
            int py = ly - sy; if (fl & 0x40) py = h - 1 - py;
            if (h == 16) t &= 0xFE;
            u8 pal = (fl & 0x10) ? obp1 : obp0;
            for (int px = 0; px < 8; px++) {
                int x = sx + px; if (x < 0 || x >= 160) continue;
                u8 c = tile_px((t + (py >> 3)) * 16, (fl & 0x20) ? 7 - px : px, py & 7);
                if (!c || ((fl & 0x80) && bgpix[x])) continue;
                row[x] = SHADE[pal >> (c * 2) & 3];
            }
        }
    }
}

static void present(void) {
    static Uint64 next; Uint64 f = SDL_GetPerformanceFrequency(), now = SDL_GetPerformanceCounter();
    SDL_UpdateTexture(tex, NULL, fb, 160 * 4); SDL_RenderClear(ren); SDL_RenderCopy(ren, tex, NULL, NULL); SDL_RenderPresent(ren);
    static int frame; frame++;
    if (getenv("QUIT_FRAME") && frame >= atoi(getenv("QUIT_FRAME"))) quit(0);
    const char *d = getenv("DUMP_FRAMES");   // e.g. "300,600": writes frame_<n>.bmp
    for (; d && *d; d = strchr(d, ',') ? strchr(d, ',') + 1 : NULL)
        if (atoi(d) == frame) { char nm[32]; sprintf(nm, "frame_%d.bmp", frame); SDL_Surface *s = SDL_CreateRGBSurfaceFrom(fb, 160, 144, 32, 640, 0xFF0000, 0xFF00, 0xFF, 0xFF000000); SDL_SaveBMP(s, nm); fprintf(stderr, "dumped %d\n", frame); }
    if (getenv("DUMP_MEM") && atoi(getenv("DUMP_MEM")) == frame) { FILE *m = fopen("mem.bin", "wb"); fwrite(wram, 1, sizeof wram, m); fwrite(vram, 1, sizeof vram, m); fwrite(oam, 1, sizeof oam, m); fwrite(hram, 1, sizeof hram, m); fclose(m); }
    const char *ks = getenv("KEYSCRIPT");    // e.g. "600:START:5,700:DOWN:3" (frame:key:frames), test automation
    if (ks) {
        static const char *N[8] = {"RIGHT", "LEFT", "UP", "DOWN", "A", "B", "SELECT", "START"};
        u8 m = 0xFF; char b[2048]; strncpy(b, ks, sizeof b - 1); b[sizeof b - 1] = 0;
        for (char *t = strtok(b, ","); t; t = strtok(NULL, ",")) {
            int f0, n; char nm[16];
            if (sscanf(t, "%d:%15[A-Z]:%d", &f0, nm, &n) == 3 && frame >= f0 && frame < f0 + n)
                for (int i = 0; i < 8; i++) if (!strcmp(nm, N[i])) m &= ~(1 << i);
        }
        keys = m;
    }
    SDL_Event e;
    while (SDL_PollEvent(&e)) {
        if (e.type == SDL_QUIT) quit(0);
        if (e.type == SDL_KEYDOWN || e.type == SDL_KEYUP) {
            int bit = -1;
            switch (e.key.keysym.sym) {
            case SDLK_RIGHT: bit = 0; break; case SDLK_LEFT: bit = 1; break; case SDLK_UP: bit = 2; break; case SDLK_DOWN: bit = 3; break;
            case SDLK_z: bit = 4; break; case SDLK_x: bit = 5; break;
            case SDLK_RSHIFT: case SDLK_BACKSPACE: bit = 6; break; case SDLK_RETURN: bit = 7; break;
            case SDLK_ESCAPE: quit(0);
            }
            if (bit >= 0) { if (e.type == SDL_KEYDOWN) keys &= ~(1 << bit); else keys |= 1 << bit; }
        }
    }
    if (!next) next = now;
    next += f * 70224 / 4194304;
    if (next > now && !getenv("FAST")) SDL_Delay((Uint32)((next - now) * 1000 / f)); else if (now - next > f / 10) next = now;
}

static void hw_step(int t) {
    div16 += t;
    if (tac & 4) {
        static const int per[4] = {1024, 16, 64, 256};
        timer_clk += t;
        while (timer_clk >= per[tac & 3]) { timer_clk -= per[tac & 3]; if (++tima == 0) { tima = tma; g_if |= 4; } }
    }
    if (serial_clk && (serial_clk -= t) <= 0) { serial_clk = 0; io[1] = 0xFF; io[2] &= 0x7F; g_if |= 8; }
    apu_step(t);
    if (!(lcdc & 0x80)) return;
    line_clk += t;
    if (line_clk >= 456) {
        if (ly < 144) render_line();
        line_clk -= 456; ly++;
        if (ly == 144) { g_if |= 1; present(); }
        else if (ly == 154) { ly = 0; win_line = 0; }
    }
    lcd_stat_check();
}

void cyc(int m) { hw_step(m * 4); }

int irq_service(void) {
    if (ime_delay && --ime_delay == 0) ime = 1;
    u8 p = g_if & g_ie & 31;
    if (!ime || !p) return 0;
    int b = __builtin_ctz(p);
    g_if &= ~(1 << b); ime = 0; push16(pc); pc = 0x40 + b * 8; cyc(5);
    return 1;
}

void do_halt(void) { while (!(g_if & g_ie & 31)) cyc(1); }

static void quit(int code) { save_ram(); SDL_Quit(); exit(code); }

int main(int argc, char **argv) {
    FILE *f = fopen(argc > 1 ? argv[1] : "pokered.gbc", "rb");
    if (!f) { fprintf(stderr, "usage: %s rom.gbc (only used for game data)\n", argv[0]); return 1; }
    fseek(f, 0, SEEK_END); rom_size = ftell(f); rewind(f); rom = malloc(rom_size); fread(rom, 1, rom_size, f); fclose(f);
    if ((f = fopen(SAVE, "rb"))) { fread(sram, 1, sizeof sram, f); fclose(f); }
    SDL_Init(SDL_INIT_VIDEO | SDL_INIT_AUDIO);
    win = SDL_CreateWindow("Pokemon Red", SDL_WINDOWPOS_CENTERED, SDL_WINDOWPOS_CENTERED, 640, 576, SDL_WINDOW_RESIZABLE | SDL_WINDOW_ALLOW_HIGHDPI);
    ren = SDL_CreateRenderer(win, -1, SDL_RENDERER_ACCELERATED);
    SDL_RenderSetLogicalSize(ren, 160, 144);
    tex = SDL_CreateTexture(ren, SDL_PIXELFORMAT_ARGB8888, SDL_TEXTUREACCESS_STREAMING, 160, 144);
    apu_init();
    memset(fb, 0xFF, sizeof fb);
    A = 1; setF(0xB0); B = 0; C = 0x13; D = 0; E = 0xD8; H = 1; L = 0x4D; SP = 0xFFFE; pc = 0x100; g_if = 1;
    for (;;) {
        int r;
        if (pc < 0x4000) r = run_bank[0]();
        else if (pc < 0x8000) r = run_bank[rom_bank]();
        else if (pc >= 0xFF80 && pc < 0xFFFF) { wr(0xFF46, 0xC3); A = 0; zf = 1; cyc(165); pc = pop16(); r = 0; }  // hDMARoutine loads HIGH(wShadowOAM) itself; A is not an input
        else { fprintf(stderr, "execution outside ROM at %04X\n", pc); quit(1); r = 0; }
        if (r) { fprintf(stderr, "uncompiled code at bank %d pc=%04X\n", pc < 0x4000 ? 0 : rom_bank, pc); quit(1); }
    }
}

// Runtime shared by the recompiled code (gen.py output) and rt.c.
#pragma once
#include <stdint.h>
typedef uint8_t u8; typedef uint16_t u16; typedef uint32_t u32;
extern u8 A, B, C, D, E, H, L, zf, nf, hf, cf, ime;
extern u16 SP, pc;
extern int rom_bank;
u8 rd(u16 a); void wr(u16 a, u8 v);
void cyc(int m);          // advance hardware by m machine cycles
extern u8 ime_delay, g_if, g_ie;
int irq_service(void);    // EI delay + service pending interrupt; 1 if pc changed
#define irq_check() ((ime_delay || (ime && (g_if & g_ie & 31))) ? irq_service() : 0)
void do_halt(void);

#define HL() ((u16)((H << 8) | L))
#define BC() ((u16)((B << 8) | C))
#define DE() ((u16)((D << 8) | E))
#define SETHL(v) do { u16 _v = (v); H = _v >> 8; L = _v; } while (0)
#define SETBC(v) do { u16 _v = (v); B = _v >> 8; C = _v; } while (0)
#define SETDE(v) do { u16 _v = (v); D = _v >> 8; E = _v; } while (0)
static inline u8 getF(void) { return (zf << 7) | (nf << 6) | (hf << 5) | (cf << 4); }
static inline void setF(u8 f) { zf = f >> 7 & 1; nf = f >> 6 & 1; hf = f >> 5 & 1; cf = f >> 4 & 1; }
static inline void push16(u16 v) { SP--; wr(SP, v >> 8); SP--; wr(SP, v); }
static inline u16 pop16(void) { u16 lo = rd(SP++); u16 hi = rd(SP++); return lo | hi << 8; }

static inline void ADD(u8 v) { u16 r = A + v; hf = ((A & 15) + (v & 15)) > 15; cf = r > 255; A = r; zf = !A; nf = 0; }
static inline void ADC(u8 v) { u8 c = cf; u16 r = A + v + c; hf = ((A & 15) + (v & 15) + c) > 15; cf = r > 255; A = r; zf = !A; nf = 0; }
static inline void SUB(u8 v) { hf = (A & 15) < (v & 15); cf = A < v; A -= v; zf = !A; nf = 1; }
static inline void SBC(u8 v) { u8 c = cf; int r = A - v - c; hf = ((A & 15) - (v & 15) - c) < 0; cf = r < 0; A = r; zf = !A; nf = 1; }
static inline void AND(u8 v) { A &= v; zf = !A; nf = 0; hf = 1; cf = 0; }
static inline void XOR(u8 v) { A ^= v; zf = !A; nf = hf = cf = 0; }
static inline void OR(u8 v) { A |= v; zf = !A; nf = hf = cf = 0; }
static inline void CP(u8 v) { hf = (A & 15) < (v & 15); cf = A < v; zf = A == v; nf = 1; }
static inline u8 INC(u8 v) { v++; zf = !v; nf = 0; hf = (v & 15) == 0; return v; }
static inline u8 DEC(u8 v) { v--; zf = !v; nf = 1; hf = (v & 15) == 15; return v; }
static inline void ADDHL(u16 v) { u16 h = HL(); u32 r = h + v; hf = ((h & 0xFFF) + (v & 0xFFF)) > 0xFFF; cf = r > 0xFFFF; nf = 0; SETHL(r); }
static inline u16 SPE8(int8_t e) { u16 r = SP + e; zf = nf = 0; hf = ((SP & 15) + (e & 15)) > 15; cf = ((SP & 255) + (u8)e) > 255; return r; }
static inline u8 RLC(u8 v) { cf = v >> 7; v = v << 1 | cf; zf = !v; nf = hf = 0; return v; }
static inline u8 RRC(u8 v) { cf = v & 1; v = v >> 1 | cf << 7; zf = !v; nf = hf = 0; return v; }
static inline u8 RL(u8 v) { u8 c = cf; cf = v >> 7; v = v << 1 | c; zf = !v; nf = hf = 0; return v; }
static inline u8 RR(u8 v) { u8 c = cf; cf = v & 1; v = v >> 1 | c << 7; zf = !v; nf = hf = 0; return v; }
static inline u8 SLA(u8 v) { cf = v >> 7; v <<= 1; zf = !v; nf = hf = 0; return v; }
static inline u8 SRA(u8 v) { cf = v & 1; v = (v >> 1) | (v & 0x80); zf = !v; nf = hf = 0; return v; }
static inline u8 SRL(u8 v) { cf = v & 1; v >>= 1; zf = !v; nf = hf = 0; return v; }
static inline u8 SWAP(u8 v) { v = v << 4 | v >> 4; zf = !v; nf = hf = cf = 0; return v; }
static inline void BIT(int b, u8 v) { zf = !(v >> b & 1); nf = 0; hf = 1; }
static inline void DAA(void) {
    int a = A;
    if (!nf) { if (hf || (a & 15) > 9) a += 6; if (cf || a > 0x9F) { a += 0x60; cf = 1; } }
    else { if (hf) a -= 6; if (cf) a -= 0x60; }
    A = a; zf = !A; hf = 0;
}

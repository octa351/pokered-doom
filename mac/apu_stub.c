#include "rt.h"
void apu_init(void) {} void apu_write(u16 a, u8 v) { (void)a; (void)v; } u8 apu_read(u16 a) { (void)a; return 0xFF; } void apu_step(int t) { (void)t; }

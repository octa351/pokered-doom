#!/usr/bin/env python3
# Static recompiler: pokered.gbc + pokered.sym -> C (one function per ROM bank).
import sys
rom = open(sys.argv[1], 'rb').read()
out = sys.argv[3]
R8 = ['B', 'C', 'D', 'E', 'H', 'L', None, 'A']
R16 = ['BC', 'DE', 'HL', 'SP']
CC = ['!zf', 'zf', '!cf', 'cf']
ALU = ['ADD', 'ADC', 'SUB', 'SBC', 'AND', 'XOR', 'OR', 'CP']
ILLEGAL = {0xD3, 0xDB, 0xDD, 0xE3, 0xE4, 0xEB, 0xEC, 0xED, 0xF4, 0xFC, 0xFD}

def rdx(r): return 'rd(HL())' if r == 6 else R8[r]
def wrx(r, v): return f'wr(HL(),{v});' if r == 6 else f'{R8[r]}={v};'
def rd16(n): return {'BC': 'BC()', 'DE': 'DE()', 'HL': 'HL()', 'SP': 'SP'}[n]
def wr16(n, v): return f'SP={v};' if n == 'SP' else f'SET{n}({v});'

def byte(bank, a): return rom[(a if a < 0x4000 else bank * 0x4000 + a - 0x4000)]

def decode(bank, a):
    """-> (len, code, flow, targets) ; flow: 0 normal, 1 conditional (falls through), 2 terminal"""
    op = byte(bank, a)
    n8 = lambda: byte(bank, a + 1)
    n16 = lambda: byte(bank, a + 1) | byte(bank, a + 2) << 8
    s8 = lambda: (n8() ^ 0x80) - 0x80
    nxt = lambda l: (a + l) & 0xFFFF
    if op in ILLEGAL: return 1, f'fatal_op(0x{op:02X});', 2, []
    if op == 0x00: return 1, 'cyc(1);', 0, []
    if op == 0x10: return 2, 'cyc(1);', 0, []
    if op == 0x76: return 1, 'do_halt();', 0, []
    if op & 0xCF == 0x01: r = R16[op >> 4]; return 3, wr16(r, f'0x{n16():04X}') + 'cyc(3);', 0, []
    if op & 0xEF == 0x02: return 1, ['wr(BC(),A);', 'wr(DE(),A);'][op >> 4] + 'cyc(2);', 0, []
    if op & 0xEF == 0x0A: return 1, ['A=rd(BC());', 'A=rd(DE());'][op >> 4] + 'cyc(2);', 0, []
    if op == 0x22: return 1, 'wr(HL(),A);SETHL(HL()+1);cyc(2);', 0, []
    if op == 0x32: return 1, 'wr(HL(),A);SETHL(HL()-1);cyc(2);', 0, []
    if op == 0x2A: return 1, 'A=rd(HL());SETHL(HL()+1);cyc(2);', 0, []
    if op == 0x3A: return 1, 'A=rd(HL());SETHL(HL()-1);cyc(2);', 0, []
    if op & 0xCF == 0x03: r = R16[op >> 4]; return 1, wr16(r, rd16(r) + '+1') + 'cyc(2);', 0, []
    if op & 0xCF == 0x0B: r = R16[op >> 4]; return 1, wr16(r, rd16(r) + '-1') + 'cyc(2);', 0, []
    if op & 0xC7 == 0x04: r = op >> 3 & 7; return 1, wrx(r, f'INC({rdx(r)})') + f'cyc({3 if r == 6 else 1});', 0, []
    if op & 0xC7 == 0x05: r = op >> 3 & 7; return 1, wrx(r, f'DEC({rdx(r)})') + f'cyc({3 if r == 6 else 1});', 0, []
    if op & 0xC7 == 0x06: r = op >> 3 & 7; return 2, wrx(r, f'0x{n8():02X}') + f'cyc({3 if r == 6 else 2});', 0, []
    if op == 0x07: return 1, 'A=RLC(A);zf=0;cyc(1);', 0, []
    if op == 0x0F: return 1, 'A=RRC(A);zf=0;cyc(1);', 0, []
    if op == 0x17: return 1, 'A=RL(A);zf=0;cyc(1);', 0, []
    if op == 0x1F: return 1, 'A=RR(A);zf=0;cyc(1);', 0, []
    if op == 0x27: return 1, 'DAA();cyc(1);', 0, []
    if op == 0x2F: return 1, 'A=~A;nf=hf=1;cyc(1);', 0, []
    if op == 0x37: return 1, 'nf=hf=0;cf=1;cyc(1);', 0, []
    if op == 0x3F: return 1, 'nf=hf=0;cf=!cf;cyc(1);', 0, []
    if op == 0x08: v = n16(); return 3, f'wr(0x{v:04X},SP);wr(0x{v+1:04X},SP>>8);cyc(5);', 0, []
    if op & 0xCF == 0x09: return 1, f'ADDHL({rd16(R16[op >> 4])});cyc(2);', 0, []
    if op == 0x18:
        t = nxt(2) + s8() & 0xFFFF
        return 2, f'pc=0x{t:04X};cyc(3);irq_check();goto top;', 2, [t]
    if op & 0xE7 == 0x20:
        t = nxt(2) + s8() & 0xFFFF
        return 2, f'if({CC[op >> 3 & 3]}){{pc=0x{t:04X};cyc(3);irq_check();goto top;}}cyc(2);', 1, [t]
    if 0x40 <= op < 0x80:
        d, s = op >> 3 & 7, op & 7
        return 1, wrx(d, rdx(s)) + f'cyc({2 if 6 in (d, s) else 1});', 0, []
    if 0x80 <= op < 0xC0:
        s = op & 7
        return 1, f'{ALU[op >> 3 & 7]}({rdx(s)});cyc({2 if s == 6 else 1});', 0, []
    if op & 0xC7 == 0xC6: return 2, f'{ALU[op >> 3 & 7]}(0x{n8():02X});cyc(2);', 0, []
    if op & 0xE7 == 0xC0:
        return 1, f'if({CC[op >> 3 & 3]}){{pc=pop16();cyc(5);irq_check();goto top;}}cyc(2);', 1, []
    if op == 0xC9: return 1, 'pc=pop16();cyc(4);irq_check();goto top;', 2, []
    if op == 0xD9: return 1, 'pc=pop16();ime=1;cyc(4);irq_check();goto top;', 2, []
    if op & 0xCF == 0xC1:
        r = ['BC', 'DE', 'HL', 'AF'][op >> 4 & 3]
        c = 'u16 v=pop16();setF(v);A=v>>8;' if r == 'AF' else f'{wr16(r, "pop16()")}'
        return 1, c + 'cyc(3);', 0, []
    if op & 0xCF == 0xC5:
        r = ['BC', 'DE', 'HL', 'AF'][op >> 4 & 3]
        return 1, ('push16((A<<8)|getF());' if r == 'AF' else f'push16({rd16(r)});') + 'cyc(4);', 0, []
    if op & 0xE7 == 0xC2:
        t = n16()
        return 3, f'if({CC[op >> 3 & 3]}){{pc=0x{t:04X};cyc(4);irq_check();goto top;}}cyc(3);', 1, [t]
    if op == 0xC3:
        t = n16(); return 3, f'pc=0x{t:04X};cyc(4);irq_check();goto top;', 2, [t]
    if op & 0xE7 == 0xC4:
        t = n16(); nx = nxt(3)
        return 3, f'if({CC[op >> 3 & 3]}){{push16(0x{nx:04X});pc=0x{t:04X};cyc(6);irq_check();goto top;}}cyc(3);', 1, [t]
    if op == 0xCD:
        t = n16(); nx = nxt(3)
        return 3, f'push16(0x{nx:04X});pc=0x{t:04X};cyc(6);irq_check();goto top;', 3, [t]
    if op & 0xC7 == 0xC7:
        t = op & 0x38; nx = nxt(1)
        return 1, f'push16(0x{nx:04X});pc=0x{t:04X};cyc(4);irq_check();goto top;', 3, [t]
    if op == 0xE9: return 1, 'pc=HL();cyc(1);irq_check();goto top;', 2, []
    if op == 0xE0: return 2, f'wr(0xFF00+0x{n8():02X},A);cyc(3);', 0, []
    if op == 0xF0: return 2, f'A=rd(0xFF00+0x{n8():02X});cyc(3);', 0, []
    if op == 0xE2: return 1, 'wr(0xFF00+C,A);cyc(2);', 0, []
    if op == 0xF2: return 1, 'A=rd(0xFF00+C);cyc(2);', 0, []
    if op == 0xEA: return 3, f'wr(0x{n16():04X},A);cyc(4);', 0, []
    if op == 0xFA: return 3, f'A=rd(0x{n16():04X});cyc(4);', 0, []
    if op == 0xE8: return 2, f'SP=SPE8({s8()});cyc(4);', 0, []
    if op == 0xF8: return 2, f'SETHL(SPE8({s8()}));cyc(3);', 0, []
    if op == 0xF9: return 1, 'SP=HL();cyc(2);', 0, []
    if op == 0xF3: return 1, 'ime=0;ime_delay=0;cyc(1);', 0, []
    if op == 0xFB: return 1, 'ime_delay=2;cyc(1);', 0, []
    if op == 0xCB:
        c = byte(bank, a + 1); r = c & 7; x = c >> 3 & 7; h = r == 6
        if c < 0x40:
            fn = ['RLC', 'RRC', 'RL', 'RR', 'SLA', 'SRA', 'SWAP', 'SRL'][x]
            return 2, wrx(r, f'{fn}({rdx(r)})') + f'cyc({4 if h else 2});', 0, []
        if c < 0x80: return 2, f'BIT({x},{rdx(r)});cyc({3 if h else 2});', 0, []
        if c < 0xC0: return 2, wrx(r, f'{rdx(r)}&~{1 << x}') + f'cyc({4 if h else 2});', 0, []
        return 2, wrx(r, f'{rdx(r)}|{1 << x}') + f'cyc({4 if h else 2});', 0, []
    raise Exception(f'op {op:02X}')

def rom_addr(bank, a): return a if a < 0x4000 else bank * 0x4000 + a - 0x4000

nbanks = len(rom) // 0x4000
seeds = set(); labels = set()
for l in open(sys.argv[2]):
    if l[:1] == ';' or ':' not in l: continue
    b, rest = l.split(':', 1); a = int(rest.split()[0], 16); b = int(b, 16)
    labels.add((b, a))
    if 0 <= a < 0x8000 and b < nbanks and (a < 0x4000) == (b == 0) or (a >= 0x4000 and a < 0x8000 and b < nbanks):
        seeds.add((b if a >= 0x4000 else 0, a))
for v in range(0, 0x68, 8): seeds.add((0, v))
seeds.add((0, 0x100))
# text_asm (0x08) embeds code in text data, entered via jp hl: seed the byte after it (false positives are harmless)
for b in range(nbanks):
    lo = 0 if b == 0 else 0x4000
    for a in range(lo + 4, lo + 0x4000):
        if byte(b, a) == 8 and ((b, a) in labels or byte(b, a - 4) == 0x17 or byte(b, a - 1) in (6, 0xA)): seeds.add((b, a + 1))

done = {}   # (bank, addr) -> (len, code, flow)
work = list(seeds)
while work:
    bank, a = work.pop()
    while (bank, a) not in done:
        if a >= 0x8000 or (a < 0x4000 and bank != 0): break
        if a + 3 > 0x8000 and a < 0x4000: pass
        l, code, flow, tg = decode(bank, a)
        done[(bank, a)] = (l, code, flow)
        for t in tg:
            if t < 0x8000: work.append((0 if t < 0x4000 else bank, t))
        if flow == 2: break
        a += l
        if a >= 0x8000: break
        if a == 0x4000 and bank == 0: break
        # a function must not run from bank0 into 0x4000
sys.setrecursionlimit(10000)
import os
os.makedirs(out, exist_ok=True)
for bank in range(nbanks):
    import io
    f = io.StringIO()
    if True:
        f.write('#include "../rt.h"\nvoid fatal_op(int);\n')
        lo = 0 if bank == 0 else 0x4000
        hi = 0x4000 if bank == 0 else 0x8000
        addrs = sorted(a for (b, a) in done if b == bank and lo <= a < hi)
        f.write(f'int run_bank_{bank}(void){{\ntop:\nswitch(pc){{\n')
        for i, a in enumerate(addrs):
            l, code, flow = done[(bank, a)]
            nx = (a + l) & 0xFFFF
            f.write(f'case 0x{a:04X}:pc=0x{nx:04X};{{{code}}}')
            if flow in (0, 1):
                f.write('if(irq_check())goto top;')
                if i + 1 >= len(addrs) or addrs[i + 1] != nx: f.write('goto top;')
            f.write('\n')
        f.write('default: return (pc>=%d&&pc<%d);\n}\n}\n' % (lo, hi))
    path = f'{out}/bank{bank:02d}.c'
    if not os.path.exists(path) or open(path).read() != f.getvalue(): open(path, 'w').write(f.getvalue())
tbl = ''.join(f'int run_bank_{b}(void);' for b in range(nbanks)) + 'int (*const run_bank[])(void)={' + ','.join(f'run_bank_{b}' for b in range(nbanks)) + '};\n'
if not os.path.exists(f'{out}/table.c') or open(f'{out}/table.c').read() != tbl: open(f'{out}/table.c', 'w').write(tbl)
print(len(done), 'instructions', nbanks, 'banks')

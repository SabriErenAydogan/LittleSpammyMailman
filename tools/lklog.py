#!/usr/bin/env python3
"""
Pull LK (little kernel / bootloader) logs out of an `expdb` dump.

Why this exists: when a kernel dies before its own console comes up, ramoops
stays empty and pstore tells us nothing. LK, however, runs to completion every
time and MTK's DRAM log-store persists its log into `expdb`, which lives in
flash and survives cold cuts. That log is the only witness to what the
bootloader handed the kernel, so for a pre-console death it is the whole story.

The log is stored as plain text with `[<ms>] ` timestamps. Sessions are not
delimited by any header, so a session is recovered as a maximal run of
printable bytes that carries LK's own markers.

Usage:
    lklog.py <expdb.bin> [-o out.txt] [--all]

By default only the newest sessions are printed (LK writes forward, so the
highest offsets are the most recent). --all dumps every session found.
"""
import argparse, re, sys

# Strings only LK emits; a printable run without one of these is kernel console
# text or unrelated AEE payload, not a bootloader log.
LK_MARKERS = (b'[PROFILE]', b'platform_init', b'[LK_ENV]', b'mt_boot_init',
              b'[autofb]', b'boot mode', b'mt_boot_init')

PRINTABLE = bytes(range(32, 127)) + b'\n\r\t'
_TBL = bytes(1 if c in PRINTABLE else 0 for c in range(256))


def sessions(data, min_len=512):
    """Maximal printable runs that look like an LK log, oldest first."""
    out, start, n = [], None, len(data)
    for i in range(n):
        if _TBL[data[i]]:
            if start is None:
                start = i
        else:
            if start is not None and i - start >= min_len:
                out.append((start, data[start:i]))
            start = None
    if start is not None and n - start >= min_len:
        out.append((start, data[start:n]))
    return [(o, b) for o, b in out if any(m in b for m in LK_MARKERS)]


def summarise(blob):
    """A few fields worth seeing without reading the whole session."""
    got = {}
    for key, pat in (
            ('boot denemesi', rb'\[autofb\][^\n]*'),
            ('platform_init', rb'platform_init takes \d+ ms'),
            ('boot mode',     rb'boot mode[^\n]{0,40}'),
            ('kernel',        rb'(?:kernel|zimage|Image)[^\n]{0,60}'),
            ('cmdline',       rb'command line[^\n]{0,80}')):
        m = re.findall(pat, blob, re.I)
        if m:
            got[key] = [x.decode('ascii', 'replace').strip() for x in m[:4]]
    return got


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument('expdb')
    ap.add_argument('-o', '--out')
    ap.add_argument('--all', action='store_true')
    ap.add_argument('--min-len', type=int, default=512)
    a = ap.parse_args()

    data = open(a.expdb, 'rb').read()
    ses = sessions(data, a.min_len)
    if not ses:
        print("LK logu bulunamadi (expdb'de LK isareti yok)", file=sys.stderr)
        return 1

    keep = ses if a.all else ses[-6:]
    lines = []
    lines.append("# LK log -- kaynak: %s (%d bayt)" % (a.expdb, len(data)))
    lines.append("# %d oturum bulundu, %d tanesi yaziliyor (en yenisi en altta)"
                 % (len(ses), len(keep)))
    lines.append("")
    for off, blob in keep:
        lines.append("=" * 72)
        lines.append("== oturum @ 0x%08x  (%d bayt)" % (off, len(blob)))
        s = summarise(blob)
        for k in ('boot denemesi', 'boot mode', 'platform_init', 'cmdline'):
            if k in s:
                for v in s[k]:
                    lines.append("   %-14s %s" % (k + ':', v))
        lines.append("=" * 72)
        lines.append(blob.decode('ascii', 'replace'))
        lines.append("")

    text = "\n".join(lines)
    if a.out:
        open(a.out, 'w', encoding='utf-8', newline='\n').write(text)
        print("yazildi: %s (%d bayt, %d oturum)" % (a.out, len(text), len(keep)))
    else:
        sys.stdout.write(text)
    return 0


if __name__ == '__main__':
    sys.exit(main())

# Findings

Working notes from bringing Linux 4.19 up on `selene` (Redmi 10 2022,
MT6769H). Ordered roughly the way the problems were hit.

## 1. Getting any output at all

A kernel that dies before `console_init()` tells you nothing. On MediaTek
there are two independent places a dying kernel can leave traces, and they
behave differently:

* **ramoops / pstore** — a ring buffer in reserved DRAM, read back as
  `/sys/fs/pstore/*` after the next boot. Registers late, at
  `console_initcall`, with `CON_PRINTBUFFER`.
* **mboot_params / AEE** — MediaTek's own record, written to the `expdb`
  partition. Available much earlier, and it survives a hardware watchdog
  reset.

An empty pstore is **not** evidence that the kernel died early. On this
device it was empty because the `reserved-memory` DT node was wrong, so
ramoops never got its region — verified by fixing the node and re-running
under QEMU.

### `fiq_step` breadcrumbs

`aee_rr_rec_fiq_step()` writes a single byte that survives reset. Six of
them around the interesting parts of `init/main.c`, plus
`aee_rr_rec_last_init_func()` inside `do_one_initcall()`, turn "it hangs
somewhere" into an exact answer. See `patches/0005`.

Verify the patch actually landed before trusting a build:

```sh
llvm-objdump -r out/init/main.o | grep aee_rr_rec
```

Expect exactly six `fiq_step` relocations and one `last_init_func`.

**Trap:** `run_init_process()` returns on success too. A breadcrumb after
it is not proof that `exec` failed.

### Reading it back without Android

`docs/`-adjacent tooling in `tools/` dumps `expdb` and decodes it, but that
still needs a booting system. The KAERU payload in `lk/` removes that
dependency: `oem ramoops`, `oem rrlog` and `oem rdmem <addr> <len>` read the
previous boot's records straight out of DRAM from the bootloader.

Memory access there needs LPAE long-descriptor page table entries — this SoC
boots with `TTBCR.EAE` set (`TTBCR = 0xb0003000`). Short-descriptor writes
fault. Measure first with `oem cpuinfo` rather than assuming a format.

**Trap:** `expdb` is a ring. Session counts and "number of boots recorded"
are not reliable evidence for anything.

**Trap:** with `initcall_debug` on, one boot fills the 256 K console ring by
itself. That is why the ISP backtrace in `docs/isp-crash-report.txt` is
missing — the Oops scrolled out before the reset. To capture one boot
cleanly, set the auto-fastboot threshold so the kernel runs exactly once
(`fastboot oem env set kaeru.bootcount 3`).

## 2. Where the kernel died, in order

| build | time | cause |
|---|---|---|
| #13 | 1.21 s | gpufreq |
| #17, #21 | 1.28 s | thermal `BUG()` in `mtk_cooler_sysrst.c` |
| #23, #24 | — | `fiq_step 0xA5`, before `run_init_process` |
| #28–#30 | ~29 s | hardware watchdog (HWT) — no `wd_api` implementation |
| #31 | 66 s | `camerahalserver`, ISP/SMI |

Two of these were the same class of bug: vendor code present, vendor
implementation missing, symbol resolving weakly, failure appearing far from
the cause.

### thermal `sysrst`

`mtk_cooler_sysrst.c` calls `BUG()` when a thermal trip fires. During
bring-up the thermal zones are not configured yet, so this fires almost
immediately and looks like a random early panic. `patches/0003` replaces the
four `BUG()` calls with an actual reset path, adds a 120 s boot grace
period, and permanently disables the reset if it trips that early.
`patches/0004` logs which cooler, zone and trip asked for it.

### watchdog

`fire-t-oss` ships AEE and thermal code that calls `wd_api`, but no
implementation of `wd_api` — so the calls resolve weakly and nothing kicks
the RGU. The device resets at ~29 s. Porting `drivers/watchdog/mediatek/`
from 4.14 fixes it. `CONFIG_MTK_WD_KICKER` must stay off; it duplicates
symbols from `aee/hangdet/aee_hangdet.c`.

## 3. The current blocker

```
[   66.054229] [ISP][ISP_open] - E. UserCount: 0.
[   66.054604] [MTK_SMI]SMI smi_bus_prepare_enable: 3 is not ready.
[   66.054615] [MTK_SMI]SMI smi_bus_prepare_enable: 2 is not ready.
[   66.054626] Unable to handle kernel paging request at virtual address fffffffffffffffe
```

`0xfffffffffffffffe` is `ERR_PTR(-2)`, i.e. `-ENOENT`. SMI larb 2 and 3 are
not ready, the ISP driver gets an error pointer back and dereferences it
without an `IS_ERR()` check. The fault is in ISP; the actual problem is the
SMI larb binding.

Worth testing: whether this changes when the kernel-built DTB is used
instead of the stock base DTB, since the larb bindings live in the device
tree.

## 4. Process notes

Things that cost real time and are cheap to avoid:

* **Verify the binary, not the script.** A cleared `/tmp` made a `cp` fail
  silently; the old image was reflashed and the md5 readback still matched,
  because it matched the *old* file. Always `rm -f` the output before
  building, assert it exists after, and check the new md5 differs from every
  previous one.
* **Verify the patch in the source before building, and the string in the
  binary after.** A patch script that raised an error but did not stop the
  build wasted a full flash cycle.
* **Don't trust a comparison across different capture conditions.** Two
  builds "differing by 0.03%" was used to argue the build pipeline was at
  fault; it wasn't.
* **`mtk.bat` appends its own `--preloader` after `%*`**, overriding yours.
  Call `mtk.py` directly. For BROM recovery in preloader mode, omit
  `--preloader` entirely.

# LittleSpammyMailman

Linux **4.19** bring-up notes, patches and boot diagnostics for the
**Xiaomi Redmi 10 2022** (`selene`, MT6769H / Helio G85), based on the
`fire-t-oss` MT6768 4.19 OSS release.

This is not a ROM and not a finished kernel. It is the set of findings,
patches and tools produced while getting a 4.19 kernel to boot on a device
whose stock kernel is 4.14 — published so the next person does not have to
rediscover them.

**Status:** boots into Android second stage. eMMC, dm-verity, dynamic
partitions, zram, SELinux, vold, apexd, netd and display all come up.
Current blocker is an ISP/SMI crash in `camerahalserver` at ~66 s
(see [`docs/isp-crash-report.txt`](docs/isp-crash-report.txt)).

---

## The headline finding: two ways to get eMMC on MT6768 / 4.19

The symptom is init dying in first stage with

```
init: Failed to mount required partitions early
InitFatalReboot: signal 6
```

and **not a single error line in dmesg** — because the MMC driver was never
probed at all, rather than failing.

The MT6768 device tree describes the same controller at `0x11230000` twice:

| node | compatible | driver | in `mt6768.dts` |
|---|---|---|---|
| `mmc@11230000` | `mediatek,mt6768-mmc` | mainline `drivers/mmc/host/mtk-sd.c` | `status = "disabled"` |
| `msdc@11230000` | `mediatek,msdc` | vendor ComboA (`CONFIG_MMC_MTK_PRO`) | present |

The disabled state is misleading. At the very bottom of `mt6768.dts` there is

```c
#include "mediatek/cust_mt6768_msdc.dtsi"
```

and that file overrides the node:

```c
&mmc0 {
	status = "okay";
	host-function = <MSDC_EMMC>;
	bus-width = <8>;
	mmc-hs400-1_8v;
	mediatek,cqhci;
	vmmc-supply = <&mt_pmic_vemc_ldo_reg>;
	...
};
```

So on 4.19 the **mainline** driver is the intended path, and it works —
`mtk-sd.c` carries `{ .compatible = "mediatek,mt6768-mmc", .data = &mt6768_compat }`.

**Which path you need depends on where your DTB comes from:**

| you ship | use | why |
|---|---|---|
| a kernel-built DTB | mainline `CONFIG_MMC_MTK` | `cust_mt6768_msdc.dtsi` enables `mmc0` for you; no vendor code needed |
| the **stock** base DTB from `boot.img` | vendor `CONFIG_MMC_MTK_PRO` + ComboA | the stock DTB has only `msdc@11230000`; there is no node the mainline driver can bind to, and `selene.dts` is a `/plugin/` overlay so it cannot change the base |

This repository takes the second path, because the AEE / ramoops / expdb
diagnostics used here depend on the stock base DTB. If you build your own
DTB, take the first path — it is strictly less work.

### What is *not* true

An earlier version of these notes claimed Xiaomi had stripped
`ComboA/mt6768` out of `fire-t-oss`. That is wrong. An independent MediaTek
4.19 tree ([`bengris32/android_kernel_mediatek_4.19`](https://github.com/bengris32/android_kernel_mediatek_4.19),
branch `android-4.19.y-mediatek`) has exactly the same shape:

* `ComboA/` contains only `mt6739`, `mt6765`, `mt6885` — no `mt6768`
* `drivers/mmc/host/mediatek/Makefile` has the same hand-written `ifeq` list
  covering only `mt6765`, `mt6761`, `mt6739`
* no `drivers/watchdog/mediatek/`, only the mainline `mtk_wdt.c`
* no `cmdq_hci.c`

Nothing was deleted. These vendor subsystems are a **4.14-era** thing; the
4.19 release line simply uses the mainline drivers instead. Porting them
from 4.14 is only necessary if you deliberately stay in the vendor-node
world, as this tree does.

---

## Layout

```
patches/   small edits against fire-t-oss, as unified diffs
ported/    subsystems copied from the 4.14 selene tree, verbatim
tools/     boot-log extraction and flashing helpers
lk/        KAERU bootloader payload (auto-fastboot, memory dumping)
docs/      captured crash reports
```

### `patches/`

| patch | what it does |
|---|---|
| `0001-mmc-mediatek-mt6768-build-glue` | adds the missing `mt6768` block so ComboA is compiled at all |
| `0002-watchdog-wire-up-mediatek-vendor-stack` | `source`s and builds `drivers/watchdog/mediatek/` |
| `0003-thermal-sysrst-replace-BUG-with-reset` | replaces four `BUG()` calls with a real reset path plus a 120 s boot grace period |
| `0004-thermal-monitor-log-sysrst-requests` | logs which cooler/zone/trip asked for a reset |
| `0005-init-aee-boot-breadcrumbs` | `aee_rr_rec_fiq_step()` markers around `console_init`, `do_basic_setup`, `run_init_process`, plus `last_init_func` |
| `0006-sched-eas_plus-ratelimit-log-spam` | `printk_deferred` → `printk_deferred_once`; "Perf order domain is not ready!" was filling the 256 K ramoops ring every 10 ms |
| `0007`–`0009` | gpufreq, SCP DVFS and SPI fixups |

### `ported/`

Copied unchanged in structure from the 4.14 `selene` source, then adapted:

* `drivers/mmc/host/mediatek/ComboA/mt6768/` — 8 files.
  4.14 → 4.19 fixups: `msdc_sd_power_switch()` `void` → `int` (3 call sites);
  `req_vcore` / `vcore_opp` / `PM_QOS_VCORE_OPP` removed (not in the 4.19
  struct); `msdc_of_parse()` returns `-ENODEV` for `id != 0`, because the
  msdc1 (SD slot) probe crashes without matching DT and regulator entries.
* `drivers/watchdog/mediatek/` — 17 files.
  `mt-plat/mtk_ram_console.h` → `mt-plat/mboot_params.h`;
  `linux/irqchip/mtk-eic.h` dropped, `pwrap_disable()` declared extern.
  `CONFIG_MTK_WD_KICKER` must stay **off**: it duplicates symbols already
  provided by `aee/hangdet/aee_hangdet.c`.

  This one is needed because `fire-t-oss` ships vendor AEE and thermal code
  that calls into `wd_api`, but ships no implementation of it — the symbols
  resolve weakly and the device takes a hardware watchdog reset at ~29 s.

### Relevant config

```
CONFIG_MMC_MTK is not set          # mainline off — no matching node in the stock DTB
CONFIG_MMC_MTK_PRO=y               # vendor ComboA on
CONFIG_MTK_EMMC_SUPPORT=y
CONFIG_MTK_EMMC_HW_CQ is not set   # cmdq_hci.c does not exist in 4.19
CONFIG_MEDIATEK_WATCHDOG is not set
CONFIG_MTK_WATCHDOG=y
CONFIG_MTK_WATCHDOG_COMMON=y
CONFIG_MTK_WATCHDOG_COMMON_V2=y
CONFIG_MTK_WD_KICKER is not set    # duplicate symbols with aee_hangdet
```

### `tools/`

* `lklog.py` — pulls LK and preloader sessions out of an `expdb` dump.
* `flash-session/` — flash, recover and collect scripts. `05` produces a
  decoded LK log automatically, `07` dumps device memory over
  `fastboot oem rdmem` in 4 KB chunks.

### `lk/`

`board-selene.c` for [KAERU](https://github.com/bengris32/kaeru), providing:

* **auto-fastboot** — after five consecutive failed boots the device drops
  into fastboot by itself, so a bootlooping kernel never needs a cable and
  a BROM recovery.
* `oem ramoops`, `oem rrlog`, `oem sram`, `oem rdmem <addr> <len>`,
  `oem cpuinfo` — read the previous boot's logs and arbitrary DRAM from
  the bootloader, before Android exists.

Memory access uses LPAE long-descriptor page tables (this SoC boots with
`TTBCR.EAE` set); short-descriptor writes will fault.

---

## Credits

* [`bengris32`](https://github.com/bengris32) — KAERU, and the
  `android_kernel_mediatek_4.19` tree that made the "nothing was stripped"
  comparison possible.
* [`vrdons`](https://github.com/vrdons) and the
  [mt6768-S](https://github.com/mt6768-S) group — the mainline-DTB approach,
  and the questions that corrected the record here.
* `creativchic` — the 4.14 `selene` kernel that everything here was ported from.
* MediaTek and Xiaomi, for the original sources.

## License

GPL-2.0, following the kernel sources these patches apply to.

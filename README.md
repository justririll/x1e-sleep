# Deep sleep on the ASUS Vivobook S15 (S5507QA, Snapdragon X Elite X1E80100)

> **Disclaimer: this is vibe coding.** Almost everything here was written
> and debugged with AI assistants (Claude, plus another model for firmware
> analysis), with a human driving the tests on real hardware. Treat it as
> experimental research notes and test patches, not reviewed kernel code.
> Nothing here has been sent upstream yet. Use at your own risk.

## Result

With all of this applied, s2idle on this laptop reaches the deepest
platform state (AOP stats: `ddr`, `cxsd` and `aosd` all accumulate for
~99.7% of the sleep time). The battery drain in sleep is **~0.25 W**
(1886 s, 130 mWh). Windows Modern Standby on the same laptop measured
~0.23 W. Before this work the drain was ~4 W.

Setup this was tested on:

- BIOS .367;
- Linux 7.2 from [jglathe/linux_ms_dev_kit](https://github.com/jglathe/linux_ms_dev_kit/tree/jg/ubuntu-qcom-x1e-7.2.y), branch `jg/ubuntu-qcom-x1e-7.2.y` @ `0aaff8f`, NixOS;
- Linux running at **EL2** through slbounce, with the DSPs started by
  qebspil. Some parts (el1tmr, qebspil) only matter at EL2.
- The numbers below were measured with the kernel in VHE mode plus
  `el1tmr`. **nVHE works too** (`id_aa64mmfr1.vh=0`, el1tmr not loaded):
  the kernel then runs at EL1 on the EL1 timers itself, a small nVHE
  hypervisor keeps EL2, KVM still works, and full DRIPS was reached. The
  hourly AOSD reset happens in both modes, so it is not caused by EL2 or
  el1tmr.

**Known open issue: hard resets in long full-DRIPS sleeps.** The reset
(`PM: Reset by PSHOLD`, `Reset Type: Hard Reset` in the next boot's XBL
log) lands at about *N hours + ~38 s after boot*, not at a fixed time after
suspend, and only while the SoC is in AOSD (XO off). It also happens on AC
power. With AOSD enabled the laptop reset almost exactly every ~61 min of
sleep (2026-10-05…07). The periodic trigger and the initiator of the reset
are not known yet. Not tested at EL1 so far.

**Current default: CXSD-only sleep.** `modules/aoss-cxsd-only` inhibits
AOSD over QMP (`{class: aoss_slp, res: sleep, val: disable}`); CX collapse
and DDR low-power mode stay allowed. Since 2026-10-08 no sleep has ended in
a reset, including a **16.9 h overnight sleep: 2.93 Wh, ~0.17 W, 99.96% of
the time in `cxsd`** (about 4 Wh, ~7% of the battery per day). That is not
worse than the ~0.25 W measured in full DRIPS.

## Layout

Generic X1E80100 (Hamoa) material sits at the top level. Everything
specific to this laptop is in `vivobook-s15/`.

```
qebspil/                    patch for qebspil (git format-patch against 8e4d9e6)
kernel/upstream-backports/  fixes taken from upstream or lore
kernel/sleep/               our own X1E sleep/power fixes
kernel/experimental/        DC ZVA erratum + CL5
modules/                    out-of-tree modules (EL2 timer helper, ADSP messages, CXSD-only)
vivobook-s15/kernel/        EC + keyboard drivers and DT fixes for this laptop
vivobook-s15/nixos/         the NixOS module that wires everything together
vivobook-s15/scripts/       suspend energy log
```

## qebspil

`qebspil/0001-pil-send-AOSS-load_state-off-on-before-starting-ADSP.patch`

- **Problem:** qebspil starts ADSP/CDSP from UEFI, but AOSS is never told
  that the images run (Linux PAS sends `load_state on` through QMP in
  `qcom_q6v5_prepare()`). After the first DDR low-power mode in s2idle the
  ADSP went silent: GLINK TX hung, battmgr returned -110, and the system
  died a few seconds after resume.
- **Fix:** a minimal polled AOSS QMP client (`src/qmp.c`) sends
  `load_state off` and then `on` for adsp/cdsp right before
  auth_and_reset, as a Linux PAS stop + start would.

## Kernel: upstream backports

| Patch | What | Upstream status |
|---|---|---|
| `drm-msm-a6xx-fix-stale-rpmh-votes.patch` | `a6xx_rpmh_stop()` had an inverted `GMU_STATUS_FW_START` check, so after the GMU had run, the GPU RSC never went to sleep. Its RPMh votes then blocked CXSD and DDR LPM. This was the first big sleep blocker. The backport also halts the GMU CM3 core before `rpmh_stop`, like upstream. | **Merged upstream** ("drm/msm/a6xx: Fix stale rpmh votes after suspend", Shivam Rawat / Akhil P Oommen). Not in 7.2. |
| `qcom-pdc-wake-and-ss3.patch` | Qualcomm PDC series v4 (GPIO wake through PDC, X1E PDC secondary mode, pinctrl, and the `domain_ss3` system idle state `0x0200c354` in `hamoa.dtsi`). | **Merged upstream** (current master has the X1E quirk and `domain_ss3`). |
| `serial-qcom-geni-force-suspend-resume.patch` | With Bluetooth up, `hci_uart` keeps the BT UART open; `uart_suspend_port()` relies on `pm_runtime_put_sync()`, which does nothing during system suspend, so the UART kept its clocks, interconnect and CX performance votes and the SoC never left DDR-only sleep (`cxsd`/`aosd` = 0). This is the upstream fix "serial: qcom-geni: add force suspend/resume to system sleep callbacks" (Praveen Talari). We first found and fixed it ourselves before learning it was already upstream. | **Upstream**, `d0cd9c8d0fd5` (in 7.3). Needed on 7.2. |
| `soundwire-qcom-wait-for-irq-thread-before-gating-clock.patch` | `swrm_runtime_suspend()` gates the SoundWire clock while the interrupt thread still touches the controller; the next clock-stop exit can fail with a bus clash and leave a WSA8845 speaker amp `UNATTACHED` until reboot (seen here as speakers going silent). One line: `synchronize_irq()` before gating the clock. | Posted by Oleg Keri on 2026-10-07, not merged yet. In this laptop's build since 2026-10-10, being tested. |
| `scmi-qcom-memlat-rfc-v7.patch` | Qualcomm SCMI vendor protocol + memlat (Sibi Sankar, RFC v7). CPUCP scales DDR/LLCC by memory latency. Not needed for sleep; it improved memory bandwidth. | RFC on lore, not merged. |

## Kernel: our sleep fixes

| Patch | What | Upstream status |
|---|---|---|
| `lpass-macro-release-votes-in-runtime-suspend.patch` | The LPASS tx and rx macro drivers enable the `macro` and `dcodec` clocks (q6prm LPASS_HW_MACRO/DCODEC votes to the ADSP) in probe and drop them only in remove. The ADSP then keeps the audio core clock voted forever, so AOP never collapses CX or turns off XO (`cxsd`/`aosd` stay 0). The va and wsa macros already handle this through pm_clk. The patch takes the votes in runtime resume and drops them in runtime suspend. Sound still works. The leak was first found by valpackett. | **Fixed upstream in 7.3** by Ajay Kumar Nandam (Qualcomm): "ASoC: codecs: lpass-{tx,rx}-macro: switch to PM clock framework" (b9b23e72ab, b05482e7ce). Needed only for older kernels such as jglathe 7.2. |
| `vivobook-s15/kernel/dts-vivobook-s15-edp-regulator-not-always-on.patch` | `VREG_EDP_3P3` (the 3.3 V supply of the Samsung ATNA56AC03 OLED panel) was `regulator-always-on`, so the panel stayed powered in s2idle. Removing it cut sleep drain from **~1.43 W to ~0.25 W**. The panel driver powers the panel through runtime PM; `regulator-boot-on` is kept. Other X1E boards with the same pattern may have the same leak. | Not upstream; master still has `regulator-always-on`. |
| `pmdomain-system-sleep-only.patch` | Generic genpd and DT-binding change: a domain idle state marked `system-sleep-only` is never picked by runtime idle, only by system suspend. See "Runtime DRIPS" below. | Not upstream. |
| `dts-hamoa-add-ss1-idle-state.patch` | Adds platform.SS1 (`0x02000154`, from ACPI `\_SB.SYSM._LPI`) as a shallower system idle state and marks DRIPS `system-sleep-only`. See "Runtime DRIPS" below. | Not upstream. |
| `syscon-skip-clock-of-clock-providers.patch` | syscon attached the parent clock of the TCSR clock provider (`bi_tcxo`) as its register clock and kept it prepared, which pinned an RPMh XO vote. Skip `clocks` for nodes with `#clock-cells`. | Not upstream. |
| `pcie-qcom-keep-gen1-icc-vote.patch` | After link up, pcie-qcom votes full link bandwidth, which pinned DDR at 2092 MHz while the link idled in L1ss. Keep the boot-time Gen1 x1 vote. Debatable: real DMA traffic relies on the LLCC to DDR BWMON. | Not upstream. |

## Runtime DRIPS: how Windows does it

After the first s2idle, entering the deepest system state (DRIPS,
`0x0200c354`) from **runtime** idle hangs the SoC. This was proven to be on
the TZ side: with a kprobe that skips the `PSCI_SYSTEM_SUSPEND` SMC the
system stays alive.

A Windows WPR trace (Kernel-Processor-Power `PlatformIdleVeto`) showed
that Windows never enters DRIPS while the screen is on. The PEP vetoes it
(reasons 4/5/8) and only allows platform.SS1. DRIPS is used only in Modern
Standby. We do the same:

- `kernel/sleep/pmdomain-system-sleep-only.patch` adds a
  `system-sleep-only` property for domain idle states. The runtime genpd
  governor skips such a state, but `genpd_sync_power_off()` (s2idle) still
  uses it.
- `dts-hamoa-add-ss1-idle-state.patch` adds SS1 and marks DRIPS
  (`domain_ss3`) `system-sleep-only`. Runtime idle then gets CL5 and SS1,
  and DRIPS is used only in s2idle.

An earlier version did the same with a 4500 µs per-CPU resume-latency QoS
from `el1tmr`. That worked only at EL2, because the module refuses to load
at EL1.

## Kernel: Vivobook support

`vivobook-s15/kernel/vivobook-s15-ec-hid.patch`:

- **EC driver** (`drivers/platform/arm64/asus-vivobook-s15.c`): fan
  RPM/PWM/profiles, SoC temperature feed, keyboard RGB. Suspend notifies
  the EC with `0x23 01` and resume with `0x23 00`. This is what Windows
  sends (confirmed with a kernel-debugger capture): the DSDT `PEP0._DSM` Modern Standby entry/exit
  (UUID `11e00d56…`, functions 7/8) writes EC command `0x23` on I2C6 at
  address 0x76.
- **The EC driver is work in progress.** Notes on the EC protocol:
  - EC command `0x20` takes a sensor channel byte: `{0x20, channel, 0x02,
    temp_lo, temp_hi}`, temperature in 0.1 °C.
  - The ACPI tables can also feed thermal zones `TZ31`…`TZ37` as
    channels 2…8.
  - A Windows kernel-debugger capture of the AML debug output showed that
    Windows only sends channel 1 (SoC Tj, about once a second), the same
    as this driver.
  - Still missing: battery health that MyASUS reads through the EC (SBS
    registers: cycle count, full/design capacity), plus a few unknown EC
    registers that MyASUS polls. See `ASUS_EC.md`.
- **Keyboard driver** (`hid-asus-vivobook-s15`): Fn hotkeys, backlight,
  Fn-lock.
- The EC node in the DT.

`vivobook-s15/kernel/ec-timed-standby-experiment.patch`: an opt-in
experiment (`disable_standby_timer=1`) that clears the EC's timed-standby
flag (EC RAM `0xca68`) for the duration of system sleep and restores it on
resume, to test whether an EC timer is behind the hourly resets. It is not
known to fix anything; off by default.

## Kernel: DC ZVA and CL5 (`kernel/experimental/`)

- `x1-dc-zva-erratum-and-cl5.patch`:
  - On this firmware `DC ZVA` is broken once the clusters use the CL5
    power-collapse state: it can hard-reset the machine (see
    icecream95/x1e-crash).
  - jglathe's tree avoids that by not using CL5.
  - This patch takes Marc Zyngier's Oryon erratum, which disables `DC ZVA`
    for EL0 and emulates it, and extends it to the kernel (`clear_page`,
    `memset`, MTE). With the erratum in place it enables CL5 on all three
    clusters.
  - Upstream master (7.3-rc5) has CL5 in `hamoa.dtsi` but no `DC ZVA`
    workaround in `cpu_errata.c` that we could find, so mainline may need
    this too.

## Modules

- `el1tmr`, EL2 only:
  - Under VHE (`HCR_EL2.E2H=1`) the kernel's `CNTP_*_EL0` accesses are
    redirected to the EL2 physical timer (`CNTHP`), so the host kernel
    ticks on CNTHP. The `*_EL02` aliases are the only way to reach the EL1
    timers from the host. The secure firmware computes the APSS wake-up
    deadline from the EL1 timers (what Windows and EL1 Linux use).
  - Before power-down idle states the module writes the next CNTHP
    deadline into `CNTP_CVAL_EL02` (the EL1 physical timer) with the
    interrupt masked, and parks it far away again on exit.
  - It also clears `CNTV_CTL_EL02` (the EL1 virtual timer) that UEFI leaves
    armed and long expired: it made the firmware abort every system-level
    sleep entry.
  - Do not load it while KVM guests run.
- `adsp-pwr-lmts` (`qcom_adsp_pwr_lmts`):
  - An rpmsg driver for the ADSP `APPS_ADSP_PWR_LMTS_GLINK_PORT` channel.
  - It sends the 24-byte `MODERN_STANDBY_STATE` message that Windows PEP
    (`qcpep8380.sys`) sends: state 1 on system suspend, 0 on resume.
  - On entry the ADSP stops its power-limits timer, which otherwise wakes
    it ~100 times/s.
  - It replaces an earlier userspace script that sent the same message from the suspend hooks.
- `aoss-cxsd-only` (`aoss_cxsd_only`): the workaround for the hourly
  resets. At load it sends `{class: aoss_slp, res: sleep, val: disable}`
  to the AOSS over the existing `qcom_aoss` QMP transport, so AOP never
  enters AOSD (XO shutdown); CXSD and DDR LPM are still used. Unloading it
  re-enables AOSD. Note: the `qcom_aoss` debugfs file
  `prevent_aoss_sleep` sends this command without `val`, which is why a
  module is used.
- `adsp-sleepstate`: drives the outbound SMP2P `sleepstate` bit to the
  ADSP like Windows `qcsubsys`: 0x1000 while awake, 0 on suspend. Needs
  the `adsp-sleepstate` DT overlay from `vivobook-s15/nixos/vivobook-s15.nix`.
  Whether it is really needed is still being tested.

## Scripts (`vivobook-s15/scripts/`)

- `sleep-log.sh pre|post`: logs battery energy and the AOP
  `ddr`/`cxsd`/`aosd` counters around each suspend to
  `/var/log/sleep-energy.log`. Drain in W is
  `(e_pre - e_post) / (t_post - t_pre) * 3.6e-3` (energy is in µWh).

## Spurious wake-ups with the lid open

When the laptop suspends with the lid **open** (for example GNOME's idle
suspend), it woke up again exactly **~5 min 2 s** later, every time. The
wake IRQ (`/sys/power/pm_wakeup_irq`, `pm_debug_messages`) was
`gpio_keys` (gpio92), the lid switch: the EC pulses the lid line a few
minutes into s2idle although the lid did not move. With the lid closed the
laptop slept 17 h without a spurious wake.

Fix, in `vivobook-s15/nixos/vivobook-s15.nix`
(`powerManagement.powerDownCommands` / `resumeCommands`): before
suspend, if logind reports `LidClosed=false`, set
`/sys/bus/platform/devices/gpio-keys/power/wakeup` to `disabled`; set it
back to `enabled` on resume. The power key and the keyboard still wake the
laptop; with the lid closed, opening it still wakes it. Verified: with lid
wake disabled a lid-open sleep lasted until the power key was pressed.

## Other settings that matter (see `vivobook-s15/nixos/vivobook-s15.nix`)

- `msm.psr_enabled=0`: PSR caused green stripes on the panel. Re-tested on
  2026-10-09: no stripes any more and `self_refresh_active=1`, but idle
  power with the screen on did not change (~4.05 W either way), and
  turning the display off and on again (Mutter `PowerSaveMode` 3 → 0) with
  PSR enabled hard-reset the laptop. So it stays off.
- `qcrypto` blacklisted: QCE holds an always-on DDR bandwidth vote.
- `nvme.quirks=1344:5413:simple_suspend`.

## Credits

- valpackett: the LPASS macro vote leak, pointing out the upstream geni fix.
- Praveen Talari (Qualcomm): geni serial force suspend.
- Oleg Keri: the SoundWire clock-gating race fix.
- Shivam Rawat / Akhil P Oommen: GMU fix.
- Qualcomm: PDC series, memlat RFC.
- Marc Zyngier: the DC ZVA erratum.
- jglathe: kernel tree.
- The slbounce and qebspil authors.

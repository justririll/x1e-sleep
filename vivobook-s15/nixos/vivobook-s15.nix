# ASUS Vivobook S 15 (S5507QA, Snapdragon X Elite X1E-78/80) hardware support:
# custom kernel, device tree, firmware and the initrd module set that is known
# to boot. Shared by the installed system and the installer ISO.
{ config, lib, pkgs, kernelPkgs, ... }:

let
  # ccache for the kernel build (kernelPkgs is a separate nixpkgs, so programs.ccache.packageNames
  # does not reach it). Cache in /var/cache/ccache, exposed to the sandbox by programs.ccache.
  kernelCcache = kernelPkgs.ccacheWrapper.override {
    extraConfig = ''
      export CCACHE_COMPRESS=1
      export CCACHE_DIR=/var/cache/ccache
      export CCACHE_UMASK=007
      export CCACHE_MAXSIZE=20G
      export CCACHE_SLOPPINESS=random_seed,include_file_mtime,include_file_ctime,time_macros
    '';
  };
  kernelStdenv = kernelPkgs.overrideCC kernelPkgs.stdenv kernelCcache;

  customKernel = (kernelPkgs.linuxManualConfig.override { stdenv = kernelStdenv; }) {
    version = "7.2.0";
    modDirVersion = "7.2.0";

    src = kernelPkgs.fetchFromGitHub {
      owner = "jglathe";
      repo = "linux_ms_dev_kit";
      rev = "0aaff8f";
      hash = "sha256-pdQNoZBbGShzq1GZJPm85m+IvmyM9P22JSD8tXLDUlg=";
    };

    configfile = ../config;
    allowImportFromDerivation = true;
    features = { efiBootStub = true; };
  };

  # Mainline kernel (2026-10-03 test): torvalds v7.3-rc5 + mainline/*.patch
  # (our sleep/EC patches rebased, EL2 bits from the jglathe tree). Boot entry
  # "mainline" (specialisation), the jglathe kernel stays the default.
#  mainlineKernel = kernelPkgs.linuxManualConfig {
#    version = "7.3.0-rc5";
#    modDirVersion = "7.3.0-rc5";
#
#    src = kernelPkgs.fetchFromGitHub {
#      owner = "torvalds";
#      repo = "linux";
#      rev = "72d3fcf802c45d00b300f25b848a93c3a2bd7c7e";
#      hash = "sha256-NrTyfot19uJ1SulXU98z2V+leOjjjLmoueX8pnyvn+o=";
#    };
#
#    configfile = ../config-mainline;
#    allowImportFromDerivation = true;
#    features = { efiBootStub = true; };
#  };

#  mainlinePatches = map (f: { name = lib.removeSuffix ".patch" f; patch = ../mainline + "/${f}"; })
#    (lib.sort lib.lessThan (lib.filter (lib.hasSuffix ".patch")
#      (builtins.attrNames (builtins.readDir ../mainline))));

  # Vendor-signed ADSP/CDSP/GPU firmware from the ASUS Windows driver package;
  # linux-firmware doesn't ship the per-device signed blobs.
  asusFirmware = pkgs.runCommand "vivobook-s15-firmware" { } ''
    dir=$out/lib/firmware/qcom/x1e80100/ASUSTeK/vivobook-s15
    mkdir -p $dir
    cp ${../el2-stuff/firmware/qcom/x1e80100/ASUSTeK/vivobook-s15}/* $dir/
  '';

  # Every module is forced into the initrd: the ISO/system only booted
  # reliably this way (display, keyboard, USB and DSPs up before stage 2).
  initrdModules = [
    "aes_ce_ccm"
    "xt_conntrack"
    "nf_conntrack"
    "nf_defrag_ipv6"
    "nf_defrag_ipv4"
    "ip6t_rpfilter"
    "ipt_rpfilter"
    "xt_pkttype"
    "nft_compat"
    "nf_tables"
    "sch_fq_codel"
    "isofs"
    "qrtr_mhi"
    "uas"
    "usb_storage"
    "input_leds"
    "joydev"
    "snd_soc_hdmi_codec"
    "btrfs"
    "hid_multitouch"
    "hid_asus_vivobook_s15"
    "hid_generic"
    "xor"
    "libblake2b"
    "ath12k_wifi7"
    "raid6_pq"
    "ath12k"
    "pm8941_pwrkey"
    "i2c_hid_of"
    "mhi"
    "i2c_hid"
    "ucsi_glink"
    "qcom_pon"
    "qcom_battmgr"
    "typec_ucsi"
    "qrtr_smd"
    "rpmsg_ctrl"
    "qcom_pd_mapper"
    "panel_samsung_atna33xc20"
    "phy_nxp_ptn3222"
    "hid"
    "qcom_spmi_temp_alarm"
    "ps883x"
    "reboot_mode"
    "industrialio"
    "nvme"
    "rtc_pm8xxx"
    "ghash_ce"
    "mac80211"
    "gf128mul"
    "hci_uart"
    "qcom_iris"
    "sm4_ce_gcm"
    "libarc4"
    "videobuf2_dma_contig"
    "btqca"
    "nvmem_qcom_spmi_sdam"
    "sm4_ce_ccm"
    "videobuf2_memops"
    "btrtl"
    "nvme_core"
    "btbcm"
    "cfg80211"
    "v4l2_mem2mem"
    "nvme_keyring"
    "btintel"
    "sm4_ce"
    "nvme_auth"
    "bluetooth"
    "pci_pwrctrl_pwrseq"
    "sm4_ce_cipher"
    "qcom_spmi_pmic"
    "sm4"
    "i2c_qcom_geni"
    "videobuf2_v4l2"
    "qrtr"
    "msm"
    "phy_qcom_edp"
    "qcom_stats"
    "qcom_geni_serial"
    "videodev"
    "snd_soc_wcd938x"
    "qcom_q6v5_pas"
    "snd_soc_wcd_classh"
    "dispcc_x1e80100"
    "qcom_pil_info"
    "videobuf2_common"
    "snd_soc_x1e80100"
    "snd_soc_lpass_tx_macro"
    "qcom_q6v5"
    "snd_soc_wcd938x_sdw"
    "snd_soc_qcom_common"
    "snd_soc_lpass_rx_macro"
    "mc"
    "snd_soc_lpass_va_macro"
    "regmap_sdw"
    "snd_soc_wcd_common"
    "snd_soc_lpass_wsa_macro"
    "snd_soc_wcd_mbhc"
    "snd_soc_qcom_sdw"
    "soundwire_qcom"
    "snd_soc_lpass_macro_common"
    "videocc_sm8550"
    "qcom_sysmon"
    "pinctrl_sm8550_lpass_lpi"
    "ubwc_config"
    "qcom_common"
    "pinctrl_lpass_lpi"
    "snd_soc_core"
    "ocmem"
    "qcom_glink_smem"
    "drm_gpuvm"
    "qcom_edac"
    "gpucc_x1e80100"
    "mdt_loader"
    "snd_compress"
    "lpasscc_sc8280xp"
    "slimbus"
    "drm_exec"
    "gpu_sched"
    "icc_bwmon"
    "tcsrcc_x1e80100"
    "snd_pcm"
    "libdes"
    "authenc"
    "sbsa_gwdt"
    "qcom_cpucp_mbox"
    "snd_timer"
    "qcom_rng"
    "snd"
    "socinfo"
    "pwrseq_qcom_wcn"
    "soundcore"
    "arm_smccc_trng"
    "display_connector"
    "soundwire_bus"
    "efi_pstore"
    "gpio_keys"
    "fixed"
    "simple_bridge"
    "overlay"
    "nls_iso8859_1"
    "dmi_sysfs"
    "autofs4"
    "aes_neon_bs"
    "aes_ce_blk"
  ];
in
{
  boot.kernelPackages = kernelPkgs.linuxPackagesFor customKernel;
  programs.ccache.enable = true;  # creates /var/cache/ccache (group nixbld)
  nix.settings.extra-sandbox-paths = [ "/var/cache/ccache" ];  # visible to kernelCcache in builds

  # Linux at EL2/VHE runs on the hyp timer, but the secure firmware picks the APSS wake deadline
  # only from the EL1 CNTP/CNTV timers (2026-09-30: with none armed it refuses system suspend).
  # el1tmr (2026-10-02) mirrors each CPU's hyp-timer deadline into the masked EL1 physical timer on
  # CPU_PM_ENTER, so runtime system-level idle really sleeps and wakes on time; it also disables the
  # expired EL1 virtual timer UEFI leaves on cpu0, and like Windows keeps runtime idle out of
  # platform.DRIPS with a 4.5 ms per-CPU resume-latency QoS (SS1/CL5 allowed; s2idle ignores QoS).
  # Only while KVM guests do not run (KVM owns these timers). Source: ./el1tmr.
  boot.extraModulePackages = [
    (let kernel = config.boot.kernelPackages.kernel; in kernelPkgs.stdenv.mkDerivation {
      pname = "el1tmr";
      version = "4";
      src = ./el1tmr;
      nativeBuildInputs = kernel.moduleBuildDependencies;
      buildPhase = "make -C ${kernel.dev}/lib/modules/${kernel.modDirVersion}/build M=$PWD modules";
      installPhase = "install -Dm444 el1tmr.ko $out/lib/modules/${kernel.modDirVersion}/extra/el1tmr.ko";
    })
    (let kernel = config.boot.kernelPackages.kernel; in kernelPkgs.stdenv.mkDerivation {
      pname = "asus-adsp-sleepstate";
      version = "1";
      src = ./adsp-sleepstate;
      nativeBuildInputs = kernel.moduleBuildDependencies;
      buildPhase = "make -C ${kernel.dev}/lib/modules/${kernel.modDirVersion}/build M=$PWD modules";
      installPhase = "install -Dm444 asus_adsp_sleepstate.ko $out/lib/modules/${kernel.modDirVersion}/extra/asus_adsp_sleepstate.ko";
    })
    (let kernel = config.boot.kernelPackages.kernel; in kernelPkgs.stdenv.mkDerivation {
      pname = "qcom-adsp-pwr-lmts";
      version = "1";
      src = ./adsp-pwr-lmts;
      nativeBuildInputs = kernel.moduleBuildDependencies;
      buildPhase = "make -C ${kernel.dev}/lib/modules/${kernel.modDirVersion}/build M=$PWD modules";
      installPhase = "install -Dm444 qcom_adsp_pwr_lmts.ko $out/lib/modules/${kernel.modDirVersion}/extra/qcom_adsp_pwr_lmts.ko";
    })
    # 2026-10-08 workaround: in AOSD (XO off) the SoC resets at boot + N h + 38 s; CXSD-only
    # sleep survives (~0.17 W). Disables AOSD via AOSS QMP at load (modules/aoss-cxsd-only).
    (let kernel = config.boot.kernelPackages.kernel; in kernelPkgs.stdenv.mkDerivation {
      pname = "aoss-cxsd-only";
      version = "1";
      src = ./aoss-cxsd-only;
      nativeBuildInputs = kernel.moduleBuildDependencies;
      buildPhase = "make -C ${kernel.dev}/lib/modules/${kernel.modDirVersion}/build M=$PWD modules";
      installPhase = "install -Dm444 aoss_cxsd_only.ko $out/lib/modules/${kernel.modDirVersion}/extra/aoss_cxsd_only.ko";
    })
  ];
  boot.kernelModules = [ "el1tmr" "asus_adsp_sleepstate" "qcom_adsp_pwr_lmts" "aoss_cxsd_only" ];

  # The ADSP power-limits (PLD) timer wakes it ~100 times/s unless told the system is in Modern Standby.
  # Windows (qcpep8380.sys) sends MODERN_STANDBY_STATE on APPS_ADSP_PWR_LMTS_GLINK_PORT around sleep;
  # do the same (ADSP then wakes ~2 times/s).
  # sent by the qcom_adsp_pwr_lmts rpmsg driver (modules/adsp-pwr-lmts) from its suspend/resume callbacks
  # The EC pulses the lid GPIO (gpio-keys, gpio92) ~5 min into s2idle even with the
  # lid open, which fully wakes the laptop. If we suspend with the lid open, drop lid
  # wakeup for this sleep (power key / keyboard still wake); restore it on resume.
  powerManagement.powerDownCommands = ''
    ${pkgs.bash}/bin/sh ${./sleep-log.sh} pre || true
    if [ "$(${pkgs.systemd}/bin/busctl get-property org.freedesktop.login1 /org/freedesktop/login1 org.freedesktop.login1.Manager LidClosed 2>/dev/null)" = "b false" ]; then
      echo disabled > /sys/bus/platform/devices/gpio-keys/power/wakeup || true
    fi
  '';
  powerManagement.resumeCommands = ''
    echo enabled > /sys/bus/platform/devices/gpio-keys/power/wakeup || true
    ${pkgs.bash}/bin/sh ${./sleep-log.sh} post || true
  '';

  # EC driver (asus_vivobook_ec: SoC temperature feed, fan RPM/PWM/profiles,
  # keyboard RGB) + keyboard driver (hid-asus-vivobook-s15: Fn hotkeys,
  # backlight, Fn-lock, Fn+F fan profile) + the EC node in the device tree.
  # Replaces the old 1/2/3.patch (now in old/). Controlled by
  # modules/vivobook-control.nix.
  boot.extraModprobeConfig = "options asus_vivobook_s15 disable_standby_timer=1";
  boot.kernelPatches = [
    { name = "vivobook-s15"; patch = ../vivobook-s15.patch; }
    { name = "ec-timed-standby-experiment"; patch = ../ec-timed-standby-experiment.patch; }
    { name = "pdc-sleep"; patch = ../pdc-sleep.patch; }
    { name = "x1-zva-cl5"; patch = ../x1-zva-cl5.patch; }
    # syscon must not hold the TCSR parent clock (bi_tcxo) prepared: pins xo.lvl ON in suspend
    { name = "syscon-xo"; patch = ../syscon-xo.patch; }
    # Qualcomm SCMI vendor protocol + memlat (CPUCP scales DDR/LLCC/DDR_QOS), RFC v7 from lore
    { name = "memlat-scmi"; patch = ../memlat-scmi.patch; }
    # X1E PCIe: vote link BW as avg (a peak vote pinned DDR >= 2 GHz while the link idles)
    { name = "pcie-x1e-power"; patch = ../pcie-x1e-power.patch; }
    # a6xx_rpmh_stop had an inverted GMU_STATUS_FW_START check: GPU RSC never slept after GMU use,
    # its RPMh votes blocked CXSD/DDR LPM in s2idle (2026-10-02)
    { name = "gmu-rpmh-stop"; patch = ../gmu-rpmh-stop.patch; }
    { name = "lpass-macro-rpm"; patch = ../lpass-macro-rpm.patch; }
    # runtime idle must not enter DRIPS (Windows PEP vetoes it while the screen is on); s2idle still does
    { name = "pmdomain-system-sleep-only"; patch = ../pmdomain-system-sleep-only.patch; }
    { name = "dt-ss1"; patch = ../dt-ss1.patch; }
    # panel 3.3 V was always-on, stayed powered in s2idle (2026-10-03 test)
    { name = "dt-edp-off"; patch = ../dt-edp-off.patch; }
    # BT UART (hci_uart keeps it open) kept clocks/ICC/CX votes in s2idle -> no CXSD/AOSD (2026-10-03).
    # Was our own geni-serial-s2idle.patch; now the upstream fix d0cd9c8d0fd5 (Praveen Talari).
    { name = "serial-qcom-geni-upstream"; patch = ../serial-qcom-geni-upstream.patch; }
    # SoundWire: wait for the IRQ thread before gating hclk (bus clash -> WSA8845 UNATTACHED), Oleg Keri
    { name = "soundwire-qcom-irq-sync"; patch = ../soundwire-qcom-irq-sync.patch; }
  ];

  # USB controllers, xHCI and USB PHYs default to power/control=on (runtime PM forbidden), so all
  # four dwc3 + PHYs stay powered with nothing plugged in. Let them runtime-suspend (2026-09-29).
  services.udev.extraRules = ''
    ACTION=="add|bind", SUBSYSTEM=="platform", DRIVER=="dwc3-qcom|xhci-hcd|qcom-qmp-combo-phy|qcom-qmp-usb-phy", ATTR{power/control}="auto"
    # memlat "remote" devfreq polls CPUCP over SCMI every 2 ms per device (~900 mailbox IRQs/s at
    # idle) only to read back the frequency CPUCP already chose. Voting happens in CPUCP, so stop
    # the polling (2026-10-01).
    ACTION=="add", SUBSYSTEM=="devfreq", KERNEL=="ddr|ddr-qos|llcc", ATTR{polling_interval}="0"
  '';

  boot.kernelParams = [ "asus_vivobook_s15.disable_standby_timer=1"
    "no_console_suspend"  # DEBUG with ramoops: log s2idle to pstore
    # EXPERIMENT 2026-09-29: clk_ignore_unused / pd_ignore_unused removed so Linux turns off what UEFI left on
    # (display/PCIe RSCC clocks etc.). Restore both lines if something breaks at boot.
    # "clk_ignore_unused"
    # "pd_ignore_unused"
    "systemd.tpm2_wait=0"
    "id_aa64mmfr0.ecv=1"
    # EFI runtime services are unreliable on X1E: no efivars, no RTC via EFI
    "efi=noruntime"
    "cma=192M"
    "pcie_aspm.policy=powersupersave"
    "mem_sleep_default=s2idle"
    "console=tty0"
    # Panel Self Refresh: the SDC OLED reports PSR1 (DPCD 0x070=0x01), msm keeps PSR behind a
    # param that defaults off. With PSR the display pipeline stops scanning out DDR when the
    # screen is static (2026-10-01, gen 85). Disabled 2026-10-03: with PSR the frame the panel
    # keeps during self refresh gets green underrun stripes (DPU drops its bandwidth vote to 0/0
    # on self-refresh entry; visible since the GMU fix lets DDR clock down). Costs ~0.5 W idle.
    "msm.psr_enabled=0"
    # s2idle: the Micron DRAM-less SSD otherwise stays in D0 (APST), so
    # pcie-qcom keeps a 1 kB/s DDR vote in the RPMh sleep set and DDR/CX
    # never collapse. simple_suspend shuts the controller down instead.
    "nvme.quirks=1344:5413:simple_suspend"
    # The root ports claim hot-plug (pciehp binds), which keeps them in D0 in
    # s2idle: the link then stays up and pcie-qcom keeps the DDR vote.
    "pcie_port_pm=force"
    # Interconnect providers drop their boot-time INT_MAX votes only in
    # sync_state(); with qcrypto blacklisted (below) 1dfa000.crypto never
    # probes, so without this the buses would stay at max forever.
    "fw_devlink.sync_state=timeout"
  ];

  # QCE (hardware crypto) holds an always-on DDR bandwidth vote, also in
  # s2idle, which keeps DDR out of self-refresh. ARMv8 CE does the crypto.
  boot.blacklistedKernelModules = [ "qcrypto" ];

  hardware.deviceTree.enable = true;

  # 2026-10-02: the rsc-control-tcs overlay (CONTROL_TCS=1, Linux writes the
  # APSS RSC wake timer) was removed: under s2idle it writes a stale
  # next_hrtimer deadline. Added 2026-09-28 while the GPU still blocked DRIPS.
  hardware.deviceTree.overlays = [{
    # DEBUG (2026-09-29): 2 MiB pstore/ramoops buffer so the kernel log survives a reset
    # during s2idle resume. Read after reboot: /sys/fs/pstore/console-ramoops-0
    name = "ramoops";
    filter = "x1e80100-asus-vivobook-s15";
    dtsText = ''
      /dts-v1/;
      /plugin/;
      / { compatible = "asus,vivobook-s15"; };
      &{/reserved-memory} {
        ramoops@c00000000 {
          compatible = "ramoops";
          reg = <0xc 0x00000000 0x0 0x200000>;
          no-map;
          record-size = <0x20000>;
          console-size = <0x100000>;
          pmsg-size = <0x20000>;
        };
      };
    '';
  } {
    # EXPERIMENT 2026-09-29: both USB-C PHY sets share L2J (1.2 V) and L3J (0.8 V) with only eDP/NVMe PHYs.
    # With USB wakeup off on both USB-C controllers they switch fully off in suspend and the SoC resets or
    # hangs; Windows keeps LDO2_J/LDO3_J on (LPM) while USB is wake-armed. Test: keep them always on.
    name = "usbc-ldo-always-on";
    filter = "x1e80100-asus-vivobook-s15";
    dtsText = ''
      /dts-v1/;
      /plugin/;
      / { compatible = "asus,vivobook-s15"; };
      &{/soc@0/rsc@17500000/regulators-7/ldo2} { regulator-always-on; };
      &{/soc@0/rsc@17500000/regulators-7/ldo3} { regulator-always-on; };
    '';
  } {
    # Outbound SMP2P "sleepstate" item to the ADSP: Windows (qcsubsys) writes 0x1000 when the ADSP
    # is up and 0 on Modern Standby entry. Consumer: asus_adsp_sleepstate (modules/adsp-sleepstate).
    name = "adsp-sleepstate";
    filter = "x1e80100-asus-vivobook-s15";
    dtsText = ''
      /dts-v1/;
      /plugin/;
      / { compatible = "asus,vivobook-s15"; };
      &{/smp2p-adsp} {
        sleepstate_smp2p_out: sleepstate-out {
          qcom,entry-name = "sleepstate";
          #qcom,smem-state-cells = <1>;
        };
      };
      &{/} {
        adsp-sleepstate {
          compatible = "asus,adsp-sleepstate";
          qcom,smem-states = <&sleepstate_smp2p_out 0>;
          qcom,smem-state-names = "sleepstate";
        };
      };
    '';
  }];

  # Some module from the list above isn't built by this kernel config
  nixpkgs.overlays = [
    (final: super: {
      makeModulesClosure = x: super.makeModulesClosure (x // { allowMissing = true; });
    })
  ];

  boot.initrd.kernelModules = initrdModules;
  boot.initrd.availableKernelModules = initrdModules;

  hardware.enableRedistributableFirmware = true;
  hardware.firmware = [ asusFirmware ];

  # fan-profile            -> show (current one in brackets)
  # fan-profile whisper|standard|performance|full
  environment.systemPackages = [
    (pkgs.writeShellScriptBin "fan-profile" ''
      f=$(echo /sys/bus/i2c/drivers/asus_vivobook_ec/*/fan_profile)
      [ -e "$f" ] || { echo "asus_vivobook_ec not loaded" >&2; exit 1; }
      if [ $# -eq 0 ]; then cat "$f"; else echo "$1" > "$f" && cat "$f"; fi
    '')
  ];

#  specialisation.mainline.configuration = {
#    system.nixos.tags = [ "mainline" ];
#    boot.kernelPackages = lib.mkForce (kernelPkgs.linuxPackagesFor mainlineKernel);
#    boot.kernelPatches = lib.mkForce mainlinePatches;
#    # DEBUG: Wi-Fi (pcie4) link never comes up on 7.3
#    boot.kernelParams = [ "dyndbg=\"file drivers/pci/pwrctrl/* +p; file drivers/pci/controller/dwc/* +p; file drivers/power/sequencing/* +p\"" ];
#  };

  # HDR10 on the internal OLED (ATNA56AC03: PQ, BT.2020, ~620 nit): drivers/gpu/drm/msm/dp taken
  # from v7.3-rc5 + "drm/msm/dp: Add static HDR support for DP and eDP" v2 (Xilin Wu, 2026-10-09)
  # + its 2 linux-next prerequisites, ported to 7.2 (bridge atomic_reset API, max bpc needs a
  # connector state, jglathe's delayed DP clock defaults kept). Separate boot entry; default unchanged.
  specialisation.hdr.configuration = {
    boot.kernelPatches = [ { name = "msm-dp-hdr"; patch = ../msm-dp-hdr.patch; } ];
  };
}

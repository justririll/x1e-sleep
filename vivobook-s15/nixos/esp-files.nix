# Files that have to sit on the ESP for EL2 boot: systemd-boot EFI drivers
# (slbounce switches to EL2 when the entry's DTB is an -el2 one, qebspil starts
# the DSPs from the firmware below), and tcblaunch.exe that slbounce needs.
# Returns { "<path on ESP>" = <source>; }.
{ pkgs }:

let
  fw = ../el2-stuff/firmware/qcom/x1e80100/ASUSTeK/vivobook-s15;
  fwFiles = builtins.attrNames (builtins.readDir fw);
in
{
  "EFI/systemd/drivers/slbounceaa64.efi" = pkgs.fetchurl {
    url = "https://github.com/TravMurav/slbounce/releases/download/v5/slbounce.efi";
    hash = "sha256-lsiaBqE5ueOc759SiWoaLIzVQ30P7u+ypcfqWzVhThc=";
  };
  # qebspil v1 (8e4d9e6) + QMP load_state off/on for adsp/cdsp before
  # auth_and_reset (el2-stuff/qebspil-qmp.diff + qebspil-qmp.c as src/qmp.c);
  # without it the ADSP dies after the first DDR LPM.
  "EFI/systemd/drivers/qebspilaa64.efi" = ../el2-stuff/qebspilaa64-qmp.efi;
  "tcblaunch.exe" = ../el2-stuff/tcblaunch.exe;
}
// builtins.listToAttrs (map (f: {
  name = "firmware/qcom/x1e80100/ASUSTeK/vivobook-s15/${f}";
  value = "${fw}/${f}";
}) fwFiles)

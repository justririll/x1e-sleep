#!/bin/sh
# Log battery energy and AOP sleep counters around every suspend: sleep-log.sh pre|post
B=/sys/class/power_supply/qcom-battmgr-bat
S=/sys/kernel/debug/qcom_stats
AWK=${AWK:-awk}
L=/var/log/sleep-energy.log
st() { for f in ddr cxsd aosd; do $AWK -v n=$f "/Accum/{printf \" %s=%.1f\", n, \$3/19200000}" $S/$f 2>/dev/null; done; }
if [ "$1" = post ]; then
  p1=$(cat $B/power_now); sleep 2; p2=$(cat $B/power_now)
  echo "post $(date +%s) e=$(cat $B/energy_now) p_now=$p1,$p2$(st)" >> $L
else
  echo "pre  $(date +%s) e=$(cat $B/energy_now) st=$(cat $B/status)$(st)" >> $L
fi

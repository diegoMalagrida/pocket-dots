#!/usr/bin/env bash
# Emits every ~1.5 s:
# cpu mem bat ac bright vol muted nightlight disk mem_used_kib mem_total_kib
# disk_used_bytes disk_total_bytes cpu_temp_mC load1 uptime_s cpu_threads
#
# The first nine fields are the shell's historical contract. The rest feed the
# performance panel without opening another parallel polling loop.
pt=0; pi=0
threads=$(getconf _NPROCESSORS_ONLN 2>/dev/null); [ -z "$threads" ] && threads=1

# FALLBACK temperature sensor, resolved only once (the loop below runs every
# 1.5 s and this does not change for the whole session).
#
# The thermal_zone search inside the loop only knows x86_pkg_temp and TCPU,
# which belong to this Intel. An AMD publishes neither: its sensor is called
# k10temp (or zenpower on boards with the separate module) and lives in hwmon,
# not in thermal_zone. Without this fallback, on any machine other than this
# laptop the temperature card in the performance panel said "Sin lectura"
# (no reading) forever and the graph drew nothing.
hwtemp=""
for hw in /sys/class/hwmon/hwmon*; do
  [ -r "$hw/name" ] || continue
  case "$(<"$hw/name")" in
    k10temp|zenpower|coretemp)
      [ -r "$hw/temp1_input" ] && hwtemp="$hw/temp1_input" && break ;;
  esac
done
# Brightness (%): ONE single read, outside the loop. ShellState only consumes
# this value the first time (if bright < 0); after that the shell itself keeps
# the brightness up to date on every key press, so polling it every 1.5 s was a
# brightnessctl fork thrown away.
#
# The `-c backlight` is NOT decoration. Without a class, brightnessctl walks
# the classes in order -- backlight first, leds after -- and keeps the first
# one that has any device. On a machine with no internal panel (a tower) there
# is no backlight at all, so it FALLS BACK TO THE LEDS and publishes the state
# of the caps-lock or wifi led as "screen brightness": a 0 or a 100 that on top
# of that brought the Control Centre slider back to life with a false value.
# With the class pinned, no panel means no reading, `br` stays at -1 and the
# slider disappears.
br=$(brightnessctl -c backlight -m 2>/dev/null | awk -F, 'NR==1{gsub("%","",$4); print $4}'); [ -z "$br" ] && br=-1
while true; do
  # CPU
  read -r _ u ni sy idl io ir sq _ < /proc/stat
  tot=$((u+ni+sy+idl+io+ir+sq)); idle=$((idl+io))
  if [ "$pt" -ne 0 ]; then
    dt=$((tot-pt)); di=$((idle-pi))
    if [ "$dt" -gt 0 ]; then cpu=$(( (100*(dt-di))/dt )); else cpu=0; fi
  else cpu=0; fi
  pt=$tot; pi=$idle
  # RAM
  mt=$(awk '/MemTotal/{print $2}' /proc/meminfo)
  ma=$(awk '/MemAvailable/{print $2}' /proc/meminfo)
  if [ -n "$mt" ] && [ "$mt" -gt 0 ]; then
    mu=$((mt-ma))
    mem=$(( (100*mu)/mt ))
  else
    mt=0; mu=0; mem=0
  fi
  # Battery / AC
  bat=$(cat /sys/class/power_supply/BAT*/capacity 2>/dev/null | head -1); [ -z "$bat" ] && bat=-1
  ac=$(cat /sys/class/power_supply/A[CD]*/online 2>/dev/null | head -1); [ -z "$ac" ] && ac=0
  # Without a battery there is no AC*/ADP* to read, and the `ac=0` fallback
  # literally means "running on battery": a tower plugged into the wall was
  # described as an unplugged laptop. It does not show today because everything
  # that paints the power state requires `bat >= 0`, but it is a FALSE value
  # waiting for someone to read it. With no battery, mains power is a fact.
  [ "$bat" -lt 0 ] && ac=1
  # Volume/mute and night light: fixed placeholders. Nobody reads them from here —
  # volume and mute come from the native Pipewire binding in ShellState and the
  # night light from its own toggle. The columns are kept so as not to shift
  # p[8..16]. (They used to be a wpctl + a pgrep per tick, thrown away.)
  vol=-1; mut=0
  nl=0
  read -r du ds dsk < <(df -B1 --output=used,size,pcent / 2>/dev/null | tail -1)
  dsk=${dsk%%%}; [ -z "$du" ] && du=0; [ -z "$ds" ] && ds=0; [ -z "$dsk" ] && dsk=0

  # Package temperature without invoking `sensors` every second. On this Intel
  # x86_pkg_temp is the good reading; TCPU stays as a fallback for other ACPI.
  temp=-1; tcpu=-1
  for zone in /sys/class/thermal/thermal_zone*; do
    [ -r "$zone/type" ] && [ -r "$zone/temp" ] || continue
    ztype=$(<"$zone/type")
    if [ "$ztype" = "x86_pkg_temp" ]; then temp=$(<"$zone/temp"); break; fi
    [ "$ztype" = "TCPU" ] && tcpu=$(<"$zone/temp")
  done
  [ "$temp" -lt 0 ] && temp=$tcpu
  if [ "$temp" -lt 0 ] && [ -n "$hwtemp" ]; then temp=$(<"$hwtemp"); fi

  load1=$(awk '{print $1}' /proc/loadavg)
  up=$(awk '{print int($1)}' /proc/uptime)
  echo "$cpu $mem $bat $ac $br $vol $mut $nl $dsk $mu $mt $du $ds $temp $load1 $up $threads"
  sleep 1.5
done

#!/usr/bin/env bash
# Emite cada ~1.5 s:
# cpu mem bat ac bright vol muted nightlight disk mem_used_kib mem_total_kib
# disk_used_bytes disk_total_bytes cpu_temp_mC load1 uptime_s cpu_threads
#
# Los nueve primeros campos son el contrato histórico del shell. Los demás
# alimentan el panel de rendimiento sin abrir otro bucle de sondeo paralelo.
pt=0; pi=0
threads=$(getconf _NPROCESSORS_ONLN 2>/dev/null); [ -z "$threads" ] && threads=1

# Sensor de temperatura de RESPALDO, resuelto una sola vez (el bucle de abajo
# corre cada 1,5 s y esto no cambia en toda la sesion).
#
# La busqueda de thermal_zone que hay dentro del bucle solo conoce x86_pkg_temp
# y TCPU, que son de este Intel. Un AMD no publica ninguno de los dos: su sensor
# se llama k10temp (o zenpower en placas con el modulo aparte) y vive en hwmon,
# no en thermal_zone. Sin este respaldo, en cualquier equipo que no fuera este
# portatil la tarjeta de temperatura del panel de rendimiento decia "Sin
# lectura" para siempre y la grafica no dibujaba nada.
hwtemp=""
for hw in /sys/class/hwmon/hwmon*; do
  [ -r "$hw/name" ] || continue
  case "$(<"$hw/name")" in
    k10temp|zenpower|coretemp)
      [ -r "$hw/temp1_input" ] && hwtemp="$hw/temp1_input" && break ;;
  esac
done
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
  # Batería / AC
  bat=$(cat /sys/class/power_supply/BAT*/capacity 2>/dev/null | head -1); [ -z "$bat" ] && bat=-1
  ac=$(cat /sys/class/power_supply/A[CD]*/online 2>/dev/null | head -1); [ -z "$ac" ] && ac=0
  # Sin bateria no hay AC*/ADP* que leer, y el respaldo `ac=0` significa
  # literalmente "funcionando con bateria": una torre enchufada a la pared
  # quedaba descrita como un portatil desenchufado. Hoy no se ve porque todo lo
  # que pinta el estado electrico exige `bat >= 0`, pero es un dato FALSO
  # esperando a que alguien lo lea. Si no hay bateria, la corriente es un hecho.
  [ "$bat" -lt 0 ] && ac=1
  # Brillo (%)
  #
  # El `-c backlight` NO es adorno. Sin clase, brightnessctl recorre las clases
  # en orden -- backlight primero, leds despues -- y se queda con la primera que
  # tenga algun dispositivo. En un equipo sin panel interno (una torre) no hay
  # ningun backlight, asi que CAE A LOS LEDS y publica como "brillo de pantalla"
  # el estado del led de bloq-mayus o del wifi: un 0 o un 100 que ademas
  # resucitaba el slider del centro de control con un valor falso. Con la clase
  # fijada, sin panel no hay lectura, `br` se queda en -1 y el slider desaparece.
  br=$(brightnessctl -c backlight -m 2>/dev/null | awk -F, 'NR==1{gsub("%","",$4); print $4}'); [ -z "$br" ] && br=-1
  # Volumen + mute (wpctl)
  vraw=$(wpctl get-volume @DEFAULT_AUDIO_SINK@ 2>/dev/null)
  vol=$(printf '%s' "$vraw" | awk '{print int($2*100+0.5)}'); [ -z "$vol" ] && vol=-1
  mut=0; printf '%s' "$vraw" | grep -q MUTED && mut=1
  # Luz nocturna
  nl=0; pgrep -x hyprsunset >/dev/null 2>&1 && nl=1
  read -r du ds dsk < <(df -B1 --output=used,size,pcent / 2>/dev/null | tail -1)
  dsk=${dsk%%%}; [ -z "$du" ] && du=0; [ -z "$ds" ] && ds=0; [ -z "$dsk" ] && dsk=0

  # Temperatura del paquete sin invocar `sensors` cada segundo. En este Intel
  # x86_pkg_temp es la lectura buena; TCPU queda como respaldo para otros ACPI.
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

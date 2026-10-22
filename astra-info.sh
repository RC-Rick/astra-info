#!/usr/bin/env bash
# ---------------------------------------------------------
# Скрипт:       astra-info.sh
# Назначение:   Скрипт с кратким выводом полезной информации о машине в ASCII-таблицах
# Автор:        RC-Rick
# Версия:       0.1
# Дата создания: 2026-08-25
# Обновлено:    2026-08-25
#
# Использование: sudo bash astra-info.sh
#
# Важно: 
#   [!] Запускать от root или через sudo!
# ---------------------------------------------------------


#C-locale специально, чтобы сортировка, числа и рамки были предсказуемыми!!
export LC_ALL=C

#Добавляем sbin-пути, чтобы видеть ip, ifconfig и т.п. даже не от root.
export PATH="${PATH:+$PATH:}/usr/sbin:/usr/local/sbin:/sbin"

#Разделитель колонок внутри скрипта: TAB.
DELIM=$'\t'

#Максимальная ширина одной колонки, чтобы длинные значения не рвали таблицу.
TABLE_MAX_WIDTH=70

green='\033[0;32m'
red='\033[0;31m'
blue='\033[0;36m'
reset='\033[0m'
orange='\033[0;33m'
pur='\033[0;35m'

# ---------------------------------------------------------------------------
# Вспомогательные функции
# ---------------------------------------------------------------------------

trim() {
  local s=$1
  s=${s#"${s%%[![:space:]]*}"}
  s=${s%"${s##*[![:space:]]}"}
  printf '%s' "$s"
}

join_fields() {
  local out="" sep="" a
  for a in "$@"; do
    a=${a//$'\n'/ }
    a=${a//$'\r'/ }
    a=${a//$DELIM/ }
    out+="${sep}${a}"
    sep=$DELIM
  done
  printf '%s' "$out"
}

file_first() {
  if [ -f "$1" ] && [ -r "$1" ]; then
    head -n 1 "$1" 2>/dev/null | tr -d '\r\n'
  fi
}

os_release() {
  local key=$1 val
  val=$(sed -n "s/^${key}=//p" /etc/os-release 2>/dev/null | head -n 1)
  val=$(trim "$val")
  val=${val#\"}
  val=${val%\"}
  printf '%s' "$val"
}

get_short_astra_version() {
  local v=$1 major minor

  v=$(trim "$v")

  if [ -z "$v" ]; then
    printf 'n/a'
    return
  fi

  IFS=. read -r major minor _ <<<"$v"

  if [ -n "$major" ] && [ -n "$minor" ]; then
    printf '%s.%s' "$major" "$minor"
  else
    printf '%s' "$v"
  fi
}

get_astra_version() {
  local v f first

  for f in /etc/astra_version /etc/astra-version; do
    v=$(trim "$(file_first "$f")")
    if [ -n "$v" ]; then
      printf '%s' "$v"
      return
    fi
  done

  v=$(trim "$(file_first /etc/astra/build_version)")
  if [ -n "$v" ]; then
    get_short_astra_version "$v"
    return
  fi

  v=$(trim "$(file_first /etc/astra/ext_version)")
  if [ -n "$v" ]; then
    get_short_astra_version "$v"
    return
  fi

  v=$(os_release VERSION_ID)
  v=$(trim "$v")
  if [ -n "$v" ]; then
    printf '%s' "$v"
    return
  fi

  v=$(os_release VERSION)
  v=$(trim "$v")
  if [ -n "$v" ]; then
    first=${v%% *}
    if [[ $first =~ ^[0-9]+\.[0-9]+ ]]; then
      get_short_astra_version "$first"
    else
      printf '%s' "$v"
    fi
    return
  fi

  if command -v lsb_release >/dev/null 2>&1; then
    v=$(lsb_release -rs 2>/dev/null | tr -d '"')
    v=$(trim "$v")
    if [ -n "$v" ]; then
      printf '%s' "$v"
      return
    fi
  fi

  printf 'n/a'
}

get_astra_update() {
  local v f

  v=$(trim "$(file_first /etc/astra/build_version)")
  if [ -n "$v" ]; then
    printf '%s' "$v"
    return
  fi

  v=$(trim "$(file_first /etc/astra/ext_build_version)")
  if [ -n "$v" ]; then
    printf '%s' "$v"
    return
  fi

  v=$(trim "$(file_first /etc/astra/ext_version)")
  if [ -n "$v" ]; then
    printf '%s' "$v"
    return
  fi

  for f in /etc/astra_update \
    /etc/astra-update \
    /etc/astra_update_version \
    /etc/astra-update-version \
    /etc/astra_update_number \
    /etc/astra-update-number \
    /etc/astra_sm_update \
    /etc/astra_sm/update \
    /etc/astra_release \
    /etc/astra_release_info; do
    if [ -f "$f" ] && [ -r "$f" ]; then
      v=$(trim "$(file_first "$f")")
      if [ -n "$v" ]; then
        printf '%s' "$v"
        return
      fi
    fi
  done

  if command -v astra-version >/dev/null 2>&1; then
    v=$(astra-version --update 2>/dev/null | head -n 1 | tr -d '\r\n')
    v=$(trim "$v")
    if [ -n "$v" ]; then
      printf '%s' "$v"
      return
    fi
  fi

  if command -v dpkg >/dev/null 2>&1; then
    v=$(dpkg -l 'astra-update*' 2>/dev/null | awk '/^ii/ {print $2 "=" $3; exit}')
    v=$(trim "$v")
    if [ -n "$v" ]; then
      printf '%s' "$v"
      return
    fi
  fi

  printf 'n/a'
}

meminfo_kb() {
  awk -v k="$1" '$1 == k":" {print $2; exit}' /proc/meminfo 2>/dev/null
}

human_kb() {
  local kb=${1:-0}
  [[ $kb =~ ^[0-9]+$ ]] || kb=0

  if ! command -v awk >/dev/null 2>&1; then
    printf '%s KiB' "$kb"
    return
  fi

  LC_ALL=C awk -v kb="$kb" 'BEGIN {
        if (kb < 1024) {
            printf "%d KiB", kb
            exit
        }

        split("MiB GiB TiB PiB", u, " ")
        v = kb / 1024
        i = 1

        while (v >= 1024 && i < 4) {
            v /= 1024
            i++
        }

        printf "%.1f %s", v, u[i]
    }'
}

get_default_gw() {
  local gw="" hex

  if command -v ip >/dev/null 2>&1; then
    gw=$(ip -4 route show default 2>/dev/null | awk '/default/ {print $3; exit}')
  fi

  if [ -z "$gw" ] && [ -r /proc/net/route ]; then
    hex=$(awk '$2 == "00000000" {print $3; exit}' /proc/net/route 2>/dev/null)
    if [ -n "$hex" ] && [ "$hex" != "00000000" ]; then
      printf -v gw '%d.%d.%d.%d' \
        "0x${hex:6:2}" \
        "0x${hex:4:2}" \
        "0x${hex:2:2}" \
        "0x${hex:0:2}" 2>/dev/null || gw=""
    fi
  fi

  [ -z "$gw" ] && gw="n/a"
  printf '%s' "$gw"
}

draw_table() {
  local title=$1 header=$2
  shift 2
  local -a rows=("$@")

  if [ ${#rows[@]} -eq 0 ]; then
    rows=("n/a")
  fi

  local -a all=("$header")
  all+=("${rows[@]}")

  local -a widths=() cols
  local maxcols=0 row i len cell w
  local maxw=$TABLE_MAX_WIDTH

  for row in "${all[@]}"; do
    IFS=$DELIM read -r -a cols <<<"$row"

    if [ "${#cols[@]}" -gt "$maxcols" ]; then
      maxcols=${#cols[@]}
    fi

    for i in "${!cols[@]}"; do
      cell=${cols[i]}
      len=${#cell}

      if [ "$len" -gt "$maxw" ]; then
        len=$maxw
      fi

      if [ "$i" -ge "${#widths[@]}" ]; then
        widths[i]=$len
      elif [ "$len" -gt "${widths[i]}" ]; then
        widths[i]=$len
      fi
    done
  done

  for ((i = 0; i < maxcols; i++)); do
    if [ "$i" -ge "${#widths[@]}" ]; then
      widths[i]=1
    fi

    if [ "${widths[i]}" -lt 1 ]; then
      widths[i]=1
    fi
  done

  local sep="+" total=1
  for ((i = 0; i < maxcols; i++)); do
    w=${widths[i]}
    sep+=$(printf '%*s' $((w + 2)) '' | tr ' ' '-')
    sep+="+"
    total=$((total + w + 3))
  done

  local max_title=$((total - 4))

  printf '%s\n' "$sep"

  if [ -n "$title" ] && [ "$max_title" -gt 0 ]; then
    local t=$title
    if [ ${#t} -gt "$max_title" ]; then
      t=${t:0:max_title}
    fi
    printf '| %-*s |\n' "$max_title" "$t"
    printf '%s\n' "$sep"
  fi

  IFS=$DELIM read -r -a cols <<<"$header"
  local line="|"

  for ((i = 0; i < maxcols; i++)); do
    cell=${cols[i]:-}
    w=${widths[i]}

    if [ ${#cell} -gt "$w" ]; then
      if [ "$w" -gt 3 ]; then
        cell="${cell:0:w-3}..."
      else
        cell="${cell:0:w}"
      fi
    fi

    line+=$(printf ' %-*s |' "$w" "$cell")
  done

  printf '%s\n' "$line"
  printf '%s\n' "$sep"

  for row in "${rows[@]}"; do
    IFS=$DELIM read -r -a cols <<<"$row"
    line="|"

    for ((i = 0; i < maxcols; i++)); do
      cell=${cols[i]:-}
      w=${widths[i]}

      if [ ${#cell} -gt "$w" ]; then
        if [ "$w" -gt 3 ]; then
          cell="${cell:0:w-3}..."
        else
          cell="${cell:0:w}"
        fi
      fi

      line+=$(printf ' %-*s |' "$w" "$cell")
    done

    printf '%s\n' "$line"
  done

  printf '%s\n' "$sep"
  printf '\n'
}

# ---------------------------------------------------------------------------
# Сбор данных
# ---------------------------------------------------------------------------

now=$(date '+%Y-%m-%d %H:%M:%S %Z' 2>/dev/null || date)
host=$(hostname 2>/dev/null || cat /proc/sys/kernel/hostname 2>/dev/null || echo n/a)

os_pretty=$(os_release PRETTY_NAME)

if [ -z "$os_pretty" ] && command -v lsb_release >/dev/null 2>&1; then
  os_pretty=$(lsb_release -ds 2>/dev/null | tr -d '"')
fi

if [ -z "$os_pretty" ]; then
  if [ -r /etc/astra_version ]; then
    os_pretty="Astra Linux $(file_first /etc/astra_version)"
  elif [ -r /etc/debian_version ]; then
    os_pretty="Debian $(file_first /etc/debian_version)"
  else
    os_pretty=$(uname -s 2>/dev/null || echo Unknown)
  fi
fi

astra_version=$(get_astra_version)
astra_update=$(get_astra_update)
astra_ext_build=$(trim "$(file_first /etc/astra/ext_build_version)")
astra_ext_version=$(trim "$(file_first /etc/astra/ext_version)")

[ -z "$astra_ext_build" ] && astra_ext_build="n/a"
[ -z "$astra_ext_version" ] && astra_ext_version="n/a"

debian_version=$(file_first /etc/debian_version)
[ -z "$debian_version" ] && debian_version="n/a"

kernel=$(uname -r 2>/dev/null || echo n/a)
arch=$(uname -m 2>/dev/null || echo n/a)

init=$(file_first /proc/1/comm)
[ -z "$init" ] && init="n/a"

btime=$(awk '/^btime/ {print $2; exit}' /proc/stat 2>/dev/null)
boot_time="n/a"
if [ -n "$btime" ]; then
  boot_time=$(date -d "@$btime" '+%Y-%m-%d %H:%M:%S' 2>/dev/null || echo n/a)
fi

uptime_s=$(cut -d. -f1 /proc/uptime 2>/dev/null)
[ -z "$uptime_s" ] && uptime_s=0

days=$((uptime_s / 86400))
hours=$((uptime_s % 86400 / 3600))
mins=$((uptime_s % 3600 / 60))
uptime_str="${days}d ${hours}h ${mins}m"

loadavg=$(cut -d' ' -f1-3 /proc/loadavg 2>/dev/null || echo n/a)

proc_count=0
for p in /proc/[0-9]*; do
  [ -d "$p" ] && proc_count=$((proc_count + 1))
done

# ---------------------------------------------------------------------------
# Пользователи
# ---------------------------------------------------------------------------

user_rows=()
logged_count=0

if command -v who >/dev/null 2>&1; then
  while read -r u t d tm rest; do
    [ -z "$u" ] && continue

    rest=${rest#(}
    rest=${rest%)}
    [ -z "$rest" ] && rest="-"

    user_rows+=("$(join_fields "$u" "$t" "$rest" "$d $tm")")
    logged_count=$((logged_count + 1))
  done < <(who 2>/dev/null)
fi

if [ "$logged_count" -eq 0 ]; then
  user_rows=("$(join_fields "-" "-" "-" "no active sessions")")
fi

# ---------------------------------------------------------------------------
# Память
# ---------------------------------------------------------------------------

mem_total=$(meminfo_kb MemTotal)
mem_total=${mem_total:-0}
mem_free=$(meminfo_kb MemFree)
mem_free=${mem_free:-0}
mem_avail=$(meminfo_kb MemAvailable)
mem_avail=${mem_avail:-0}
buffers=$(meminfo_kb Buffers)
buffers=${buffers:-0}
cached=$(meminfo_kb Cached)
cached=${cached:-0}

swap_total=$(meminfo_kb SwapTotal)
swap_total=${swap_total:-0}
swap_free=$(meminfo_kb SwapFree)
swap_free=${swap_free:-0}

if [ "$mem_avail" -gt 0 ]; then
  mem_used=$((mem_total - mem_avail))
else
  mem_used=$((mem_total - mem_free - buffers - cached))
fi

[ "$mem_used" -lt 0 ] && mem_used=0

swap_used=$((swap_total - swap_free))
[ "$swap_used" -lt 0 ] && swap_used=0

# ---------------------------------------------------------------------------
# CPU
# ---------------------------------------------------------------------------

cpu_model=$(sed -n 's/^model name[[:space:]]*:[[:space:]]*//p' /proc/cpuinfo 2>/dev/null | head -n 1)
[ -z "$cpu_model" ] && cpu_model=$(sed -n 's/^Hardware[[:space:]]*:[[:space:]]*//p' /proc/cpuinfo 2>/dev/null | head -n 1)
[ -z "$cpu_model" ] && cpu_model="n/a"

cpu_cores=$(grep -c '^processor' /proc/cpuinfo 2>/dev/null)
[ -z "$cpu_cores" ] && cpu_cores=1

# ---------------------------------------------------------------------------
# Железо / DMI
# ---------------------------------------------------------------------------

hw_vendor=$(file_first /sys/class/dmi/id/sys_vendor)
hw_product=$(file_first /sys/class/dmi/id/product_name)
hw_serial=$(file_first /sys/class/dmi/id/product_serial)
bios_vendor=$(file_first /sys/class/dmi/id/bios_vendor)
bios_version=$(file_first /sys/class/dmi/id/bios_version)

[ -z "$hw_vendor" ] && hw_vendor="n/a"
[ -z "$hw_product" ] && hw_product="n/a"
[ -z "$hw_serial" ] && hw_serial="n/a"
[ -z "$bios_vendor" ] && bios_vendor="n/a"
[ -z "$bios_version" ] && bios_version="n/a"

virt="n/a"

if grep -qw hypervisor /proc/cpuinfo 2>/dev/null; then
  virt="hypervisor flag present"
fi

case "$hw_product" in
*VirtualBox* | *VMware* | *KVM* | *QEMU* | *Xen* | *Bochs* | *OpenStack* | *EC2* | *Alibaba* | *Google* | *libvirt*)
  virt="VM: $hw_product"
  ;;
esac

if [ -r /sys/hypervisor/type ]; then
  hv=$(file_first /sys/hypervisor/type)
  [ -n "$hv" ] && virt="hypervisor: $hv"
fi

# ---------------------------------------------------------------------------
# Сеть
# ---------------------------------------------------------------------------

def_gw=$(get_default_gw)

dns=$(awk '/^nameserver/ {printf "%s%s", (n++ ? ", " : ""), $2}' /etc/resolv.conf 2>/dev/null)
[ -z "$dns" ] && dns="n/a"

all_ipv4=""
if command -v ip >/dev/null 2>&1; then
  all_ipv4=$(ip -4 -o addr show scope global 2>/dev/null | awk '{print $4}' | cut -d/ -f1 | paste -sd, -)
fi

if [ -z "$all_ipv4" ]; then
  all_ipv4=$(hostname -I 2>/dev/null | tr ' ' '\n' | grep -E '^[0-9]+\.[0-9]+\.[0-9]+\.[0-9]+$' | paste -sd, -)
fi

[ -z "$all_ipv4" ] && all_ipv4="n/a"

all_ipv6=""
if command -v ip >/dev/null 2>&1; then
  all_ipv6=$(ip -6 -o addr show scope global 2>/dev/null | awk '{print $4}' | cut -d/ -f1 | paste -sd, -)
fi

if [ -z "$all_ipv6" ]; then
  all_ipv6=$(hostname -I 2>/dev/null | tr ' ' '\n' | grep -E '^[0-9a-fA-F:]+$' | grep -F ':' | paste -sd, -)
fi

[ -z "$all_ipv6" ] && all_ipv6="n/a"

# ---------------------------------------------------------------------------
# Сетевые интерфейсы
# ---------------------------------------------------------------------------

net_rows=()

for path in /sys/class/net/*; do
  [ -e "$path" ] || continue

  iface=${path##*/}
  [ "$iface" = "lo" ] && continue

  state=$(file_first "$path/operstate")
  [ -z "$state" ] && state="unknown"

  mac=$(file_first "$path/address")
  [ -z "$mac" ] && mac="-"

  ipv4=""
  ipv6=""

  if command -v ip >/dev/null 2>&1; then
    ipv4=$(ip -4 -o addr show dev "$iface" scope global 2>/dev/null | awk '{print $4}' | cut -d/ -f1 | paste -sd, -)
    ipv6=$(ip -6 -o addr show dev "$iface" scope global 2>/dev/null | awk '{print $4}' | cut -d/ -f1 | paste -sd, -)
  elif command -v ifconfig >/dev/null 2>&1; then
    ipv4=$(ifconfig "$iface" 2>/dev/null | awk '/inet / {print $2}' | sed 's/^addr://' | cut -d/ -f1 | paste -sd, -)
  fi

  [ -z "$ipv4" ] && ipv4="-"
  [ -z "$ipv6" ] && ipv6="-"

  net_rows+=("$(join_fields "$iface" "$state" "$mac" "$ipv4" "$ipv6")")
done

if [ ${#net_rows[@]} -eq 0 ]; then
  net_rows=("$(join_fields "n/a" "n/a" "n/a" "$all_ipv4" "$all_ipv6")")
fi

# ---------------------------------------------------------------------------
# Файловые системы
# ---------------------------------------------------------------------------

disk_rows=()

if command -v df >/dev/null 2>&1; then
  if df -hPT >/dev/null 2>&1; then
    while read -r fs type size used avail pcent mount; do
      case "$type" in
      tmpfs | devtmpfs | devpts | sysfs | proc | cgroup* | efivarfs | ramfs | securityfs | debugfs | tracefs | pstore | bpf | autofs | mqueue | hugetlbfs | configfs | binfmt_misc | rpc_pipefs | nsfs | fuse.portal | fuse.gvfsd-fuse | fuse.lxcfs)
        continue
        ;;
      esac

      [ -z "$mount" ] && mount="/"

      disk_rows+=("$(join_fields "$fs" "$type" "$size" "$used" "$avail" "$pcent" "$mount")")
    done < <(df -hPT 2>/dev/null | tail -n +2)
  else
    while read -r fs size used avail pcent mount; do
      [ -z "$mount" ] && mount="/"
      disk_rows+=("$(join_fields "$fs" "-" "$size" "$used" "$avail" "$pcent" "$mount")")
    done < <(df -hP 2>/dev/null | tail -n +2)
  fi
fi

if [ ${#disk_rows[@]} -eq 0 ]; then
  disk_rows=("$(join_fields "n/a" "n/a" "n/a" "n/a" "n/a" "n/a" "df unavailable")")
fi

# ---------------------------------------------------------------------------
# Swap
# ---------------------------------------------------------------------------

swap_rows=()

if [ -r /proc/swaps ]; then
  while read -r fname ftype ssize sused sprio; do
    [ -z "$fname" ] && continue
    swap_rows+=("$(join_fields "$fname" "$ftype" "$(human_kb "$ssize")" "$(human_kb "$sused")" "$sprio")")
  done < <(tail -n +2 /proc/swaps 2>/dev/null)
fi

if [ ${#swap_rows[@]} -eq 0 ]; then
  swap_rows=("$(join_fields "none" "-" "0 KiB" "0 KiB" "-")")
fi

# ---------------------------------------------------------------------------
# Топ процессов, если доступен ps
# ---------------------------------------------------------------------------

top_cpu_rows=()
top_mem_rows=()

if command -v ps >/dev/null 2>&1; then
  while read -r pid user cpu mem comm; do
    [ -z "$pid" ] && continue
    top_cpu_rows+=("$(join_fields "$pid" "$user" "$cpu" "$mem" "$(trim "$comm")")")
  done < <(ps -eo pid,user,pcpu,pmem,comm 2>/dev/null | tail -n +2 | sort -k3,3nr | head -n 5)

  while read -r pid user cpu mem comm; do
    [ -z "$pid" ] && continue
    top_mem_rows+=("$(join_fields "$pid" "$user" "$cpu" "$mem" "$(trim "$comm")")")
  done < <(ps -eo pid,user,pcpu,pmem,comm 2>/dev/null | tail -n +2 | sort -k4,4nr | head -n 5)
fi

# ---------------------------------------------------------------------------
# Вывод
# ---------------------------------------------------------------------------

header_kv=$(join_fields "Parameter" "Value")

echo -e "${blue}"
draw_table "SYSTEM SUMMARY" "$header_kv" \
  "$(join_fields "Report time" "$now")" \
  "$(join_fields "Hostname" "$host")" \
  "$(join_fields "OS" "$os_pretty")" \
  "$(join_fields "Astra version" "$astra_version")" \
  "$(join_fields "Astra update / build" "$astra_update")" \
  "$(join_fields "Astra ext version" "$astra_ext_version")" \
  "$(join_fields "Astra ext build" "$astra_ext_build")" \
  "$(join_fields "Debian version" "$debian_version")" \
  "$(join_fields "Kernel" "$kernel")" \
  "$(join_fields "Architecture" "$arch")" \
  "$(join_fields "Init" "$init")" \
  "$(join_fields "Boot time" "$boot_time")" \
  "$(join_fields "Uptime" "$uptime_str")" \
  "$(join_fields "Load average" "$loadavg")" \
  "$(join_fields "Logged users" "$logged_count")" \
  "$(join_fields "Processes" "$proc_count")" \
  "$(join_fields "Virtualization" "$virt")"

echo -e "${green}"
draw_table "HARDWARE / RESOURCES" "$header_kv" \
  "$(join_fields "Vendor" "$hw_vendor")" \
  "$(join_fields "Product" "$hw_product")" \
  "$(join_fields "Serial" "$hw_serial")" \
  "$(join_fields "BIOS vendor" "$bios_vendor")" \
  "$(join_fields "BIOS version" "$bios_version")" \
  "$(join_fields "CPU model" "$cpu_model")" \
  "$(join_fields "CPU cores" "$cpu_cores")" \
  "$(join_fields "Memory total" "$(human_kb "$mem_total")")" \
  "$(join_fields "Memory used" "$(human_kb "$mem_used")")" \
  "$(join_fields "Memory available" "$(human_kb "$mem_avail")")" \
  "$(join_fields "Swap total" "$(human_kb "$swap_total")")" \
  "$(join_fields "Swap used" "$(human_kb "$swap_used")")"

echo -e "${blue}"
draw_table "NETWORK SUMMARY" "$header_kv" \
  "$(join_fields "Default gateway" "$def_gw")" \
  "$(join_fields "DNS servers" "$dns")" \
  "$(join_fields "IPv4 global" "$all_ipv4")" \
  "$(join_fields "IPv6 global" "$all_ipv6")"

echo -e "${orange}"
draw_table "NETWORK INTERFACES" \
  "$(join_fields Interface State MAC IPv4 IPv6)" \
  "${net_rows[@]}"

echo -e "${blue}"
draw_table "FILESYSTEM USAGE" \
  "$(join_fields Filesystem Type Size Used Avail Use% Mounted)" \
  "${disk_rows[@]}"

echo -e "${blue}"
draw_table "SWAP" \
  "$(join_fields Filename Type Size Used Priority)" \
  "${swap_rows[@]}"

echo -e "${green}"
draw_table "LOGGED IN USERS" \
  "$(join_fields User TTY Host Login time)" \
  "${user_rows[@]}"

if [ ${#top_cpu_rows[@]} -gt 0 ]; then
  echo -e "${blue}"
  draw_table "TOP 5 BY CPU" \
    "$(join_fields PID User CPU% MEM% Command)" \
    "${top_cpu_rows[@]}"
fi

if [ ${#top_mem_rows[@]} -gt 0 ]; then
  echo -e "${blue}"
  draw_table "TOP 5 BY MEMORY" \
    "$(join_fields PID User CPU% MEM% Command)" \
    "${top_mem_rows[@]}"
fi
echo -e "${reset}"
exit 0

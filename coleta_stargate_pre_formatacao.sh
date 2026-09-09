#!/usr/bin/env bash
set -u

OUT="${HOME}/stargate-audit-$(date +%Y%m%d-%H%M%S)"
mkdir -p "$OUT"

run() {
  local name="$1"
  shift
  {
    echo "# COMMAND: $*"
    echo
    "$@"
  } >"$OUT/$name.txt" 2>&1 || true
}

echo "Coletando diagnóstico SOMENTE LEITURA em: $OUT"

run 01-pvs sudo pvs
run 02-vgs sudo vgs
run 03-lvs sudo lvs -a -o +devices
run 04-lsblk lsblk -o NAME,MODEL,SIZE,TYPE,FSTYPE,MOUNTPOINTS
run 05-fstab cat /etc/fstab
run 06-cpu lscpu
run 07-processor-dmi sudo dmidecode --type processor
run 08-memory sudo dmidecode --type memory
run 09-net-ip ip -br addr
run 10-net-route ip route
run 11-netplan bash -lc 'sudo cat /etc/netplan/*.yaml'
run 12-resolver resolvectl status
run 13-ethtool-enp5s0 sudo ethtool -i enp5s0
run 14-ethtool-enp9s0 sudo ethtool -i enp9s0
run 15-ports sudo ss -tulpn
run 16-services-running systemctl --type=service --state=running
run 17-services-failed systemctl --failed
run 18-ufw sudo ufw status verbose
run 19-docker-ps docker ps -a
run 20-docker-images docker images
run 21-docker-volumes docker volume ls
run 22-docker-networks docker network ls
run 23-docker-stats docker stats --no-stream
run 24-ipmi-sel sudo ipmitool sel elist
run 25-ipmi-sel-info sudo ipmitool sel info
run 26-ipmi-chassis sudo ipmitool chassis status
run 27-ipmi-mc sudo ipmitool mc info
run 28-ipmi-power bash -lc 'sudo ipmitool sdr type "Power Supply"'
run 29-microcode-proc bash -lc 'grep -m1 microcode /proc/cpuinfo'
run 30-microcode-dmesg bash -lc 'sudo dmesg | grep -i microcode'
run 31-microcode-package apt-cache policy intel-microcode
run 32-packages-manual bash -lc 'apt-mark showmanual | sort'
run 33-git-global git config --global --list
run 34-crontab-user crontab -l
run 35-crontab-root sudo crontab -l
run 36-systemd-custom sudo find /etc/systemd/system -maxdepth 2 -type f -print

if command -v smartctl >/dev/null 2>&1; then
  run 37-smart-scan sudo smartctl --scan-open
  for i in 0 1 2; do
    run "38-smart-megaraid-$i" sudo smartctl -a -d "megaraid,$i" /dev/sda
  done
fi

if command -v lsscsi >/dev/null 2>&1; then
  run 39-lsscsi lsscsi -g
fi

if [ -d "$HOME/diario-de-dor-platform/.git" ]; then
  (
    cd "$HOME/diario-de-dor-platform" || exit
    run 40-diario-git-status git status
    run 41-diario-git-branch git branch --show-current
    run 42-diario-git-remote git remote -v
    if [ -f docker-compose.yml ] || [ -f compose.yml ] || [ -f compose.yaml ] || [ -f docker-compose.yaml ]; then
      run 43-diario-compose-ps docker compose ps
      run 44-diario-compose-services docker compose config --services
    fi
  )
fi

echo
echo "Concluído."
echo "Resultados em: $OUT"
echo
echo "ATENÇÃO: revise os arquivos antes de compartilhá-los."
echo "Não envie .env, chaves privadas, tokens ou senhas."

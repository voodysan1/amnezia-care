#!/usr/bin/env bash
# Read-only, bounded collector. stdout is retrieved by the Windows launcher.
set -uo pipefail
export LC_ALL=C
if ! command -v timeout >/dev/null; then
  printf 'ERROR: timeout is required; no packages installed.\n'; exit 1
fi
check() {
  local title=$1; shift
  printf '\n=== %s ===\n' "$title"
  timeout 20 "$@" 2>&1 | head -c 48000
  local rc=${PIPESTATUS[0]}
  printf '\nSTATUS %s: %s\n' "$title" "$rc"
}
printf 'Amnezia Care 1.0 | UTC: '; date -u +%FT%TZ
printf 'Reports contain network addresses; review before sharing. No keys/config dumps collected.\n'
check os uname -a
check uptime uptime
check memory free -m
check disk df -h
check interfaces ip -brief address
check counters ip -s link
check routes4 ip -4 route show table all
check routes6 ip -6 route show table all
check policy ip rule show
check forwarding sysctl net.ipv4.ip_forward net.ipv4.conf.all.rp_filter net.ipv4.conf.all.route_localnet
check listeners ss -lnut
check firewall4 iptables-save -c
check firewall6 ip6tables-save -c
check nft nft list ruleset
check resolver cat /etc/resolv.conf
check dnsmasq-upstream cat /etc/resolv.conf.dnsmasq
check services systemctl is-active x-ui warp-svc amnezia-smart-monitor.service
check containers docker ps --format '{{.Names}}\t{{.Status}}\t{{.Ports}}'
check bridges ip -d link show type bridge
if command -v docker >/dev/null; then
  while IFS= read -r container; do
    [[ "$container" =~ ^[a-zA-Z0-9_.-]+$ ]] || continue
    case "$container" in
      *amnezia*|*wireguard*|*wg-easy*)
        check "$container interfaces" docker exec "$container" ip -brief address
        check "$container routes" docker exec "$container" ip route show
        check "$container firewall" docker exec "$container" iptables-save -c
        check "$container aggregate-peers" docker exec "$container" sh -c '
          tool=""; command -v awg >/dev/null && tool=awg
          [ -n "$tool" ] || { command -v wg >/dev/null && tool=wg; }
          [ -n "$tool" ] || exit 127
          for i in $($tool show interfaces); do
            echo "interface=$i"
            $tool show "$i" latest-handshakes | awk -v now="$(date +%s)" '\''{n++;if($2>0){seen++;a=now-$2;if(a<=180)recent++}}END{printf "peers=%d ever_handshaken=%d recent_180s=%d\n",n,seen,recent}'\''
            $tool show "$i" transfer | awk '\''{r+=$2;t+=$3}END{printf "rx_bytes=%.0f tx_bytes=%.0f\n",r,t}'\''
          done'
        ;;
    esac
  done < <(timeout 10 docker ps --format '{{.Names}}' 2>/dev/null)
fi
if [[ "${1:-}" != "--skip-probes" ]]; then
  for domain in chatgpt.com claude.ai; do
    for resolver in 127.0.0.1 1.1.1.1; do
      check "DNS $domain $resolver" dig "@$resolver" "$domain" A +time=2 +tries=1 +noall +answer +comments
    done
    check "HTTPS $domain" curl -q -4 --noproxy '*' --connect-timeout 5 --max-time 12 -sS -o /dev/null -w 'ip=%{remote_ip} http=%{http_code} dns=%{time_namelookup} tcp=%{time_connect} tls=%{time_appconnect} total=%{time_total}\n' "https://$domain/"
  done
fi
printf '\nSUMMARY: inspect STATUS entries. FORWARD DROP alone is not proof of failure.\n'
printf 'Docker ACCEPT before custom filters can bypass them; review order, do not auto-rewrite.\n'
printf 'This VPS check does not measure subscriber speed or establish TSPU interference.\n'



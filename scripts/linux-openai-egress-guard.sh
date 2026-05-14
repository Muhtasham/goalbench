#!/usr/bin/env bash
set -euo pipefail

usage() {
  cat <<'EOF'
Usage:
  sudo scripts/linux-openai-egress-guard.sh apply <user>
  sudo scripts/linux-openai-egress-guard.sh proxy-apply <user>
  sudo scripts/linux-openai-egress-guard.sh delete <user>
  sudo scripts/linux-openai-egress-guard.sh status <user>

Creates UID-scoped iptables OUTPUT rules so the given Linux user can only make:
  - loopback connections
  - DNS queries to the host-configured nameservers
  - HTTPS connections to currently resolved OpenAI/Codex allowlist IPs

Override allowlist:
  OPENAI_EGRESS_DOMAINS="api.openai.com chatgpt.com auth.openai.com" sudo ...

proxy-apply is stricter: it allows only loopback for the user and rejects all
direct external egress. Use it with scripts/openai-connect-proxy.py running as a
different user/root and launch Codex with HTTPS_PROXY=http://127.0.0.1:18080.

This is intentionally Linux-only. Run Codex as a dedicated user and apply this
guard to that user, not to your normal admin account.
EOF
}

if [[ $# -ne 2 || "$1" == "-h" || "$1" == "--help" ]]; then
  usage
  exit 1
fi

if [[ "$(uname -s)" != "Linux" ]]; then
  echo "This guard is Linux-only." >&2
  exit 1
fi

if [[ "${EUID}" -ne 0 ]]; then
  echo "Run as root." >&2
  exit 1
fi

action="$1"
user="$2"
uid="$(id -u "$user")"
chain4="PB_OPENAI_${uid}"
chain6="PB_OPENAI6_${uid}"
domains="${OPENAI_EGRESS_DOMAINS:-api.openai.com auth.openai.com chatgpt.com ab.chatgpt.com persistent.oaistatic.com}"
proxy_port="${OPENAI_PROXY_PORT:-18080}"

require_cmd() {
  command -v "$1" >/dev/null || {
    echo "Missing required command: $1" >&2
    exit 1
  }
}

require_cmd iptables
require_cmd ip6tables
require_cmd getent

delete_rules() {
  while iptables -D OUTPUT -m owner --uid-owner "$uid" -j "$chain4" 2>/dev/null; do
    :
  done
  while ip6tables -D OUTPUT -m owner --uid-owner "$uid" -j "$chain6" 2>/dev/null; do
    :
  done
  iptables -F "$chain4" 2>/dev/null || true
  iptables -X "$chain4" 2>/dev/null || true
  ip6tables -F "$chain6" 2>/dev/null || true
  ip6tables -X "$chain6" 2>/dev/null || true
}

nameserver_ips() {
  awk '/^nameserver / { print $2 }' /etc/resolv.conf | sort -u
}

domain_ips() {
  for domain in $domains; do
    getent ahosts "$domain" | awk '{ print $1 }'
  done | sort -u
}

apply_rules() {
  delete_rules
  iptables -N "$chain4"
  ip6tables -N "$chain6"
  iptables -A OUTPUT -m owner --uid-owner "$uid" -j "$chain4"
  ip6tables -A OUTPUT -m owner --uid-owner "$uid" -j "$chain6"
  iptables -A "$chain4" -o lo -j ACCEPT
  ip6tables -A "$chain6" -o lo -j ACCEPT
  iptables -A "$chain4" -m conntrack --ctstate ESTABLISHED,RELATED -j ACCEPT
  ip6tables -A "$chain6" -m conntrack --ctstate ESTABLISHED,RELATED -j ACCEPT

  while read -r ip; do
    [[ -n "$ip" ]] || continue
    if [[ "$ip" == *:* ]]; then
      ip6tables -A "$chain6" -p udp -d "$ip" --dport 53 -j ACCEPT
      ip6tables -A "$chain6" -p tcp -d "$ip" --dport 53 -j ACCEPT
    else
      iptables -A "$chain4" -p udp -d "$ip" --dport 53 -j ACCEPT
      iptables -A "$chain4" -p tcp -d "$ip" --dport 53 -j ACCEPT
    fi
  done < <(nameserver_ips)

  while read -r ip; do
    [[ -n "$ip" ]] || continue
    if [[ "$ip" == *:* ]]; then
      ip6tables -A "$chain6" -p tcp -d "$ip" --dport 443 -j ACCEPT
    else
      iptables -A "$chain4" -p tcp -d "$ip" --dport 443 -j ACCEPT
    fi
  done < <(domain_ips)

  iptables -A "$chain4" -j REJECT
  ip6tables -A "$chain6" -j REJECT
}

proxy_apply_rules() {
  delete_rules
  iptables -N "$chain4"
  ip6tables -N "$chain6"
  iptables -A OUTPUT -m owner --uid-owner "$uid" -j "$chain4"
  ip6tables -A OUTPUT -m owner --uid-owner "$uid" -j "$chain6"
  iptables -A "$chain4" -o lo -p tcp --dport "$proxy_port" -j ACCEPT
  iptables -A "$chain4" -o lo -j ACCEPT
  ip6tables -A "$chain6" -o lo -j ACCEPT
  iptables -A "$chain4" -m conntrack --ctstate ESTABLISHED,RELATED -j ACCEPT
  ip6tables -A "$chain6" -m conntrack --ctstate ESTABLISHED,RELATED -j ACCEPT
  iptables -A "$chain4" -j REJECT
  ip6tables -A "$chain6" -j REJECT
}

case "$action" in
  apply)
    apply_rules
    ;;
  proxy-apply)
    proxy_apply_rules
    ;;
  delete)
    delete_rules
    ;;
  status)
    iptables -S "$chain4" 2>/dev/null || true
    ip6tables -S "$chain6" 2>/dev/null || true
    iptables -S OUTPUT | grep -- "--uid-owner $uid" || true
    ip6tables -S OUTPUT | grep -- "--uid-owner $uid" || true
    ;;
  *)
    usage
    exit 1
    ;;
esac

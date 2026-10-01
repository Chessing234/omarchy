echo "Stop broken TPM PCR units from forcibly rebooting the machine"

# Upstream systemd-pcrphase*.service / systemd-pcrfs*.service use
# FailureAction=reboot-force. On hardware where the TPM is present but dead
# (ThinkPad T470 and similar), that turns a failed measurement into a login
# loop. omarchy-settings ships FailureAction=none drop-ins to /etc, which
# pacman's daemon-reload hook does not watch; reload so they apply now.

as_root() {
  if (( EUID == 0 )); then
    "$@"
  else
    sudo "$@"
  fi
}

as_root systemctl daemon-reload >/dev/null 2>&1 || omarchy-state set reboot-required

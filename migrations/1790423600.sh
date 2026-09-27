echo "Disable unprivileged TTY line-discipline autoload"

# Package updates deliver etc/sysctl.d/99-omarchy-sysctl.conf with
# dev.tty.ldisc_autoload=0, but existing boots keep the prior runtime value
# until the next reboot unless we load the file now. Apply only our drop-in
# so an unrelated invalid key elsewhere cannot fail the migration.
if [[ $(sysctl -n dev.tty.ldisc_autoload 2>/dev/null) == "0" ]]; then
  exit 0
fi

if [[ -r /etc/sysctl.d/99-omarchy-sysctl.conf ]]; then
  sudo sysctl -p /etc/sysctl.d/99-omarchy-sysctl.conf >/dev/null || omarchy-state set reboot-required
fi

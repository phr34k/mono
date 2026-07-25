rm -rf /var/cache/libdnf5 /var/cache/dnf /var/lib/dnf /var/log/dnf5.log 2>/dev/null || true
rm -rf /usr/share/doc || true
rm -rf /tmp/* || true
rm -rf /usr/etc
rm -rf /boot && mkdir /boot
rm -rf /ctx || true
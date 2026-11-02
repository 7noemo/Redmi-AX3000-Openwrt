#!/bin/bash
#
# Redmi AX3000 (RA81) - DIY part 2 (runs after the config is loaded, before defconfig)
#
# Wi-Fi hardening on top of the upstream board support:
#   1. files/ overlay replaces the board_id hotplug script with a hardened one
#      (searches several MTD partitions, correct M81 fallback, syslog traces)
#   2. files/ overlay adds /etc/uci-defaults/99-ra81-wifi, which configures the
#      radios by BAND (not index) on first boot: CN country, 2.4G HE40 ch6,
#      5G HE160 ch36
#   3. files/ overlay adds /usr/sbin/ra81-wifi-diag for field debugging
#   4. sanity-check that the overlay really lands in the image
#

set -e

WS="$GITHUB_WORKSPACE"

echo "--- overlay check ---"
for f in \
	etc/hotplug.d/firmware/10-ath11k-board_id \
	etc/uci-defaults/99-ra81-wifi \
	usr/sbin/ra81-wifi-diag ; do
	if [ -f "files/$f" ]; then
		echo "OK: files/$f"
	else
		echo "FAIL: files/$f missing (overlay was not moved into the tree?)"
		exit 1
	fi
done

# Make sure the overlay scripts are executable inside the image
chmod 0755 files/etc/uci-defaults/99-ra81-wifi \
	files/usr/sbin/ra81-wifi-diag \
	files/etc/hotplug.d/firmware/10-ath11k-board_id

echo "--- board_id logic that will be shipped ---"
/usr/bin/grep -nE "set_board_id|wl_pa_type|0x24|0x10" \
	files/etc/hotplug.d/firmware/10-ath11k-board_id | head -12

echo "--- dmesg/board id of the pinned base tree ---"
/usr/bin/grep -nE "0x24|0x10|board_id" target/linux/ipq50xx/dts/ipq5000-ax3000.dts | head -8

echo ""
echo ">>> Wi-Fi overlay ready"

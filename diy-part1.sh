#!/bin/bash
#
# Redmi AX3000 (RA81) - DIY part 1 (runs after the source clone, before feeds)
#
# The base tree already carries the full board support (DTS, ipq50xx target,
# ipq-wifi-redmi_ax3000 board files, ath11k-firmware-qcn6122). This script only
# verifies that assumption, so a silent upstream rename cannot produce a
# firmware without Wi-Fi.
#

set -e

fail=0

check() {
	if [ -e "$2" ]; then
		echo "OK: $1 -> $2"
	else
		echo "FAIL: $1 missing ($2)"
		fail=1
	fi
}

check "DTS (IPQ5000 board)"      target/linux/ipq50xx/dts/ipq5000-ax3000.dts
check "device definition"        target/linux/ipq50xx/image/Makefile
check "2.4G BDF board file"      package/firmware/ipq-wifi/src/board-redmi_ax3000.ipq5018
check "5G BDF board file"        package/firmware/ipq-wifi/src/board-redmi_ax3000.qcn6122
check "board_id hotplug"         target/linux/ipq50xx/base-files/etc/hotplug.d/firmware/10-ath11k-board_id
check "ART caldata hotplug"      target/linux/ipq50xx/base-files/etc/hotplug.d/firmware/11-ath11k-caldata

if ! /usr/bin/grep -rqs "define Device/redmi_ax3000" target/linux/ipq50xx/image/; then
	echo "FAIL: Device/redmi_ax3000 not defined in image Makefile"
	fail=1
fi

if [ "$fail" -ne 0 ]; then
	echo ">>> board support is not where we expect it, aborting before the 2h build"
	exit 1
fi

echo ""
echo ">>> board support checks passed"

#!/bin/bash -e

# an automated ROM installer
# runtime dependencies: adb, fastboot, payload-dumper-go, unzip
# device requirements: bootloader unlocked, USB debugging enabled

case "${1}" in "")
  printf "${0} [path to rom]\n"
  exit ;;
esac

if touch /tmp > /dev/null 2>&1; then cd /tmp; fi

unzip "${1}" payload.bin

payload-dumper-go \
  -partitions boot,vendor_boot,dtbo \
  -output "${PWD}" \
    payload.bin

rm -fv payload.bin

if adb shell ':' > /dev/null 2>&1; then
  echo "rebooting to bootloader"
  adb reboot bootloader && fastboot -w
else
  fastboot -w
fi

for PART in boot vendor_boot dtbo; do
  fastboot flash "${PART}" "${PART}.img"
done

fastboot reboot-recovery

# Apply ROM to target device
until adb sideload "${1}"; do sleep 5; done

rm -fv *.bin *.img

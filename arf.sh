#!/bin/bash -e

rom_validity_check() {
  if test -e "${1}"; then
    if unzip -l "${1}" | grep payload.bin > /dev/null 2>&1; then
      true
    fi
  else
    printf "[${1} doesn't appear to be a valid ROM, exiting.]\n"
    exit 1
  fi
}

flash_rom() {

  rom_validity_check "${1}"

  unzip "${1}" payload.bin

  payload-dumper-go \
    -partitions boot,vendor_boot,dtbo \
    -output "${PWD}" \
      payload.bin

  rm -fv payload.bin

  if adb shell ':' > /dev/null 2>&1; then
    printf "[rebooting to bootloader...]\n"
    adb reboot bootloader && fastboot -w
  else
    fastboot -w
  fi

  for PART in boot vendor_boot dtbo; do
    fastboot flash "${PART}" "${PART}.img"
  done

  fastboot reboot-recovery

  sleep 10
  printf "[now, apply update from adb.]\n"
  sleep 5

  # Apply ROM to target device
  until adb sideload "${1}"; do sleep 5; done

}

proc_magisk() {

  rom_validity_check "${2}"

  if adb shell "test -e /dev/block/by-name/init_boot_a"; then
    IMG="init_boot"; else IMG="boot"
  fi

  MAGISKVER="27.0"
  MAGISKURL="https://github.com/topjohnwu/Magisk/releases/download/v${MAGISKVER}/Magisk-v${MAGISKVER}.apk"

  test -e "./Magisk-v${MAGISKVER}.apk" || {
    printf "[downloading magisk...]\n"
    curl -fLO "${MAGISKURL}"
  }

  # Retrieve $IMG.img for currently running ROM for patching
  unzip "${2}" payload.bin || exit 1
  payload-dumper-go -partitions ${IMG} -output "${PWD}" payload.bin || exit 1
  adb push "${IMG}.img" "/sdcard/Download/"

  # Install and open Magisk on target device
  adb install "`find . -name \*Magisk\*apk\* | tail -1`"
  adb shell "monkey -p com.topjohnwu.magisk 1"

  printf "\n[patch /sdcard/Download/${IMG}.img in Magisk and press enter.]\n"
  read

  # ls -atr sorts newest at the bottom; tail that to get the right file
  MAGISKIMG="`adb shell ls -atr /sdcard/Download | grep -i magisk | tail -1`"

  adb pull "/sdcard/Download/${MAGISKIMG}"
  adb shell "rm -fv /sdcard/Download/${MAGISKIMG} /sdcard/Download/${IMG}.img"
  adb reboot bootloader

  for PART in a b; do fastboot flash "${IMG}_${PART}" "${MAGISKIMG}"; done

  fastboot reboot

}

if touch /tmp; then mkdir -pv /tmp/arf && cd /tmp/arf; fi

case "${1}" in
  --magisk|-m) proc_magisk "${@}" ;;
  *.zip) flash_rom "${@}" ;;
  *) echo "${0} [path to rom]" ;;
esac

cd "${HOME}" && rm -rfv /tmp/arf

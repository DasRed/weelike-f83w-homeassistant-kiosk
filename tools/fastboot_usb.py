#!/usr/bin/env python3
"""
Minimal fastboot client on top of libusb (pyusb).

Purpose: the Allwinner bootloader (u-boot fastboot, VID 0x1F3A / PID 0x1010)
is not always detected by the macOS `fastboot`, because macOS does not activate
a USB configuration for this vendor device. This script selects the
configuration itself and speaks the fastboot protocol directly.

Usage:
    fastboot_usb.py wait [SECONDS]       # waits until a fastboot device is present
    fastboot_usb.py getvar <name>
    fastboot_usb.py oem <command...>     # e.g. "oem unlock"
    fastboot_usb.py reboot

Exit code 0 = OKAY, 1 = FAIL/error, 2 = no device found.
"""
import os
import sys
import time

try:
    import usb.core
    import usb.util
    import usb.backend.libusb1
except ImportError:
    print("pyusb is missing (pip install pyusb)", file=sys.stderr)
    sys.exit(1)

FASTBOOT_IFACE = (0xFF, 0x42, 0x03)  # Class / SubClass / Protocol


def backend():
    candidates = [
        os.environ.get("LIBUSB_PATH", ""),
        "/opt/homebrew/lib/libusb-1.0.dylib",  # Apple Silicon (Homebrew)
        "/usr/local/lib/libusb-1.0.dylib",     # Intel Mac (Homebrew)
    ]
    for path in candidates:
        if path and os.path.exists(path):
            return usb.backend.libusb1.get_backend(find_library=lambda _x, p=path: p)
    return usb.backend.libusb1.get_backend()


def find_device():
    be = backend()
    if be is None:
        print("libusb not found (brew install libusb)", file=sys.stderr)
        sys.exit(1)
    for dev in usb.core.find(find_all=True, backend=be):
        try:
            for cfg in dev:
                for intf in cfg:
                    if (intf.bInterfaceClass, intf.bInterfaceSubClass, intf.bInterfaceProtocol) == FASTBOOT_IFACE:
                        return dev, cfg, intf
        except (usb.core.USBError, ValueError):
            continue
    return None


def open_device():
    found = find_device()
    if not found:
        return None
    dev, cfg, intf = found
    try:
        active = dev.get_active_configuration()
    except usb.core.USBError:
        active = None
    if active is None or active.bConfigurationValue != cfg.bConfigurationValue:
        dev.set_configuration(cfg.bConfigurationValue)
    try:
        if dev.is_kernel_driver_active(intf.bInterfaceNumber):
            dev.detach_kernel_driver(intf.bInterfaceNumber)
    except (NotImplementedError, usb.core.USBError):
        pass
    usb.util.claim_interface(dev, intf.bInterfaceNumber)
    ep_out = usb.util.find_descriptor(
        intf, custom_match=lambda e: usb.util.endpoint_direction(e.bEndpointAddress) == usb.util.ENDPOINT_OUT)
    ep_in = usb.util.find_descriptor(
        intf, custom_match=lambda e: usb.util.endpoint_direction(e.bEndpointAddress) == usb.util.ENDPOINT_IN)
    if ep_out is None or ep_in is None:
        raise RuntimeError("fastboot endpoints not found")
    return dev, ep_out, ep_in


def command(cmd, timeout_s=60):
    opened = open_device()
    if not opened:
        print("no fastboot device found", file=sys.stderr)
        return 2
    _dev, ep_out, ep_in = opened
    ep_out.write(cmd.encode("ascii"), timeout=5000)
    deadline = time.time() + timeout_s
    while time.time() < deadline:
        try:
            raw = bytes(ep_in.read(256, timeout=2000))
        except usb.core.USBTimeoutError:
            continue
        except usb.core.USBError as exc:
            # On "reboot" the device often disappears before answering
            if cmd == "reboot":
                return 0
            print(f"USB error: {exc}", file=sys.stderr)
            return 1
        kind, payload = raw[:4].decode("ascii", "replace"), raw[4:].decode("utf-8", "replace")
        if kind in ("INFO", "TEXT"):
            print(f"(bootloader) {payload}")
            continue
        if kind == "OKAY":
            if payload:
                print(payload)
            return 0
        if kind == "FAIL":
            print(f"FAILED: {payload}", file=sys.stderr)
            return 1
        print(f"unexpected response: {raw!r}", file=sys.stderr)
        return 1
    print("timeout", file=sys.stderr)
    return 1


def main(argv):
    if len(argv) < 2:
        print(__doc__)
        return 1
    action = argv[1]
    if action == "wait":
        seconds = int(argv[2]) if len(argv) > 2 else 30
        deadline = time.time() + seconds
        while time.time() < deadline:
            if find_device():
                return 0
            time.sleep(1)
        return 2
    if action == "getvar" and len(argv) == 3:
        return command(f"getvar:{argv[2]}")
    if action == "oem" and len(argv) >= 3:
        return command("oem " + " ".join(argv[2:]))
    if action == "reboot":
        return command("reboot")
    print(__doc__)
    return 1


if __name__ == "__main__":
    sys.exit(main(sys.argv))

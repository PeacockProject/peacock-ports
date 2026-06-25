// peacock initramfs /init wrapper.
//
// Prebuilt, per-arch binary installed at /usr/lib/peacock/init-wrapper.
// peacock-mkinitfs copies it into the initramfs as /init when present, so an
// on-device install (PRP, no Go toolchain) can assemble a bootable initramfs.
// It mounts devtmpfs and exec()s the shell init script (/init.sh) — it exists
// so kernels without BINFMT_SCRIPT (no shebang interpreter) still have a PID 1.
//
// Source of truth: peacock-mkinitfs/assets/initramfs/init-wrapper.go.in. Keep
// this copy in sync with that file.
package main

import (
	"os"
	"syscall"
	"unsafe"
)

func klog(msg string) {
	if msg == "" {
		return
	}
	if f, err := os.OpenFile("/dev/kmsg", os.O_WRONLY, 0); err == nil {
		_, _ = f.Write([]byte(msg))
		_ = f.Close()
		return
	}
	b := []byte(msg)
	// SYSLOG_ACTION_WRITE = 2
	_, _, _ = syscall.Syscall(syscall.SYS_SYSLOG, 2, uintptr(unsafe.Pointer(&b[0])), uintptr(len(b)))
}

func main() {
	_ = os.MkdirAll("/dev", 0755)
	_ = syscall.Mount("devtmpfs", "/dev", "devtmpfs", 0, "")
	klog("PEACOCK: init wrapper start\n")
	env := os.Environ()
	tryExec := func(argv []string, label string) {
		klog("PEACOCK: exec " + label + "\n")
		_ = syscall.Exec(argv[0], argv, env)
	}

	// Prefer explicit busybox ash, then fall back to shell.
	tryExec([]string{"/bin/busybox", "ash", "/init.sh"}, "/bin/busybox ash /init.sh")
	tryExec([]string{"/bin/ash", "/init.sh"}, "/bin/ash /init.sh")
	tryExec([]string{"/bin/sh", "/init.sh"}, "/bin/sh /init.sh")
	tryExec([]string{"/bin/busybox", "sh"}, "/bin/busybox sh")

	klog("PEACOCK: init wrapper exec failed\n")
	os.Exit(1)
}

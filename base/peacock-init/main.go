// Command peacock-init is the PeacockOS base supervisor and PID 1.
//
// In the flipped boot model the Peacock base IS the root filesystem
// (LABEL=ROOT). The initramfs switch_roots into it and execs /sbin/init,
// which is this program. peacock-init then:
//
//  1. mounts the base's own pseudo-filesystems (/proc /sys /dev /run),
//  2. reads the active flavor (/peacock/etc/active-flavor),
//  3. bind-mounts the base-owned trees (/peacock /apps /compat /data) and the
//     pseudo-filesystems into the flavor root under /flavors/<active>,
//  4. starts the flavor's own init (chrooted) as a child, and
//  5. stays resident as PID 1: reaps orphaned children and watches the flavor.
//
// Phase 1 (this file) uses a plain chroot — no namespaces yet, no recovery.
// Phase 2 adds PID+mount namespaces (via util-linux `unshare`) and a
// crash/timeout -> PRP_ROOTFS recovery path. The supervise() loop is the seam
// where that lands.
package main

import (
	"fmt"
	"os"
	"os/exec"
	"path/filepath"
	"strings"
	"syscall"
	"time"
)

const (
	activeFlavorFile = "/peacock/etc/active-flavor"
	flavorsRoot      = "/flavors"
	logPrefix        = "peacock-init: "
)

// baseOwnedTrees are bind-mounted into the active flavor so apps + user data
// persist across distro swaps — the meta-distro payoff.
var baseOwnedTrees = []string{"/peacock", "/apps", "/compat", "/data"}

// pseudoMounts are the kernel pseudo-filesystems the flavor userland needs.
var pseudoMounts = []struct {
	source, target, fstype string
}{
	{"proc", "/proc", "proc"},
	{"sysfs", "/sys", "sysfs"},
	{"devtmpfs", "/dev", "devtmpfs"},
	{"tmpfs", "/run", "tmpfs"},
}

func logf(format string, a ...interface{}) {
	fmt.Fprintf(os.Stderr, logPrefix+format+"\n", a...)
}

func main() {
	logf("starting (pid %d)", os.Getpid())

	// 1. Base pseudo-filesystems. Idempotent — the initramfs may have left
	//    some mounted; EBUSY is tolerated.
	earlyMounts()

	// 2. Resolve the active flavor.
	flavor := activeFlavor()
	root := filepath.Join(flavorsRoot, flavor)
	if !isDir(root) {
		fatalf("active flavor %q has no rootfs at %s", flavor, root)
	}
	logf("active flavor: %s (%s)", flavor, root)

	// 3. Stage the flavor root: base-owned trees + pseudo-filesystems.
	if err := stageFlavorRoot(root); err != nil {
		fatalf("staging flavor root: %v", err)
	}

	// 4. Start the flavor's own init, chrooted into its rootfs.
	initPath := flavorInitPath(root)
	logf("entering flavor via chroot, init=%s", initPath)
	child, err := startFlavorInit(root, initPath)
	if err != nil {
		fatalf("starting flavor init: %v", err)
	}

	// 5. PID 1 duties: reap orphans, watch the flavor.
	supervise(child.Process.Pid)
}

// earlyMounts mounts the base's own pseudo-filesystems if not already present.
func earlyMounts() {
	for _, m := range pseudoMounts {
		if isMountpoint(m.target) {
			continue
		}
		_ = os.MkdirAll(m.target, 0o755)
		if err := syscall.Mount(m.source, m.target, m.fstype, 0, ""); err != nil {
			logf("warning: mount %s on %s: %v", m.fstype, m.target, err)
		}
	}
}

// activeFlavor reads /peacock/etc/active-flavor, falling back to the sole
// installed flavor when the file is absent.
func activeFlavor() string {
	if data, err := os.ReadFile(activeFlavorFile); err == nil {
		if name := strings.TrimSpace(string(data)); name != "" {
			return name
		}
	}
	if entries, err := os.ReadDir(flavorsRoot); err == nil {
		var dirs []string
		for _, e := range entries {
			if e.IsDir() {
				dirs = append(dirs, e.Name())
			}
		}
		if len(dirs) == 1 {
			logf("no active-flavor file; defaulting to the only flavor %q", dirs[0])
			return dirs[0]
		}
	}
	fatalf("no active flavor configured (%s missing) and not exactly one flavor under %s", activeFlavorFile, flavorsRoot)
	return ""
}

// stageFlavorRoot bind-mounts the base-owned trees and pseudo-filesystems into
// the flavor root so the chrooted userland sees them. Phase 1 uses plain
// recursive bind mounts in the host mount table (no namespace).
func stageFlavorRoot(root string) error {
	bind := func(src, dst string) error {
		if err := os.MkdirAll(dst, 0o755); err != nil {
			return fmt.Errorf("mkdir %s: %w", dst, err)
		}
		if isMountpoint(dst) {
			return nil
		}
		if err := syscall.Mount(src, dst, "", syscall.MS_BIND|syscall.MS_REC, ""); err != nil {
			return fmt.Errorf("bind %s -> %s: %w", src, dst, err)
		}
		return nil
	}
	for _, t := range baseOwnedTrees {
		if !isDir(t) {
			continue // optional trees may not exist yet
		}
		if err := bind(t, filepath.Join(root, t)); err != nil {
			return err
		}
	}
	for _, m := range pseudoMounts {
		if err := bind(m.target, filepath.Join(root, m.target)); err != nil {
			return err
		}
	}
	return nil
}

// flavorInitPath picks the flavor's init: OpenRC /sbin/init, then systemd, then
// a couple of fallbacks. Paths are relative to the flavor root.
func flavorInitPath(root string) string {
	for _, c := range []string{"/sbin/init", "/usr/lib/systemd/systemd", "/lib/systemd/systemd", "/init", "/bin/sh"} {
		if isExec(filepath.Join(root, c)) {
			return c
		}
	}
	return "/sbin/init"
}

// startFlavorInit forks the flavor's init chrooted into its rootfs.
func startFlavorInit(root, initPath string) (*exec.Cmd, error) {
	cmd := exec.Command(initPath)
	cmd.SysProcAttr = &syscall.SysProcAttr{Chroot: root}
	cmd.Dir = "/"
	cmd.Stdin = os.Stdin
	cmd.Stdout = os.Stdout
	cmd.Stderr = os.Stderr
	cmd.Env = []string{
		"PATH=/usr/sbin:/usr/bin:/sbin:/bin",
		"TERM=linux",
		"container=peacock", // hint for systemd-aware tooling later
	}
	if err := cmd.Start(); err != nil {
		return nil, err
	}
	return cmd, nil
}

// supervise is the PID 1 loop: reap every child, and notice when the flavor's
// init (flavorPID) exits. Phase 2 will turn the flavor-exit branch into a
// crash/timeout -> PRP_ROOTFS recovery handoff.
func supervise(flavorPID int) {
	logf("flavor init running as pid %d; supervising", flavorPID)
	for {
		var ws syscall.WaitStatus
		pid, err := syscall.Wait4(-1, &ws, 0, nil)
		switch err {
		case nil:
			// reaped pid
		case syscall.EINTR:
			continue
		case syscall.ECHILD:
			logf("no children remain")
			haltLoud("flavor exited")
			return
		default:
			logf("wait4: %v", err)
			time.Sleep(time.Second)
			continue
		}
		if pid == flavorPID {
			logf("flavor init (pid %d) exited: %s", pid, statusString(ws))
			haltLoud("flavor init exited")
			return
		}
		// Reaped an orphan reparented to PID 1; keep going.
	}
}

// haltLoud keeps PID 1 alive (returning would panic the kernel) and, in
// Phase 1, drops to an emergency shell so the failure is inspectable. Phase 2
// replaces this with PRP_ROOTFS recovery.
func haltLoud(reason string) {
	logf("HALT: %s — entering emergency shell (phase 1; PRP recovery lands in phase 2)", reason)
	if isExec("/bin/sh") {
		sh := exec.Command("/bin/sh")
		sh.SysProcAttr = &syscall.SysProcAttr{Setctty: true, Setsid: true}
		sh.Stdin, sh.Stdout, sh.Stderr = os.Stdin, os.Stdout, os.Stderr
		_ = sh.Run()
	}
	for {
		time.Sleep(time.Hour)
	}
}

func fatalf(format string, a ...interface{}) {
	logf("FATAL: "+format, a...)
	haltLoud("fatal")
}

// isMountpoint reports whether path is a mount point by comparing its st_dev
// to its parent's — no /proc needed (it may not be mounted yet).
func isMountpoint(path string) bool {
	var st, pst syscall.Stat_t
	if err := syscall.Lstat(path, &st); err != nil {
		return false
	}
	if err := syscall.Lstat(filepath.Dir(path), &pst); err != nil {
		return false
	}
	return st.Dev != pst.Dev
}

func isDir(path string) bool {
	fi, err := os.Stat(path)
	return err == nil && fi.IsDir()
}

func isExec(path string) bool {
	fi, err := os.Stat(path)
	return err == nil && !fi.IsDir() && fi.Mode()&0o111 != 0
}

func statusString(ws syscall.WaitStatus) string {
	switch {
	case ws.Exited():
		return fmt.Sprintf("exit %d", ws.ExitStatus())
	case ws.Signaled():
		return fmt.Sprintf("signal %s", ws.Signal())
	default:
		return "unknown"
	}
}

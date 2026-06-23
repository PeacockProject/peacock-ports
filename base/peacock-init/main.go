// Command peacock-init is the PeacockOS base supervisor and PID 1.
//
// In the flipped boot model the Peacock base IS the root filesystem
// (LABEL=ROOT). The initramfs switch_roots into it and execs /sbin/init,
// which is this program. peacock-init then:
//
//  1. mounts the base's own pseudo-filesystems (/proc /sys /dev /run) and makes
//     the base mount tree private,
//  2. reads the active flavor (/peacock/etc/active-flavor),
//  3. bind-mounts the base-owned trees (/peacock /apps /compat /data) and /dev
//     /run into the flavor root under /flavors/<active>,
//  4. enters the flavor in its OWN PID + mount namespace (the flavor's init
//     becomes PID 1 of that namespace), and
//  5. stays resident as PID 1: reaps orphans, watches for the flavor's
//     boot-ready signal vs a timeout, and on crash/timeout drops into the
//     existing PRP recovery partition — never a hard reset.
//
// Namespaces need CONFIG_PID_NS in the device kernel; peacock-init probes at
// runtime and degrades to a plain chroot (phase-1 behavior) when they're
// unavailable.
package main

import (
	"bytes"
	"fmt"
	"os"
	"os/exec"
	"path/filepath"
	"strings"
	"syscall"
	"time"
)

const (
	// readyFile lives under the base-owned /peacock bind (NOT /run) so the
	// flavor mounting its own /run tmpfs can't shadow it — the flavor writes
	// here when it reaches its default runlevel and the base watches for it.
	readyFile     = "/peacock/.flavor-ready"
	prpLabel      = "PRP_ROOTFS"
	recoveryMount = "/recovery"
	bootTimeout   = 90 * time.Second
	logPrefix     = "peacock-init: "
)

// activeFlavorFile / flavorsRoot are vars (not consts) only so tests can point
// them at a sandbox; production values are the real on-base paths.
var (
	activeFlavorFile = "/peacock/etc/active-flavor"
	flavorsRoot      = "/flavors"
)

// baseOwnedTrees persist across distro swaps and are bind-mounted into the
// active flavor — the meta-distro payoff.
var baseOwnedTrees = []string{"/peacock", "/apps", "/compat", "/data"}

// pseudoMounts are the kernel pseudo-filesystems the base itself needs.
var pseudoMounts = []struct{ source, target, fstype string }{
	{"proc", "/proc", "proc"},
	{"sysfs", "/sys", "sysfs"},
	{"devtmpfs", "/dev", "devtmpfs"},
	{"tmpfs", "/run", "tmpfs"},
}

type outcome int

const (
	outcomeExit    outcome = iota // the flavor's init exited
	outcomeTimeout                // it never signaled ready in time
)

func (o outcome) String() string {
	if o == outcomeTimeout {
		return "boot timeout"
	}
	return "init exited"
}

func logf(format string, a ...interface{}) {
	fmt.Fprintf(os.Stderr, logPrefix+format+"\n", a...)
}

func main() {
	logf("starting (pid %d)", os.Getpid())

	earlyMounts()

	flavor := activeFlavor()
	root := filepath.Join(flavorsRoot, flavor)
	if !isDir(root) {
		fatalf("active flavor %q has no rootfs at %s", flavor, root)
	}
	useNS := namespacesSupported()
	logf("active flavor: %s (%s); namespaces=%v", flavor, root, useNS)

	if err := stageFlavorRoot(root, useNS); err != nil {
		fatalf("staging flavor root: %v", err)
	}

	initPath := flavorInitPath(root)
	_ = os.Remove(readyFile) // clear any stale ready marker
	logf("entering flavor (init=%s) via %s", initPath, entryMode(useNS))
	child, err := startFlavor(root, initPath, useNS)
	if err != nil {
		fatalf("starting flavor init: %v", err)
	}

	res, killPID := supervise(child.Process.Pid)
	logf("flavor %s — entering recovery", res)
	enterRecovery(killPID)

	// enterRecovery only returns if it couldn't hand off; keep PID 1 alive.
	haltLoud("recovery returned")
}

// earlyMounts mounts the base pseudo-filesystems and makes the base mount tree
// private so a flavor's namespace mounts can't propagate back to the host.
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
	if err := syscall.Mount("", "/", "", syscall.MS_REC|syscall.MS_PRIVATE, ""); err != nil {
		logf("warning: make-rprivate /: %v", err)
	}
}

// namespacesSupported reports whether the kernel exposes PID namespaces.
func namespacesSupported() bool {
	if _, err := os.Stat("/proc/self/ns/pid"); err != nil {
		return false
	}
	// A cheap functional check: unsharing a throwaway nothing-flag always
	// succeeds; the file presence above is the real signal. Keep it simple.
	return true
}

func entryMode(useNS bool) string {
	if useNS {
		return "PID+mount namespace"
	}
	return "chroot"
}

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

// stageFlavorRoot bind-mounts the base-owned trees plus /dev and /run into the
// flavor root. /proc and /sys are bound only on the chroot path; the namespace
// path mounts them fresh inside the namespace (a fresh /proc is REQUIRED there
// so the flavor's init sees the namespace's PIDs).
func stageFlavorRoot(root string, useNS bool) error {
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
			continue
		}
		if err := bind(t, filepath.Join(root, t)); err != nil {
			return err
		}
	}
	if err := bind("/dev", filepath.Join(root, "dev")); err != nil {
		return err
	}
	if err := bind("/run", filepath.Join(root, "run")); err != nil {
		return err
	}
	if !useNS {
		// Plain chroot shares the host pidns, so reuse the host /proc /sys.
		if err := bind("/proc", filepath.Join(root, "proc")); err != nil {
			return err
		}
		if err := bind("/sys", filepath.Join(root, "sys")); err != nil {
			return err
		}
	} else {
		// Make sure the mount points exist for the in-namespace mounts.
		_ = os.MkdirAll(filepath.Join(root, "proc"), 0o755)
		_ = os.MkdirAll(filepath.Join(root, "sys"), 0o755)
	}
	return nil
}

func flavorInitPath(root string) string {
	for _, c := range []string{"/sbin/init", "/usr/lib/systemd/systemd", "/lib/systemd/systemd", "/init", "/bin/sh"} {
		if isExec(filepath.Join(root, c)) {
			return c
		}
	}
	return "/sbin/init"
}

// startFlavor launches the flavor's own init. On the namespace path the child
// is PID 1 of a fresh PID+mount namespace (CLONE_NEWPID|CLONE_NEWNS) chrooted
// into the flavor; a tiny /bin/sh mounts a fresh /proc + /sys before exec'ing
// the flavor init. On the chroot fallback it's just a chrooted child.
func startFlavor(root, initPath string, useNS bool) (*exec.Cmd, error) {
	env := []string{
		"PATH=/usr/sbin:/usr/bin:/sbin:/bin",
		"TERM=linux",
		"container=peacock",
	}
	var cmd *exec.Cmd
	if useNS {
		script := "mount -t proc proc /proc 2>/dev/null; mount -t sysfs sys /sys 2>/dev/null; exec " + initPath
		cmd = exec.Command("/bin/sh", "-c", script)
		cmd.SysProcAttr = &syscall.SysProcAttr{
			Chroot:     root,
			Cloneflags: syscall.CLONE_NEWPID | syscall.CLONE_NEWNS,
			Setctty:    true,
			Setsid:     true,
		}
	} else {
		cmd = exec.Command(initPath)
		cmd.SysProcAttr = &syscall.SysProcAttr{Chroot: root}
	}
	cmd.Dir = "/"
	cmd.Stdin = os.Stdin
	cmd.Stdout = os.Stdout
	cmd.Stderr = os.Stderr
	cmd.Env = env
	if err := cmd.Start(); err != nil {
		return nil, err
	}
	return cmd, nil
}

// supervise is the PID 1 loop. It reaps every child (WNOHANG), watches for the
// flavor's boot-ready signal vs a timeout, and returns when the flavor fails:
// outcomeExit when its init exits, outcomeTimeout when it never signals ready.
// The second return is the pid to kill on timeout (0 when already dead).
func supervise(flavorPID int) (outcome, int) {
	logf("flavor init running as pid %d; supervising (boot timeout %s)", flavorPID, bootTimeout)
	deadline := time.Now().Add(bootTimeout)
	booted := false
	for {
		if !booted {
			if _, err := os.Stat(readyFile); err == nil {
				booted = true
				logf("flavor signaled ready; booted OK")
			} else if time.Now().After(deadline) {
				logf("flavor did not signal ready within %s", bootTimeout)
				return outcomeTimeout, flavorPID
			}
		}
		var ws syscall.WaitStatus
		pid, err := syscall.Wait4(-1, &ws, syscall.WNOHANG, nil)
		switch {
		case err == syscall.EINTR:
			continue
		case err == syscall.ECHILD:
			logf("no children remain")
			return outcomeExit, 0
		case err != nil:
			logf("wait4: %v", err)
			time.Sleep(time.Second)
			continue
		}
		if pid == 0 {
			// Nothing changed state; idle briefly so we re-check ready/timeout.
			time.Sleep(500 * time.Millisecond)
			continue
		}
		if pid == flavorPID {
			logf("flavor init (pid %d) exited: %s", pid, statusString(ws))
			return outcomeExit, 0
		}
		// Reaped a host-level orphan; keep going (PID 1 duty).
	}
}

// enterRecovery stops a hung flavor, then finds + mounts the existing
// PRP_ROOTFS partition and enters it as the recovery environment — no reboot,
// no hard reset. Falls back to the base emergency shell when PRP is absent.
func enterRecovery(killPID int) {
	if killPID > 0 {
		logf("stopping flavor namespace (pid %d)", killPID)
		_ = syscall.Kill(killPID, syscall.SIGKILL)
		time.Sleep(time.Second)
	}

	dev := findPRPRootfs()
	if dev == "" {
		logf("PRP_ROOTFS partition not found")
		haltLoud("no recovery partition")
		return
	}
	if err := os.MkdirAll(recoveryMount, 0o755); err != nil {
		logf("mkdir %s: %v", recoveryMount, err)
		haltLoud("recovery setup failed")
		return
	}
	// Mount READ-WRITE: PRP's recovery init writes a runtime into the rootfs
	// (/etc/passwd via ensure_minimal_users, /tmp, /run) and we must be able to
	// create the /dev /proc /sys /run mountpoints below (the overlay doesn't ship
	// them). A read-only mount fails both ("Read-only file system" + the binds
	// have no mountpoint -> "/dev/kmsg: nonexistent directory").
	mounted := false
	for _, fs := range []string{"ext4", "ext3", "ext2"} {
		if err := syscall.Mount(dev, recoveryMount, fs, 0, ""); err == nil {
			mounted = true
			break
		}
	}
	if !mounted {
		logf("failed to mount PRP_ROOTFS (%s)", dev)
		haltLoud("recovery mount failed")
		return
	}
	logf("mounted PRP_ROOTFS (%s) at %s; entering recovery", dev, recoveryMount)

	for _, m := range []struct{ src, target, fstype string }{
		{"/dev", "dev", ""},
		{"proc", "proc", "proc"},
		{"sysfs", "sys", "sysfs"},
		{"/run", "run", ""},
	} {
		dst := filepath.Join(recoveryMount, m.target)
		_ = os.MkdirAll(dst, 0o755)
		if m.fstype == "" {
			_ = syscall.Mount(m.src, dst, "", syscall.MS_BIND|syscall.MS_REC, "")
		} else {
			_ = syscall.Mount(m.src, dst, m.fstype, 0, "")
		}
	}

	// PRP_ROOTFS is an OVERLAY (toolbox + the LVGL prp-gui), not a bootable
	// rootfs — no /sbin/init. The proper recovery entry point is owned by PRP
	// (prp-recovery-enter), which runs PRP's real recovery session (framebuffer
	// bring-up, GUI, services) — peacock-init does NOT re-implement it. Fall
	// back to a busybox toolbox shell when that entry isn't present. Note:
	// /bin/sh there is an ABSOLUTE symlink to /sbin/busybox, unresolvable from
	// outside the chroot, so probe the real busybox binary.
	if entry := firstExec(recoveryMount, "/usr/bin/prp-recovery-enter", "/sbin/prp-recovery-enter", "/init"); entry != "" {
		logf("recovery entry: %s (PRP recovery session)", entry)
		runRecoveryCmd(recoveryMount, entry)
		return
	}
	if bb := firstExec(recoveryMount, "/sbin/busybox", "/bin/busybox", "/usr/bin/busybox"); bb != "" {
		logf("recovery entry: %s sh (no prp-recovery-enter; toolbox shell)", bb)
		runRecoveryCmd(recoveryMount, bb, "sh")
		return
	}
	if entry := firstExec(recoveryMount, "/sbin/init", "/bin/sh", "/bin/bash"); entry != "" {
		runRecoveryCmd(recoveryMount, entry)
		return
	}
	logf("recovery: no usable entry point in PRP_ROOTFS")
}

// runRecoveryCmd execs a recovery entry chrooted into the PRP_ROOTFS mount.
func runRecoveryCmd(root, name string, args ...string) {
	cmd := exec.Command(name, args...)
	cmd.SysProcAttr = &syscall.SysProcAttr{Chroot: root, Setctty: true, Setsid: true}
	cmd.Dir = "/"
	cmd.Stdin, cmd.Stdout, cmd.Stderr = os.Stdin, os.Stdout, os.Stderr
	cmd.Env = []string{"PATH=/usr/sbin:/usr/bin:/sbin:/bin", "TERM=linux", "HOME=/root", "PEACOCK_RECOVERY=1"}
	if err := cmd.Run(); err != nil {
		logf("recovery entry exited: %v", err)
	}
}

// firstExec returns the first of paths (relative to root) that is an executable
// regular file, or "".
func firstExec(root string, paths ...string) string {
	for _, p := range paths {
		if isExec(filepath.Join(root, p)) {
			return p
		}
	}
	return ""
}

// findPRPRootfs locates the PRP recovery rootfs. PRP_ROOTFS is NOT always a
// top-level partition with a blkid-visible label: on daisy it lives on the
// inactive A/B boot slot (boot_b), and a monolithic build can nest it as a
// subpartition of the recovery partition. So, like PRP's own find_prp_rootfs_dev,
// we match the ext volume label read straight from each device's superblock —
// that finds it wherever it sits — and as a fallback expose the recovery
// partition's subpartitions before re-scanning.
func findPRPRootfs() string {
	for _, dev := range candidateBlockDevices() {
		if extLabel(dev) == prpLabel {
			return dev
		}
	}
	// Secondary signals (some userspaces surface the label via blkid/findfs).
	if out, err := exec.Command("blkid").Output(); err == nil {
		for _, line := range strings.Split(string(out), "\n") {
			if strings.Contains(line, `LABEL="`+prpLabel+`"`) {
				if i := strings.IndexByte(line, ':'); i > 0 {
					return strings.TrimSpace(line[:i])
				}
			}
		}
	}
	if out, err := exec.Command("findfs", "LABEL="+prpLabel).Output(); err == nil {
		if dev := strings.TrimSpace(string(out)); dev != "" {
			return dev
		}
	}
	// Monolithic builds nest PRP_ROOTFS as a subpartition of recovery; expose
	// it on a partitioned loop, then re-scan superblock labels.
	return probeRecoverySubpart()
}

// candidateBlockDevices enumerates block devices PRP_ROOTFS might live on,
// deduped by their resolved path. Covers eMMC partitions, by-name aliases
// (incl. the inactive boot slot), SD/NVMe, and exposed loop subpartitions.
func candidateBlockDevices() []string {
	var devs []string
	seen := map[string]bool{}
	for _, p := range []string{
		"/dev/mmcblk*p*", "/dev/block/mmcblk*p*",
		"/dev/block/by-name/*", "/dev/block/bootdevice/by-name/*",
		"/dev/sd*", "/dev/nvme*p*", "/dev/loop*p*",
	} {
		matches, _ := filepath.Glob(p)
		for _, m := range matches {
			real := m
			if r, err := filepath.EvalSymlinks(m); err == nil {
				real = r
			}
			if seen[real] {
				continue
			}
			fi, err := os.Stat(m)
			if err != nil || fi.Mode()&os.ModeDevice == 0 || fi.Mode()&os.ModeCharDevice != 0 {
				continue
			}
			seen[real] = true
			devs = append(devs, m)
		}
	}
	return devs
}

// extLabel returns the ext2/3/4 volume label of dev (read straight from the
// superblock: magic 0xEF53 at offset 1080, s_volume_name at 1144, 16 bytes),
// or "" if dev isn't an ext filesystem.
func extLabel(dev string) string {
	f, err := os.Open(dev)
	if err != nil {
		return ""
	}
	defer f.Close()
	magic := make([]byte, 2)
	if _, err := f.ReadAt(magic, 1080); err != nil || magic[0] != 0x53 || magic[1] != 0xEF {
		return ""
	}
	buf := make([]byte, 16)
	if _, err := f.ReadAt(buf, 1144); err != nil {
		return ""
	}
	return string(bytes.TrimRight(buf, "\x00"))
}

// probeRecoverySubpart handles the monolithic layout where PRP_ROOTFS is nested
// inside the recovery partition: expose its subpartitions on a partitioned loop
// device and re-scan superblock labels. Best-effort — needs `losetup -P`.
func probeRecoverySubpart() string {
	rec := recoveryDevice()
	if rec == "" {
		return ""
	}
	out, err := exec.Command("losetup", "-fP", "--show", rec).Output()
	if err != nil {
		logf("recovery subpart: cannot expose nested PRP_ROOTFS (losetup -P: %v)", err)
		return ""
	}
	loop := strings.TrimSpace(string(out))
	subs, _ := filepath.Glob(loop + "p*")
	for _, s := range subs {
		if extLabel(s) == prpLabel {
			return s
		}
	}
	_ = exec.Command("losetup", "-d", loop).Run()
	return ""
}

// recoveryDevice finds the recovery partition by its by-name alias or PARTNAME.
func recoveryDevice() string {
	for _, p := range []string{
		"/dev/block/by-name/recovery", "/dev/block/bootdevice/by-name/recovery",
	} {
		if _, err := os.Stat(p); err == nil {
			return p
		}
	}
	uevents, _ := filepath.Glob("/sys/class/block/*/uevent")
	for _, ue := range uevents {
		data, err := os.ReadFile(ue)
		if err != nil {
			continue
		}
		if strings.Contains(string(data), "PARTNAME=recovery\n") {
			dev := "/dev/" + filepath.Base(filepath.Dir(ue))
			if _, err := os.Stat(dev); err == nil {
				return dev
			}
		}
	}
	return ""
}

// haltLoud keeps PID 1 alive (returning would panic the kernel) and offers an
// emergency shell. Last resort when recovery is unavailable.
func haltLoud(reason string) {
	logf("HALT: %s — emergency shell (/bin/sh)", reason)
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

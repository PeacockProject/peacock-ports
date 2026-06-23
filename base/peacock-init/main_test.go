package main

import (
	"os"
	"path/filepath"
	"strings"
	"syscall"
	"testing"
)

func mkExec(t *testing.T, path string) {
	t.Helper()
	if err := os.MkdirAll(filepath.Dir(path), 0o755); err != nil {
		t.Fatal(err)
	}
	if err := os.WriteFile(path, []byte("#!/bin/sh\n"), 0o755); err != nil {
		t.Fatal(err)
	}
}

func TestEntryMode(t *testing.T) {
	if got := entryMode(true); got != "PID+mount namespace" {
		t.Errorf("entryMode(true) = %q", got)
	}
	if got := entryMode(false); got != "chroot" {
		t.Errorf("entryMode(false) = %q", got)
	}
}

func TestOutcomeString(t *testing.T) {
	if got := outcomeExit.String(); got != "init exited" {
		t.Errorf("outcomeExit.String() = %q", got)
	}
	if got := outcomeTimeout.String(); got != "boot timeout" {
		t.Errorf("outcomeTimeout.String() = %q", got)
	}
}

// flavorInitPath picks the flavor's init binary by precedence; getting this
// wrong = the base execs the wrong thing as the flavor's PID 1.
func TestFlavorInitPath(t *testing.T) {
	cases := []struct{ name, mk, want string }{
		{"sbin/init", "/sbin/init", "/sbin/init"},
		{"systemd", "/usr/lib/systemd/systemd", "/usr/lib/systemd/systemd"},
		{"lib systemd", "/lib/systemd/systemd", "/lib/systemd/systemd"},
		{"sh fallback", "/bin/sh", "/bin/sh"},
	}
	for _, tc := range cases {
		t.Run(tc.name, func(t *testing.T) {
			root := t.TempDir()
			mkExec(t, filepath.Join(root, tc.mk))
			if got := flavorInitPath(root); got != tc.want {
				t.Errorf("flavorInitPath = %q, want %q", got, tc.want)
			}
		})
	}
	t.Run("sbin/init beats systemd", func(t *testing.T) {
		root := t.TempDir()
		mkExec(t, filepath.Join(root, "/usr/lib/systemd/systemd"))
		mkExec(t, filepath.Join(root, "/sbin/init"))
		if got := flavorInitPath(root); got != "/sbin/init" {
			t.Errorf("flavorInitPath = %q, want /sbin/init (precedence)", got)
		}
	})
	t.Run("none -> /sbin/init fallback", func(t *testing.T) {
		if got := flavorInitPath(t.TempDir()); got != "/sbin/init" {
			t.Errorf("flavorInitPath(empty) = %q, want /sbin/init", got)
		}
	})
}

func TestFirstExec(t *testing.T) {
	root := t.TempDir()
	mkExec(t, filepath.Join(root, "/usr/bin/b"))
	if got := firstExec(root, "/usr/bin/a", "/usr/bin/b", "/usr/bin/c"); got != "/usr/bin/b" {
		t.Errorf("firstExec = %q, want /usr/bin/b", got)
	}
	if got := firstExec(root, "/usr/bin/x", "/usr/bin/y"); got != "" {
		t.Errorf("firstExec(none) = %q, want \"\"", got)
	}
}

func TestIsExecIsDir(t *testing.T) {
	root := t.TempDir()
	mkExec(t, filepath.Join(root, "tool"))
	if err := os.WriteFile(filepath.Join(root, "plain"), []byte("x"), 0o644); err != nil {
		t.Fatal(err)
	}
	if !isExec(filepath.Join(root, "tool")) {
		t.Error("isExec(executable) = false")
	}
	if isExec(filepath.Join(root, "plain")) {
		t.Error("isExec(non-executable) = true")
	}
	if isExec(root) {
		t.Error("isExec(dir) = true")
	}
	if !isDir(root) {
		t.Error("isDir(dir) = false")
	}
	if isDir(filepath.Join(root, "tool")) {
		t.Error("isDir(file) = true")
	}
}

// extLabel reads the ext volume label straight from the superblock — the
// recovery-rootfs discovery (PRP_ROOTFS) depends on it matching PRP's own probe.
func TestExtLabel(t *testing.T) {
	dir := t.TempDir()

	good := filepath.Join(dir, "good.img")
	buf := make([]byte, 2048)
	buf[1080], buf[1081] = 0x53, 0xEF // ext superblock magic (0xEF53, LE)
	copy(buf[1144:], []byte("PRP_ROOTFS"))
	if err := os.WriteFile(good, buf, 0o644); err != nil {
		t.Fatal(err)
	}
	if got := extLabel(good); got != "PRP_ROOTFS" {
		t.Errorf("extLabel(good) = %q, want PRP_ROOTFS", got)
	}

	bad := filepath.Join(dir, "bad.img")
	b2 := make([]byte, 2048) // no magic
	copy(b2[1144:], []byte("PRP_ROOTFS"))
	if err := os.WriteFile(bad, b2, 0o644); err != nil {
		t.Fatal(err)
	}
	if got := extLabel(bad); got != "" {
		t.Errorf("extLabel(bad magic) = %q, want \"\"", got)
	}

	if got := extLabel(filepath.Join(dir, "missing.img")); got != "" {
		t.Errorf("extLabel(missing) = %q, want \"\"", got)
	}
}

func TestStatusString(t *testing.T) {
	if got := statusString(syscall.WaitStatus(5 << 8)); got != "exit 5" {
		t.Errorf("statusString(exit 5) = %q", got)
	}
	if got := statusString(syscall.WaitStatus(int(syscall.SIGKILL))); !strings.HasPrefix(got, "signal") {
		t.Errorf("statusString(SIGKILL) = %q, want signal …", got)
	}
}

func TestActiveFlavor(t *testing.T) {
	saveAF, saveFR := activeFlavorFile, flavorsRoot
	defer func() { activeFlavorFile, flavorsRoot = saveAF, saveFR }()

	t.Run("reads active-flavor file (trimmed)", func(t *testing.T) {
		tmp := t.TempDir()
		activeFlavorFile = filepath.Join(tmp, "active-flavor")
		flavorsRoot = filepath.Join(tmp, "flavors")
		if err := os.WriteFile(activeFlavorFile, []byte("  arch\n"), 0o644); err != nil {
			t.Fatal(err)
		}
		if got := activeFlavor(); got != "arch" {
			t.Errorf("activeFlavor() = %q, want arch", got)
		}
	})

	t.Run("no file, exactly one flavor -> default to it", func(t *testing.T) {
		tmp := t.TempDir()
		activeFlavorFile = filepath.Join(tmp, "nonexistent")
		flavorsRoot = filepath.Join(tmp, "flavors")
		if err := os.MkdirAll(filepath.Join(flavorsRoot, "alpine"), 0o755); err != nil {
			t.Fatal(err)
		}
		if got := activeFlavor(); got != "alpine" {
			t.Errorf("activeFlavor() = %q, want alpine", got)
		}
	})
}

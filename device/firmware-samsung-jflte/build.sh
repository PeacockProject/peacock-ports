# shellcheck shell=sh
# firmware-samsung-jflte — placeholder firmware package. No source and no
# compile; run_phases already creates $pkgdir, so package() is a no-op that
# simply ensures the (empty) stage dir exists. prepare() is a no-op (no tarball).

prepare() { :; }
build() { :; }
package() { :; }

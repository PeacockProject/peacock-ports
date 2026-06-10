# build_type = "raw"
#
# No build/package defaults: a raw port's ./build.sh must define build()
# and package() (prepare() still extracts unless overridden). For fully
# custom ports — bootloaders, recovery images, anything that doesn't fit
# make/autotools/kernel.
#
# Intentionally empty: the no-op build()/package() from default.sh stand
# until the port overrides them. The harness rejects a raw port that ends
# up with a no-op build() and no build.sh.

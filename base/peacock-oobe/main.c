/* peacock-oobe — PeacockOS base first-boot OOBE + headless blueprint applier.
 *
 * This file implements the HEADLESS --apply mode (no LVGL): fetch + minisign-verify a flavor
 * blueprint and its step scripts, then run the stages, emitting the STEP/PROGRESS/LOG/DONE/ERROR
 * line-protocol on stdout. The framebuffer UI mode (first boot) links the SAME blueprint engine and
 * renders that protocol as a progress bar (P5); the builder execs --apply at build time (P6); PRP
 * runs install.toml via its own embedded copy of the engine (separate recovery image).
 *
 *   peacock-oobe --apply --kind install|oobe --root <path>
 *       ( --base <url> --pubkey <file> | --local <dir> )
 *       [--answers <file>] [--set key=val]... [--secret key=val]...
 *
 * --base fetches+verifies <base>/{install,configure}.toml and each step's <base>/<script>; --local
 * runs an already-present (trusted) blueprint dir. --secret values become $ANS_<key> for the run
 * only and are never written to the answers store (passwords).
 */
#define _POSIX_C_SOURCE 200809L
#include "blueprint.h"
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <unistd.h>
#include <sys/stat.h>

#define WORKDIR "/tmp/peacock-oobe-bp"

/* fbdev UI entry (oobe_uimain.c) — runs the first-boot wizard when invoked without --apply. */
int oobe_run_ui(const char *root, int scale, const char *fbdev);

static void usage(void) {
	fprintf(stderr,
	    "usage: peacock-oobe --apply --kind install|oobe --root <path>\n"
	    "         ( --base <url> --pubkey <file> | --local <dir> )\n"
	    "         [--answers <file>] [--set key=val]... [--secret key=val]...\n");
}

/* split "key=val" in place; returns 1 on success */
static int kv(char *s, char **k, char **v) {
	char *e = strchr(s, '=');
	if (!e) return 0;
	*e = '\0';
	*k = s;
	*v = e + 1;
	return 1;
}

int main(int argc, char **argv) {
	const char *kind = NULL, *root = "/", *base = NULL, *pubkey = NULL, *local = NULL,
	           *answers_file = NULL;
	int apply = 0, ui_scale = 100;
	const char *ui_fbdev = NULL;
	char *set_k[64], *set_v[64];
	size_t n_set = 0;
	char *sec_k[16], *sec_v[16];
	size_t n_sec = 0;

	for (int i = 1; i < argc; i++) {
		if (!strcmp(argv[i], "--apply")) apply = 1;
		else if (!strcmp(argv[i], "--kind") && i + 1 < argc) kind = argv[++i];
		else if (!strcmp(argv[i], "--root") && i + 1 < argc) root = argv[++i];
		else if (!strcmp(argv[i], "--base") && i + 1 < argc) base = argv[++i];
		else if (!strcmp(argv[i], "--pubkey") && i + 1 < argc) pubkey = argv[++i];
		else if (!strcmp(argv[i], "--local") && i + 1 < argc) local = argv[++i];
		else if (!strcmp(argv[i], "--answers") && i + 1 < argc) answers_file = argv[++i];
		else if (!strcmp(argv[i], "--set") && i + 1 < argc) {
			char *k, *v;
			if (kv(argv[++i], &k, &v) && n_set < 64) { set_k[n_set] = k; set_v[n_set] = v; n_set++; }
		} else if (!strcmp(argv[i], "--secret") && i + 1 < argc) {
			char *k, *v;
			if (kv(argv[++i], &k, &v) && n_sec < 16) { sec_k[n_sec] = k; sec_v[n_sec] = v; n_sec++; }
		} else if (!strcmp(argv[i], "--scale") && i + 1 < argc) {
			ui_scale = atoi(argv[++i]);
		} else if (!strcmp(argv[i], "--fbdev") && i + 1 < argc) {
			ui_fbdev = argv[++i];
		} else {
			fprintf(stderr, "peacock-oobe: unknown arg %s\n", argv[i]);
			usage();
			return 2;
		}
	}

	if (!apply) return oobe_run_ui(root, ui_scale, ui_fbdev); /* no --apply: first-boot fbdev UI */
	if (!kind || (strcmp(kind, "install") && strcmp(kind, "oobe"))) {
		fprintf(stderr, "peacock-oobe: --kind install|oobe required\n");
		return 2;
	}
	if (!local && (!base || !pubkey)) {
		fprintf(stderr, "peacock-oobe: need --local <dir> or --base <url> --pubkey <file>\n");
		return 2;
	}

	const char *fname = !strcmp(kind, "install") ? "install.toml" : "configure.toml";
	char toml_path[600], scripts_dir[600], err[256];

	if (local) {
		snprintf(toml_path, sizeof toml_path, "%s/%s", local, fname);
		snprintf(scripts_dir, sizeof scripts_dir, "%s", local);
	} else {
		mkdir(WORKDIR, 0700);
		char url[700];
		snprintf(url, sizeof url, "%s/%s", base, fname);
		snprintf(toml_path, sizeof toml_path, "%s/%s", WORKDIR, fname);
		if (bp_fetch_verify(url, pubkey, toml_path, err, sizeof err) != 0) {
			printf("ERROR fetch %s: %s\n", fname, err);
			return 1;
		}
		snprintf(scripts_dir, sizeof scripts_dir, "%s", WORKDIR);
	}

	bp_blueprint *bp = bp_load(toml_path, err, sizeof err);
	if (!bp) {
		printf("ERROR load %s: %s\n", fname, err);
		return 1;
	}

	bp_answers *a = bp_answers_load(answers_file ? answers_file : "");
	for (size_t i = 0; i < n_set; i++) bp_answers_set(a, set_k[i], set_v[i]);

	/* Expose the (signed-blueprint, therefore trusted) flavor archive + digest so fetch-base.sh can
	 * verify the download. The child sh inherits our environment. */
	if (bp->archive_url) {
		char *u = bp_expand(bp->archive_url, a);
		setenv("BP_ARCHIVE_URL", u ? u : bp->archive_url, 1);
		free(u);
		setenv("BP_ARCHIVE_SHA256", bp->archive_sha256 ? bp->archive_sha256 : "", 1);
	}

	bp_phase phase = !strcmp(kind, "install") ? BP_PHASE_INSTALL : BP_PHASE_OOBE;
	const bp_stage **ord = malloc(sizeof(*ord) * (bp->n_stages ? bp->n_stages : 1));
	size_t n = bp_phase_order(bp, phase, ord);

	int rc = 0;
	for (size_t s = 0; s < n; s++) {
		const bp_stage *st = ord[s];
		if (!bp_when_eval(st->when, a)) {
			bp_set_stage_status(a, st->id, "skipped");
			continue;
		}
		printf("STEP %s\n", st->title ? st->title : st->id);
		if (st->description) printf("LOG %s\n", st->description);
		fflush(stdout);

		/* fetch + verify the step's script before running it */
		if (!local && st->action_script) {
			char surl[800], spath[800], serr[256];
			snprintf(surl, sizeof surl, "%s/%s", base, st->action_script);
			snprintf(spath, sizeof spath, "%s/%s", WORKDIR, st->action_script);
			if (bp_fetch_verify(surl, pubkey, spath, serr, sizeof serr) != 0) {
				printf("ERROR fetch script %s: %s\n", st->action_script, serr);
				rc = 1;
				break;
			}
		}

		if (bp_run_stage_action(st, a, root, scripts_dir, sec_k, sec_v, n_sec, 1) != 0) {
			printf("ERROR stage %s failed\n", st->id);
			bp_set_stage_status(a, st->id, "pending"); /* resumable */
			rc = 1;
			break;
		}
		bp_set_stage_status(a, st->id, "done");
	}

	if (rc == 0) {
		if (phase == BP_PHASE_OOBE) a->oobe_done = 1;
		else a->install_done = 1;
		if (answers_file) bp_answers_save(a, answers_file);
		printf("DONE\n");
	}
	fflush(stdout);

	free(ord);
	bp_answers_free(a);
	bp_free(bp);
	return rc;
}

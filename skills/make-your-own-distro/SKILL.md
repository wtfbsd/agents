---
name: make-your-own-distro
description: Make, build, publish and maintain a user's own BSD distribution end to end from the wtfbsd templates (FreeBSD 16, NetBSD 11.0, OpenBSD 8.0, DragonFly 6.4.2), covering fork and name, overlays on unmodified upstream, media with all firmware inside, a small signed product package repository next to upstream's, Jenkins CI with boot, installer and hardware tests, signed releases with latest.json, and security updates and release rolls. Use when someone wants their own customised BSD desktop or appliance, asks to "make my own BSD", fork the templates into a product, stand up a package repository for a distribution, cut or publish a release of one, or roll a fork to a new upstream release.
---

<!-- Copyright (c) 2026 The wtfbsd contributors. BSD-2-Clause (see LICENSE). -->

# Make your own BSD distribution

You take a user from "I want my own BSD" to a forked, CI-built, tested,
published distribution with its own small package repository, and you
keep it current afterwards. The human guide with the reasoning behind
every stage is `guide/` in wtfbsd/docs; `AGENTS.md` in this repository
holds the Q&A rules. This skill is the procedure.

Placeholders: ExampleBSD, slug `examplebsd`, hosts under `example.org`,
addresses from 192.0.2.0/24. Use the user's real values only in their
own fork, never in the templates.

## Hard rules

1. **Decorate, never fork upstream.** Change only overlay files, package
   lists, `src.conf` knobs (FreeBSD) and your own packages. Never patch an
   upstream source tree or ports tree (FreeBSD ports, pkgsrc, OpenBSD
   ports, DPorts). Adding a directory of your own ports next to them is
   fine.
2. **Upstream packages first.** Every package comes from the upstream
   binary repository unless `ours.list` gives it a reason (Stage 4). The
   product repository holds only those packages.
3. **Layer order**: upstream, baseline overlay, product overlay, packages.
   A product layer only adds.
4. **Everything is in the image.** No firmware or package download at
   install time or first boot.
5. **Keys stay on the signing host.** Never write a private key, token or
   password into git, a log, `answers.yaml`, `product.conf`, a CI
   workspace or a build VM. Secrets reach CI only as Jenkins credentials.
6. **Honesty.** Mirror the `per_os` rows of `questions.yaml`. Never offer a
   combination they forbid. Never claim a test passed that did not run,
   or a platform works that was not booted.
7. **No invented commands.** Use only commands and flags shown here, in
   the template READMEs, or in a manual page you read on the target
   system. When unsure of a flag, read the man page; if you cannot, say
   "check <page>" to the user instead of guessing.
8. **Missing piece: stop and say so.** If a script or file this skill
   names does not exist in the checkout, report it and stop that stage.
   Do not hand-emulate it.
9. **Every check must be able to fail.** A check that read nothing
   reports "could not look" (exit 2), not a pass. Prove a new check red
   once on a known-bad input before trusting its green.
10. **Look up the current upstream releases** at the start of every
    session. The versions in this file go stale. (As written, FreeBSD 16
    is 16-CURRENT; there is no 16.0-RELEASE yet, the newest is 15.1.)

Each stage below has: **Inputs**, **Do**, **Check** (what proves it
worked) and **On failure**. Do not start a stage until the previous
stage's check passed.

---

## Stage 0: preflight

**Inputs:** a clone of wtfbsd/agents; network access to GitHub.

**Do:**

1. Read `questions.yaml` and `AGENTS.md` in full.
2. Run the repository's own tests: `tests/run-tests.sh`.
3. Note which templates exist and their state: `wtfbsd/<os>-template`,
   `installer-template`, `ports-templates`, `ci-templates`. Today
   `ports-templates` and `ci-templates` are placeholders; the Jenkinsfile
   ships in each OS template.

**Check:** `tests/run-tests.sh` exits 0.

**On failure:** stop; report the failing test. Do not work around a broken
contract.

## Stage 1: questions and product.conf

**Inputs:** the user's answers.

**Do:**

1. Run the Q1..Q10 interview exactly as `AGENTS.md` Phase 1 says (one
   numbered step per message, validate each answer, quote the honesty
   note before accepting a filesystem or ZFS answer).
2. Write `answers.yaml` (flat `KEY: value` lines; see `examples/`).
3. Validate, then write:

   ```sh
   scripts/apply-answers.sh -c answers.yaml
   scripts/apply-answers.sh answers.yaml          # writes ./product.conf
   ```

**Check:** both commands exit 0; `product.conf` contains every question id
as `KEY='value'`.

**On failure:** exit 3 names the key and the rule it broke. Re-ask that
question; never edit `product.conf` by hand. Exit 2 is a usage error in
your command.

## Stage 2: fork

**Inputs:** `product.conf`; `gh` logged in with rights on `PUBLISHER_ORG`.

**Do:**

```sh
scripts/fork-distro.sh --os <DISTRO_OS> --name '<DISTRO_NAME>' \
    --slug <DISTRO_SLUG> --org <PUBLISHER_ORG>            # dry run first
scripts/fork-distro.sh --os <DISTRO_OS> --name '<DISTRO_NAME>' \
    --slug <DISTRO_SLUG> --org <PUBLISHER_ORG> --apply
```

The script forks `<os>-template`, `ports-templates`, `installer-template`
and `ci-templates` to `<slug>`, `<slug>-ports`, `<slug>-installer` and
`<slug>-ci`, and sets their descriptions. It does **not** clone them or
copy `product.conf`. Then:

```sh
gh repo clone <PUBLISHER_ORG>/<slug>
cp product.conf <slug>/product.conf
```

**Check:** `gh repo view <PUBLISHER_ORG>/<slug>` succeeds for all four; in
the clone, `./build.sh -c product.conf -n` exits 0 (works on any POSIX
host).

**On failure:** exit 3 with "already exists" means an earlier run made
some forks; ask the user before deleting anything. "gh is not
authenticated": ask the user to run `gh auth login`.

## Stage 3: overlays and profiles

**Inputs:** the clone; what the user wants on the system.

**Do:**

1. Put files under `overlay/base/rootfs/` (every image) or
   `overlay/profiles/<desktop|appliance>/rootfs/` (one profile). Profile
   files are copied after base.
2. Use the OS's own configuration mechanism (template README, "Overlay
   rules"): FreeBSD and NetBSD `rc.conf.d/<service>` named after the
   service (NetBSD values are `name=YES`); OpenBSD one `rc.conf.local`
   with profile fragments appended; DragonFly rc variables merged by
   `tools/post-customize.sh`.
3. Use the placeholders `@DISTRO_NAME@`, `@SLUG@`, `@MOTD@`, `@BRAND_URL@`
   instead of literal names; a path with `@SLUG@` in it is renamed.
4. Keep root locked. The first account comes from the `firstboot_user`
   rc script (FreeBSD, NetBSD, DragonFly) or the installer's response file
   (OpenBSD).
5. For a second product from the same base, split shared mechanisms into
   a baseline overlay in the same change; delete the copy from the first
   product.

**Check:** `tests/run-tests.sh` exits 0 (includes the leak check);
`./build.sh -c product.conf -n -p both` shows base before profile and the
expected files; `git diff --stat` touches only `overlay/`, package lists,
`product.conf` and files you added.

**On failure:** a leak-check failure names the file and pattern: replace
the value with a placeholder. A placeholder left unsubstituted means a
file name or key typo.

## Stage 4: decide upstream or ours, per package

**Inputs:** the package lists; the user's customisations.

**Do:**

1. For each needed package ask: is upstream's binary package, as built,
   what we want? Yes: list it in `packages.list`, done.
2. Otherwise it is **ours**, for exactly one reason: `product` (content
   only we have), `meta` (depends on upstream packages, no files),
   `patched` (a fix upstream has not shipped), `options` (non-default
   build options), `missing` (upstream does not package it).
3. Record each in `<slug>-ports/ours.list`, one line per package:
   `name reason note`. Name new packages `<slug>-<thing>`.
4. Prefer `product` and `meta` packages: no compiled code, no ABI
   breakage when upstream moves.
5. Install this check as `<slug>-ports/tests/ours-check.sh`:

```sh
#!/bin/sh
# Copyright (c) 2026 The wtfbsd contributors. BSD-2-Clause (see LICENSE).
# ours-check.sh OURS_LIST PUBLISHED [UPSTREAM_NV PUBLISHED_NV]
#   OURS_LIST     lines "name reason note...", reason one of
#                 product meta patched options missing
#   PUBLISHED     package names in the product repository, one per line
#   UPSTREAM_NV   optional: name-version lines of the upstream repository
#   PUBLISHED_NV  optional: name-version lines of the product repository
# exit 0 pass, 1 fail, 2 could not look
set -eu
[ $# -eq 2 ] || [ $# -eq 4 ] || { echo "usage: $0 OURS_LIST PUBLISHED [UPSTREAM_NV PUBLISHED_NV]" >&2; exit 2; }
for f in "$@"; do [ -f "$f" ] && [ -r "$f" ] || { echo "cannot read $f: could not look"; exit 2; }; done
tmp=$(mktemp -d) || exit 2
trap 'rm -rf "$tmp"' EXIT
st=0
awk -v bad="$tmp/bad" '!/^[[:space:]]*#/ && NF {
        if (NF < 3 || $2 !~ /^(product|meta|patched|options|missing)$/)
            print $1 > bad
        print $1
     }' "$1" | sort -u > "$tmp/listed"
if [ -s "$tmp/bad" ]; then
    sed 's/^/ours.list line without a valid reason and note: /' "$tmp/bad"; st=1
fi
sort -u "$2" > "$tmp/published"
[ -s "$tmp/published" ] || { echo "no published package names read: could not look"; exit 2; }
comm -23 "$tmp/published" "$tmp/listed" > "$tmp/extra"
if [ -s "$tmp/extra" ]; then
    sed 's/^/published but not in ours.list: /' "$tmp/extra"; st=1
fi
if [ $# -eq 4 ]; then
    sort -u "$3" > "$tmp/up"; sort -u "$4" > "$tmp/pubnv"
    [ -s "$tmp/up" ] || { echo "no upstream name-versions read: could not look"; exit 2; }
    comm -12 "$tmp/up" "$tmp/pubnv" > "$tmp/same"
    if [ -s "$tmp/same" ]; then
        sed 's/^/identical to upstream, take it from upstream: /' "$tmp/same"; st=1
    fi
fi
[ "$st" -eq 0 ] && echo "ours-check: pass ($(wc -l < "$tmp/published" | tr -d ' ') self-hosted packages, each with a reason)"
exit "$st"
```

   Feed it on FreeBSD or DragonFly (repository names as in the client
   files; on FreeBSD 16 upstream is `FreeBSD-ports` plus
   `FreeBSD-ports-kmods`, on DragonFly the name in `df-latest.conf`):

```sh
pkg update -f
pkg rquery -a -r ExampleBSD '%n' > published.txt
pkg rquery -a -r ExampleBSD '%n-%v' > published.nv
pkg rquery -a -r FreeBSD-ports -r FreeBSD-ports-kmods '%n-%v' > upstream.nv
sh tests/ours-check.sh ours.list published.txt upstream.nv published.nv
```

   On NetBSD read `PKGNAME=` lines from each repository's `pkg_summary.gz`
   (name-version) and strip the version for the name list; on OpenBSD use
   the file names in the repository directory without `.tgz`.

**Check:** prove the check red once: add a line `bogus` to a copy of
`ours.list` with no reason and see exit 1. Then the real run exits 0.

**On failure:** for each "published but not in ours.list", either give it
a reason or stop publishing it. For "identical to upstream", delete it
from the product repository. "Could not look" means the query returned
nothing: check the repository URL and signature (Stage 5), never treat it
as a pass.

## Stage 5: build, sign and serve the product repository

**Inputs:** `ours.list`; a signing host the user controls; a static HTTPS
host (`https://pkg.example.org/`).

**Do:**

1. Signing key, once, on the signing host, by the user or with their
   explicit go-ahead. FreeBSD and DragonFly:

   ```sh
   umask 077
   openssl genrsa -out /root/keys/examplebsd-repo.key 4096
   openssl rsa -in /root/keys/examplebsd-repo.key -pubout -out examplebsd-repo.pub
   ```

   OpenBSD: `signify -G -n -c "examplebsd 8.0 packages" -p
   examplebsd-80-pkg.pub -s examplebsd-80-pkg.sec` (keep the `pkg`
   suffix: `pkg_add` trusts `*pkg` keys by default). NetBSD: X.509 or GPG
   via `pkg_admin x509-sign-package PKG SPKG KEY CERT` or
   `pkg_admin gpg-sign-package PKG SPKG`; clients enforce with
   `VERIFIED_INSTALLATION` (default `never`; `always` also refuses
   unsigned upstream packages) plus `CERTIFICATE_ANCHOR_PKGS`.
2. Build only the packages in `ours.list`:
   - data/meta packages on FreeBSD: `pkg create -m meta/ -p plist -r
     stage -o out/` (`meta/` holds `+MANIFEST`; `-p` is refused with
     `-M`); set `abi`, `FreeBSD:16:*` for architecture-independent data;
   - compiled, FreeBSD: `poudriere jail -c -j 160amd64 -v 16.0-RELEASE -a
     amd64` (no 16.0-RELEASE exists until FreeBSD 16.0 ships: use the
     newest release, or `-m git+https -v main`); `poudriere ports -c -p
     default`; `poudriere ports -c -p examplebsd -m null -M
     <slug>-ports-checkout`; `poudriere bulk -j 160amd64 -p default -O
     examplebsd -f /abs/path/ours.origins` (origins of the compiled
     `ours.list` entries; `-f` needs an absolute path). `-b latest`
     fetches upstream binaries for dependencies; then list every
     `patched`/`options` package in `PACKAGE_FETCH_BLACKLIST`. Use the
     ports branch matching the upstream repository consumed (quarterly
     or latest);
   - NetBSD: `make package` per package directory (or pbulk); then
     `for p in *.tgz; do pkg_info -X "$p"; done | gzip -9 > pkg_summary.gz`;
   - OpenBSD: ports under `/usr/ports/mystuff/`, `make package` or
     `dpb(1)`; sign with `pkg_sign -C -s signify2 -s
     examplebsd-80-pkg.sec -o signed/ -S unsigned/`;
   - DragonFly: `dsynth build <origins>` on DragonFly; dsynth reads one
     ports tree (`Directory_portsdir`) with no overlay, so add your
     category directory inside a DPorts checkout; it does not sign.
3. Copy **only** this run's `ours.list` packages into a fresh dated
   directory. FreeBSD/DragonFly: `pkg repo <dir> /root/keys/examplebsd-repo.key`
   (also `rsa:KEYFILE`; or `signing_command: ssh <signing host> sign.sh`
   with `fingerprints` on clients). Never run `pkg repo` (with or
   without `-l`) to verify: every run rewrites the catalogue, unsigned
   without the key.
4. Publish atomically under one lock (one writer only): verify the new
   directory, then point the `latest` symlink at it. Keep the previous.
5. Client files in `overlay/base/rootfs/`, upstream file untouched:
   FreeBSD/DragonFly `usr/local/etc/pkg/repos/ExampleBSD.conf`:

   ```
   ExampleBSD: {
     url: "https://pkg.example.org/${ABI}/latest",
     signature_type: "pubkey",
     pubkey: "/usr/local/etc/pkg/keys/examplebsd-repo.pub",
     enabled: yes,
     priority: 10
   }
   ```

   plus the public key at that path. NetBSD: pkgin `repositories.conf`
   with the product URL first (first listed wins), then upstream's;
   `PKG_PATH` entries are separated by `;`. OpenBSD:
   `etc/signify/examplebsd-80-pkg.pub`; `/etc/installurl` is used only
   while `PKG_PATH` is unset, so set
   `PKG_PATH=<product url>:installpath` (colon-separated).

**Check:** from a VM booted from your image (not the builder):
`pkg update -f` shows no "no trusted public keys" message;
`pkg rquery -r ExampleBSD '%n-%v'` lists exactly this run's packages
(count them: an empty repository can exit 0); `pkg install -n
<slug>-desktop` resolves dependencies from upstream; Stage 4's
`ours-check.sh` exits 0.

**On failure:** an empty repository with exit 0 is a signing mismatch
(key file vs `signing_command`, `pubkey` vs `fingerprints`): fix the
client file to match the signing mode. "Wrong OS version" means packages
built for a newer base than the client: rebuild in a jail of the client's
release. Never copy the private key to the builder to make CI green.

## Stage 6: build media with all firmware

**Inputs:** the fork; a build host per the template (FreeBSD on FreeBSD;
NetBSD base and image on any POSIX host, its package step on NetBSD
only; OpenBSD: the site set on a FreeBSD or Linux host,
the media step on OpenBSD as root through one `doas` rule; DragonFly on
DragonFly, as root).

**Do:**

```sh
./build.sh -c product.conf -n -p both                             # always first
./build.sh -c product.conf -p both                                # FreeBSD
PKG_PATH='<product repo>;<upstream repo>' ./build.sh -c product.conf -p both   # NetBSD (on NetBSD)
./build.sh -c product.conf -r 8.0 -p both -u operator -k operator.pub -P operator.hash   # OpenBSD
DPORTS_PATH=/usr/dports ./build.sh -c product.conf -p both -u ci -k ci.pub      # DragonFly
```

1. FreeBSD: make the package step install from upstream plus the product
   repository (`pkg -R <dir with both repository files> -r <stage>
   install`; `-R` replaces `REPOS_DIR`, so copy `/etc/pkg/FreeBSD.conf`
   in too; this is a change to the fork's `build.sh`).
2. Firmware: list firmware packages for every device you support in the
   profile `packages.list` (FreeBSD: `drm-kmod` pulls
   `gpu-firmware-kmod`; add `wifi-firmware-kmod`). OpenBSD: fetch firmware
   at build time, verify against the signed `SHA256.sig` with `signify -C`,
   carry it with `SHA256.sig` in the site set, and in `install.site`
   run `fw_update -p <dir> -a` (verifies `SHA256.sig`; never pass
   `.tgz` files as arguments, those are not verified) and remove the
   `fw_update` line the installer adds to `/etc/rc.firsttime`.
   NetBSD/DragonFly: firmware mostly ships in base; read the driver man
   pages.
3. Add a firmware coverage gate after the package step: what drivers can
   ask for vs what the image contains; fail on any gap not in a checked-in
   allowlist with a reason per line; write the firmware list next to the
   image. The templates do not have this gate yet: add it to the fork.
4. After the package step, check every listed package is installed
   (`pkg -r <stage> info <name>` on FreeBSD): `pkg install` can exit 0
   having installed nothing.

**Check:** `out/SHA256` exists and each file's checksum matches it;
every expected artifact exists (one image, and ISO where the template
makes one, per profile); the firmware gate passed and wrote its list;
`sh tests/boot-test.sh <image> <profile>` reaches `login:`.

**On failure:** a build that finishes in seconds produced nothing: count
artifacts. Start re-runs from an empty `-o` directory (`mkimg` will not
overwrite). DragonFly cannot cross-build, and the OpenBSD media step needs OpenBSD:
use a native VM.

## Stage 7: CI

**Inputs:** a Jenkins controller the user runs; an agent labelled
`bsd-builder` (FreeBSD with bhyve) or a provider script of their own.

**Do:**

1. Create a pipeline job from the fork's `Jenkinsfile` (install the File
   Parameter plugin for `PRODUCT_CONF`). Its first run must be a plain
   build: a never-run job declares no parameters yet.
2. Prepare the agent per the template README: `pkg install edk2-bhyve`,
   `kldload vmm`, `kldload if_bridge`, `kldload if_tap`, `ifconfig bridge0
   create`, `ifconfig bridge0 up`. A site provider script set with
   `WTFBSD_VM_PROVIDER_PATH` must be root-owned and not writable by job
   authors.
3. Add what the templates lack: a desktop greeter screenshot in the boot
   test; an installer E2E stage (boot the ISO as a CD, install
   unattended to an empty disk, reboot from the disk without the ISO,
   log in with a per-run SSH key, check the root filesystem on the
   installed system); a real-hardware stage on an agent label that owns
   test machines (GPU driver loaded, firmware found, Wi-Fi interface
   present, greeter on screen).
4. Chain jobs: a green package build always publishes (Stage 5), and the
   publish triggers the media job.

**Check:** a push triggers a build with no click; a deliberately broken
overlay file turns the build red (then revert it); after every run no VM
is left (the FreeBSD `post` fails the build on a failed destroy; the
NetBSD, OpenBSD and DragonFly ones ignore it with `|| true`: make the
fork's fail); a package publish starts a media build.

**On failure:** when reading results, wait for a build number higher
than the last one seen; a queue id is not a build number. `timeout` does
not stop bhyve: use `timeout -k 10 N` and `bhyvectl --destroy --vm=NAME`.
A green bulk with your package skipped is a failure: check the built
list.

## Stage 8: release and publish

**Inputs:** a green media run (build, boot, installer, hardware stages).

**Do:**

1. Publish that run's artifacts by build number; never rebuild for a
   release. Names: `ExampleBSD-<version>-<profile>-<arch>-<build>.<ext>`,
   never `-latest`.
2. Checksums in BSD format and a signature, on the signing host:

   ```sh
   signify -S -e -s examplebsd-release.sec -m SHA256 -x SHA256.sig
   ```

   (FreeBSD `sha256 FILE`, not `sha256 -r`, prints the format `signify -C`
   reads; read `signify(1)`.)
3. Generate `latest.json` from the artifact files (schema in
   wtfbsd/docs `guide/06-release-and-publish.md`): `schema_version`,
   `product`, `generated_at`, `channel`, `status`, `notice`,
   `architectures[]` with `arch`, `build_number`, `published_at`, `iso`,
   `artifacts[]` (`kind`, `format`, `filename`, `size_bytes`, `sha256`,
   `url`, `sha256_url`, `torrent_url`). Write `latest.next.json`, verify
   every URL by length and checksum, then rename it.
4. Release notes: upstream release, template and overlay commits, files
   and checksums, what was and was not tested, firmware list and gaps,
   known problems, repository URL and public keys.
5. Upload to the static host: copy new, verify, then remove old; keep the
   previous release. If `PUBLISH_METHOD`/`PUBLISH_TARGET` are set, run
   the publish step of `AGENTS.md` Phase 5 with the Jenkins credential.
6. Regenerate the project site from `latest.json`.

**Check:** on a fresh download, `signify -C -p examplebsd-release.pub -x
SHA256.sig` passes; `latest.json` validates against the schema; every URL
in it returns the listed size and checksum; the site shows the release.

**On failure:** never edit `latest.json` by hand to make it pass; fix the
generator or the upload. A 200 with the wrong length is a missing file
behind a fallback page.

## Stage 9: operations (repeat)

**Inputs:** upstream security advisories and release announcements.

**Do:**

1. Per advisory: does it hit a package in `ours.list` or on the media?
   Rebuild and publish (Stage 5), which triggers new media (Stage 6-8).
   Upstream packages reach users through upstream; OpenBSD base patches
   through `syspatch(8)`.
2. Per new upstream release: new builder next to the old one; point the
   build at it (FreeBSD `-s` source tree, NetBSD source tree and
   `PKG_PATH`, OpenBSD `-r`, DragonFly source and DPorts); review
   `ours.list` and drop what upstream now ships; rebuild compiled
   packages for the new ABI into a new ABI directory; run every stage's
   check; release.
3. Versions: `ExampleBSD <upstream release>-<revision>`; CI build number
   in file names; package versions that only go up.

**Check:** the latest published media and repository are built from the
latest upstream release and include every fix for packages in
`ours.list`; `ours-check.sh` still passes.

**On failure:** "wrong OS version" on clients: packages were built for a
newer base than clients run; publish per ABI. Keep the previous release
and repository online until its end of life.

---

## Done checklist

- [ ] `product.conf` from `apply-answers.sh`; four forks exist; dry run ok.
- [ ] Overlay only; no upstream tree touched; leak check green.
- [ ] `ours.list` has a reason for every self-hosted package;
      `ours-check.sh` proven red once, then green on the live repository.
- [ ] Product repository signed, served over HTTPS, verified from a
      client; client files and public key in the overlay.
- [ ] Media built with all firmware inside; firmware gate green.
- [ ] CI builds, boot-tests, installer-tests and hardware-tests
      unattended; package publish triggers media.
- [ ] Release published by build number with signed checksums,
      `latest.json`, release notes and site.
- [ ] No private key, token or real host name in any repository or log.

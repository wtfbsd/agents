# AGENTS.md — helping a user create their own BSD distribution

You are the AI coding agent driving the wtfbsd question flow. You take a user
from a short Q&A to their own forked, Jenkins-built, bhyve-tested and published
BSD distribution. The wtfbsd templates do the heavy lifting; your job is to ask
the right questions in the right order, mirror the honest per-OS facts, and only
then touch files, scripts and CI.

Pipeline at a glance:

1. **Phase 1 — Q&A**: interview the user with the `questions.yaml` questions,
   write `answers.yaml`, run `scripts/apply-answers.sh answers.yaml` → `product.conf`.
2. **Phase 2 — Fork**: `scripts/fork-distro.sh` forks the four template repos
   under the user's own org and drops `product.conf` in.
3. **Phase 3 — Jenkins build**: a throwaway bhyve VM builds base + overlay +
   packages per chosen profile → ISO, raw/qcow2 image, SHA256 file.
4. **Phase 4 — bhyve E2E**: a second throwaway VM boots that ISO, installs
   unattended and reboots; greeter screenshot (desktop) or serial + SSH (appliance).
5. **Phase 5 — Publish**: upload release metadata plus the SHA256 file to
   `PUBLISH_TARGET` with a token that never leaves Jenkins credentials.

## 0. The contract: read questions.yaml first

Read `questions.yaml` in this repository before anything else, every session. It
is the contract between three things: this file (how the agent asks the
questions), `answers.yaml` (what the user answered), and
`scripts/apply-answers.sh` (which validates the answers and emits
`product.conf`). From it you need, verbatim:

- `per_os` — what is honestly possible per base OS (arch, root_fs, installer,
  zfs_pool). These rows are the source of truth.
- `per_os_honesty` — the exact user-facing notes to quote when a user asks for a
  combination a row forbids.
- `per_os_build` — how each base OS is actually built.
- `default_from_os` — which per_os column backfills `DISTRO_ARCH`,
  `FILESYSTEM_ROOT` and `INSTALLER` when the user gives no answer.
- `questions` — every `id`, `number`, `prompt`, `type`, `choices`, `pattern`,
  `min`/`max`, `default`, `required`/`required_if` and `notes`.

The question ids are exactly the `answers.yaml` keys and exactly the
`product.conf` keys. The `number` field is the question number in the Phase 1
interview (Q1..Q10). Refer to every id and number exactly as written; never
rename or renumber ids — product.conf files exist downstream once made. Mirror
`per_os` and `per_os_honesty` in your prose; when user requests and tables
disagree, the tables win.

## 1. Ground rules

- **Overlay only, never fork upstream.** Everything the product adds is an
  overlay on unmodified upstream source trees. Never fork or patch an upstream
  tree (system sources, ports/pkgsrc/DPorts trees included). All product
  specific work lives inside the forked template repos, in the overlay layers
  described below.
- **Three overlay layers on every base-OS template**: `overlay/base` (common to
  every product), `overlay/profiles/desktop` and `overlay/profiles/appliance`.
  What gets built on top of base is decided by the `PROFILE` answer.
- **Desktop profile is X11-only, Xfce, fixed.** No Wayland for now. The
  desktop is Xfce on Xorg with the LightDM greeter; where LightDM is not
  available on a base OS, use that OS's native xdm or slim instead. There is
  no desktop-environment or display-server question: never offer Wayland,
  GNOME, KDE or another DE.
- **Generic branding only.** All artwork, wallpapers, boot and greeter
  branding in the templates is generic "ExampleBSD"; products replace it in
  their own overlay.
- **One worked ExampleBSD per base OS** (freebsd, netbsd, openbsd, dragonfly,
  illumos) exists as reference. When unsure how a finished product should look —
  the shape of `answers.yaml`, `product.conf`, an overlay, or a green Jenkins
  run — mirror the matching ExampleBSD example.
- **Jenkins is the only supported CI.** Forks may contain a disabled sample
  GitHub Actions file; leave it disabled, never wire it up.
- **Builds and tests run in throwaway bhyve VMs.** Create for one job, destroy
  when the job ends. A disposable VM's name carries the build number only.
- **Never commit tokens.** No secret may be echoed to a log, written into git,
  or put into `answers.yaml`/`product.conf`. Secrets travel only through Jenkins
  credentials (see Phase 5).
- **Honesty is non-negotiable.** Never imply a combination a `per_os` row
  forbids is possible. Quote the matching `per_os_honesty` note before accepting
  a filesystem or ZFS answer, offer the closest honest alternative, and re-ask.
- **Placeholder hostnames only**: use `example.org` for everything you invent.
  No real IP addresses, no live hostnames except contract defaults.
- **No destructive shortcuts**: never `rm -rf` a path held in a variable that
  may be empty or unquoted. Name the path, or guard a non-empty expansion.
- **Do not improvise missing pieces.** This repository may be a stub; if a
  script or template referenced here (e.g. `scripts/apply-answers.sh`) is not
  present yet, say so plainly and stop at that step instead of hand-emulating it.

## 2. Phase 1 — Q&A: from answers to product.conf

Read `questions.yaml` again, then run the interview. Ask questions **in number
order, one at a time**: exactly one numbered step per message, waiting for the
answer before the next. Ids sharing a number form one conversational step; ask
them together in the file's id order. Validate every answer against
`questions.yaml` (type, choices, `pattern`, `min`/`max`, `required`,
`required_if`) before moving on. An empty or "don't care" answer records the
default — the question's own `default`, or, for `DISTRO_ARCH`, `FILESYSTEM_ROOT`
and `INSTALLER`, the first entry of the DISTRO_OS row in the column named by
`default_from_os`.

Load these facts before the interview (mirror of `per_os`; the `per_os_honesty`
notes appear under each row, as you must quote them):

- **freebsd** — arch: amd64, aarch64 · root_fs: zfs, ufs · installer: tui, gui ·
  zfs_pool: yes. Honesty: "ZFS is first-class on FreeBSD: fully supported as the
  root filesystem and for data pools. UFS is the classic alternative."
- **netbsd** — arch: amd64, aarch64 · root_fs: ffs · installer: tui ·
  zfs_pool: data-only. Honesty: "ZFS pools work for data storage only; the root
  filesystem stays FFS. Root-on-ZFS is not supported."
- **openbsd** — arch: amd64, aarch64 · root_fs: ffs · installer: tui ·
  zfs_pool: no. Honesty: "No ZFS at all. FFS is the only filesystem choice."
- **dragonfly** — arch: amd64 · root_fs: hammer2, ufs · installer: tui ·
  zfs_pool: no. Honesty: "The native filesystem is HAMMER2 (UFS is also
  available). No ZFS."
- **illumos** — arch: amd64 · root_fs: zfs · installer: tui · zfs_pool: yes.
  Honesty: "ZFS is native here: fully supported for the root filesystem and
  data pools."

Build facts (`per_os_build`) to relay at Q1: **freebsd** release(7) world and
kernel plus a poudriere ports overlay, on a FreeBSD build host; **netbsd**
build.sh plus pkgsrc (pbulk), cross-builds from any POSIX host; **openbsd**
release(8) plus dpb over the ports tree, must build natively on OpenBSD;
**dragonfly** make buildworld/buildkernel plus nrelease with DPorts (dsynth)
packages; **illumos** illumos-gate plus an OmniOS-style distro builder with IPS
(pkgsrc for extras), needs a large bootstrap VM.

### The interview, Q1..Q10

1. **Q1 — `DISTRO_OS`** (choice). freebsd, netbsd, openbsd, dragonfly or
   illumos. No default: always ask. After the answer, relay that OS's
   `per_os_build` facts so the user knows what the build implies.
2. **Q2 — `DISTRO_NAME` and `DISTRO_SLUG`** (both required, no default).
   - `DISTRO_NAME`: human-facing name, 1–64 characters, no control characters
     (`^[^[:cntrl:]]+$`). Documentation placeholder: ExampleBSD.
   - `DISTRO_SLUG`: `^[a-z][a-z0-9-]*$`, 2–32 characters. Becomes the repository
     names `<slug>`, `<slug>-ports`, `<slug>-installer`, `<slug>-ci`.
     Placeholder: examplebsd.
3. **Q3 — `DISTRO_ARCH`** (choice). amd64 or aarch64. Default: first `arch`
   entry of the OS row (amd64 for every row today); the fixed
   fallback default is amd64. DragonFly and illumos rows
   are amd64 only — do not offer aarch64 there even though the question lists it.
4. **Q4 — the filesystem step** (ids in file order: `FILESYSTEM_ROOT`,
   `ZFS_DATA_POOL`, `ZFS_POOL_NAME`).
   - `FILESYSTEM_ROOT` (choice: zfs, ufs, ffs, hammer2): must be inside the
     row's `root_fs` column. Defaults to the first `root_fs` entry. Quote the
     row's `per_os_honesty` note before accepting. concretely: FreeBSD allows
     zfs or ufs; NetBSD and OpenBSD allow ffs only; DragonFly allows hammer2 or
     ufs; illumos allows zfs only. A NetBSD, OpenBSD or DragonFly root cannot be
     ZFS.
   - `ZFS_DATA_POOL` (choice: yes, no; default no): allowed only where the row's
     `zfs_pool` is `yes` (freebsd, illumos) or `data-only` (netbsd). On
     data-only OSes this is the honest way to give a user who asked for
     "NetBSD with ZFS" what they actually want. On rows with `zfs_pool: no`
     (openbsd, dragonfly), say plainly that no ZFS pool is possible and record
     `no` — do not offer yes.
   - `ZFS_POOL_NAME`: asked only when `ZFS_DATA_POOL=yes`;
     `^[a-z][a-z0-9-]*$`, 1–29 characters. Placeholder: exampledata.
5. **Q5 — `PROFILE`** (choice: desktop, appliance, both; default appliance).
   Selects `overlay/profiles/desktop` and/or `overlay/profiles/appliance` on top
   of `overlay/base`, and with it which Jenkins builds and bhyve tests run.
   The desktop path is fixed: Xfce on X11 (Xorg) with LightDM, or the OS's
   native xdm or slim where LightDM is unavailable. No Wayland, no DE choice.
6. **Q6 — `PACKAGE_SET`** (choice: minimal, base-server, base-desktop, custom;
   default minimal). `custom` means: edit the package list in the product repo
   after forking; the templates install minimal plus whatever the product repo
   adds.
7. **Q7 — `INSTALLER`** (choice: tui, gui). TUI is available on every OS
   (bsddialog-style); GUI is worked out per-OS in installer-template and is only
   available where the row's `installer` column lists it (today: freebsd).
   Default: the first `installer` entry (tui everywhere today).
8. **Q8 — the branding step** (ids in file order: `MOTD`, `BRAND_COLOR`,
   `BRAND_URL`).
   - `MOTD`: one printable line, no control characters, at most 120 characters.
     Default: `built from the wtfbsd templates`.
   - `BRAND_COLOR`: accent color as exactly 6 hex digits, stored without the
     leading `#` (`RRGGBB`, e.g. `3b6ea5`; templates prepend `#`). Default: `3b6ea5`.
   - `BRAND_URL`: `^https://[A-Za-z0-9.-]+$`, at most 200 characters — the
     pattern makes https mandatory. Default: `https://wtfbsd.ai`. Shown in
     installer footers and on the release page.
9. **Q9 — `CI_ENABLED`** (choice: yes, no; default yes). Jenkins in a throwaway
   bhyve build VM is the supported CI. With `no`, builds are run by hand with
   the build template and no release is auto-published.
10. **Q10 — the publishing step** (ids in file order: `PUBLISH_METHOD`,
    `PUBLISH_TARGET`, `PUBLISHER_ORG`).
    - `PUBLISH_METHOD` (choice: api, mcp; default api). `api` = the HTTPS
      release API on the publish target. `mcp` = the target's MCP publish tool.
      Either way the token comes from the user's own account settings and lives
      only as a Jenkins credential.
    - `PUBLISH_TARGET`: hostname only, no scheme (`^[a-z0-9][a-z0-9.-]+$`,
      3–64 characters). Default: `wtfbsd.ai`.
    - `PUBLISHER_ORG`: the GitHub org or account that will own the forks
      (`^[A-Za-z0-9][A-Za-z0-9-]+$`, 2–64 characters). Default: `wtfbsd`. Same
      value passed to `fork-distro.sh --org`; the user needs permission to
      create repositories there.

If the user insists on a combination a row forbids even after the honesty note,
do not write it into `answers.yaml`; state the limit once more and propose the
closest honest alternative.

### Writing answers.yaml and product.conf

When Q10 is answered:

1. Write `answers.yaml` in the style of the answers files shipped in the
   wtfbsd examples — one key per question id, plain scalar values, abiding by
   the wtfbsd YAML subset (whole-line comments and blank lines; `key: value`
   scalars on one line; inline lists `[a, b, c]`; no block scalars, no
   anchors/aliases, no multi-line strings, no tabs, no quoting inside `{ ... }`
   rows, no `#` inside values). Keys absent from the file fall back to their
   contract defaults. Sketch:

   ```yaml
   # answers.yaml — keys are exactly the questions.yaml ids; placeholders below.
   DISTRO_OS: freebsd
   DISTRO_NAME: ExampleBSD
   DISTRO_SLUG: examplebsd
   DISTRO_ARCH: amd64
   FILESYSTEM_ROOT: zfs
   ZFS_DATA_POOL: no
   PROFILE: both
   PACKAGE_SET: minimal
   INSTALLER: tui
   MOTD: built from the wtfbsd templates
   BRAND_COLOR: 3b6ea5
   BRAND_URL: https://example.org
   CI_ENABLED: yes
   PUBLISH_METHOD: api
   PUBLISH_TARGET: example.org
   PUBLISHER_ORG: example-org
   ```

2. Produce the product configuration from it:

   ```sh
   scripts/apply-answers.sh answers.yaml    # validates, fills defaults, writes product.conf
   ```

   `product.conf` keys are exactly the question ids with the resolved values.
   Do not hand-edit `product.conf`: fix `answers.yaml` and re-run. A non-zero
   exit means a row refused a value — re-ask that question honestly.

`answers.yaml` contains no secrets by design; committing it is fine.

## 3. Phase 2 — Fork the product

With `product.conf` in hand:

```sh
scripts/fork-distro.sh --org <PUBLISHER_ORG> --slug <DISTRO_SLUG>
```

- It forks the `<os>-template` matching `DISTRO_OS`, plus `installer-template`,
  `ports-templates` and `ci-templates`, into the `--org` account, renamed to
  `<slug>`, `<slug>-installer`, `<slug>-ports` and `<slug>-ci`.
- It drops `product.conf` in so the Jenkinsfiles and build scripts can read it.
- Upstream source trees stay untouched (Ground rules); product-specific work
  from here on happens only in the fork — `overlay/base`,
  `overlay/profiles/desktop`, `overlay/profiles/appliance`, and, when
  `PACKAGE_SET=custom`, the package list in the `<slug>` repo.
- Leave the disabled sample GitHub Actions file exactly as it is.

## 4. Phase 3 — Jenkins build

The Jenkinsfile ships from `ci-templates` and lands in the `<slug>-ci` repo at
fork time. (CI_ENABLED=no means no Jenkins: run the build template by hand and
skip auto-publishing.) On a release build it:

1. creates a throwaway bhyve build VM on the Jenkins agent (a FreeBSD host with
   vm-bhyve), named after the build number only;
2. builds base exactly as `per_os_build` describes for `DISTRO_OS`, then applies
   `overlay/base`, then each profile layer chosen by `PROFILE`, then the chosen
   package set;
3. produces the release media and files: an ISO, a raw/qcow2 image, and a
   SHA256 file next to them;
4. destroys the build VM when the job ends, success or failure.

Illustrative vm-bhyve commands for that VM (sizes and templates come from the
ci-templates; illumos wants the large bootstrap VM, OpenBSD must build natively
on OpenBSD):

```sh
name="build-${BUILD_NUMBER}"                    # disposable: the name is the build number only
vm create -t "${DISTRO_SLUG}-build" -c 8 -m 16G -s 120G "${name}"
vm start "${name}"                              # the build runs inside, per per_os_build
# ... artifacts are copied back to the Jenkins workspace ...
vm destroy -f "${name}"                         # always, success or failure
```

## 5. Phase 4 — bhyve end-to-end test

A second throwaway VM proves the release actually installs. Per release build:

1. Generate a test SSH key for this run only:

   ```sh
   ssh-keygen -t ed25519 -N '' -f "e2e-key-${BUILD_NUMBER}"
   ```

2. Create the E2E VM, boot the Phase 3 installer ISO as its install media, and
   let the run install unattended; afterwards it reboots into the installed
   system:

   ```sh
   name="e2e-${BUILD_NUMBER}"
   vm create -t "${DISTRO_SLUG}-e2e" -c 2 -m 4G -s 32G "${name}"
   vm install "${name}" "$ISO"      # $ISO = the installer ISO from the Phase 3 artifacts
   ```

3. Judge each path chosen by `PROFILE`:
   - **desktop** (or `both`): the VM's bhyve fbuf framebuffer serves VNC on a
     host-local address; take a screenshot with a VNC client and pass only when
     the X11 login greeter (LightDM, or xdm/slim) is visible.
   - **appliance** (or `both`): on the serial console (`vm console`) a login
     prompt must appear, and an SSH login with the per-run test key must work:

     ```sh
     vm console "${name}"
     # Illustrative: E2E_ADDR is the VM's address on the private bhyve bridge
     # (from the ci-templates VM lifecycle); the installer answers create the
     # e2e user and install the per-run public key.
     ssh -i "e2e-key-${BUILD_NUMBER}" -o StrictHostKeyChecking=accept-new \
       -o UserKnownHostsFile="known_hosts-${BUILD_NUMBER}" -o BatchMode=yes \
       "e2e@${E2E_ADDR}" true
     ```
4. Destroy the E2E VM and discard the per-run key:

   ```sh
   vm destroy -f "${name}"
   rm -f "e2e-key-${BUILD_NUMBER}" "e2e-key-${BUILD_NUMBER}.pub" "known_hosts-${BUILD_NUMBER}"
   ```

The key is generated fresh every run, lives in the workspace, and is never
committed or reused. (If the install stops at a prompt instead of running
unattended, the ISO predates the installer answers — rebuild before debugging
bhyve.)

## 6. Phase 5 — Publish to PUBLISH_TARGET

Default target: `wtfbsd.ai` (`PUBLISH_TARGET`); default method: `api`
(`PUBLISH_METHOD`). The token flow, once, user-driven:

1. The user creates an API token in their own account settings on
   `PUBLISH_TARGET` (for wtfbsd.ai: account settings, API tokens).
2. The user adds it in Jenkins as a **Secret text** credential with id
   `wtfbsd-ai-token`. The id is a fixed convention the ci-templates
   Jenkinsfile expects, whatever `PUBLISH_TARGET` is.
3. Never echo the token, never log it, and never commit it to git, to
   `answers.yaml` or to `product.conf`. It exists only in Jenkins credentials
   and reaches a step only through the credential binding.

Use the same Jenkinsfile snippet regardless of build flavor:

```groovy
// Release metadata plus SHA256 to the publish API. RELEASE_JSON and
// SHA256_FILE are this build's release metadata and Phase 3 SHA256 file.
withCredentials([string(credentialsId: 'wtfbsd-ai-token', variable: 'WTFBSD_TOKEN')]) {
  sh '''
    set -eu
    curl -fsS \
      -H "Authorization: Bearer $WTFBSD_TOKEN" \
      -F "metadata=@$RELEASE_JSON" \
      -F "sha256=@$SHA256_FILE" \
      "https://${PUBLISH_TARGET}/api/releases"
  '''
}
```

- `PUBLISH_TARGET` comes from `product.conf` (default `wtfbsd.ai`).
  `https://wtfbsd.ai/api/releases` is the placeholder endpoint; it may change —
  check the docs on the publish target's own site before wiring it up.
- The single-quoted `sh` block is deliberate: Groovy must never interpolate the
  secret; the shell reads `$WTFBSD_TOKEN` at run time. Never `echo`, `curl -v`
  or otherwise print it; on failure, redact before surfacing any output.
- With `PUBLISH_METHOD=mcp`, publish through the target's MCP publish tool
  instead; the token still originates in the user's account settings and still
  travels only via the `wtfbsd-ai-token` credential.

## 7. Done checklist

- [ ] Phase 1: all ten steps asked in order, one message each; every id
      (`DISTRO_OS` … `PUBLISHER_ORG`) resolved against `questions.yaml` (answered,
      defaulted, or conditionally skipped); `answers.yaml` written;
      `scripts/apply-answers.sh answers.yaml` succeeded; `product.conf` produced.
- [ ] Honesty held: `per_os`/`per_os_honesty` facts mirrored; impossible
      combinations (root-on-ZFS on NetBSD, any ZFS on OpenBSD or DragonFly)
      never offered, accepted or recorded.
- [ ] Phase 2: `fork-distro.sh --org <PUBLISHER_ORG> --slug <DISTRO_SLUG>` ran;
      `<slug>`, `<slug>-installer`, `<slug>-ports`, `<slug>-ci` exist under the
      org; `product.conf` dropped in; upstream trees untouched.
- [ ] Phase 3: Jenkins (or documented hand build) built base + overlay + packages
      for each chosen profile, inside a bhyve VM that was created and destroyed;
      ISO, raw/qcow2 image and SHA256 file produced.
- [ ] Phase 4: a second throwaway VM installed unattended from the ISO and
      rebooted; per chosen profile: greeter visible in the fbuf VNC screenshot
      (desktop) and/or serial login prompt plus SSH login with the per-run key
      (appliance); VM and key disposed of.
- [ ] Phase 5: token created by the user in their account settings and stored
      only as the Jenkins Secret text credential `wtfbsd-ai-token`; release
      metadata plus SHA256 uploaded with the `Authorization: Bearer` header;
      endpoint checked against the target's own docs.
- [ ] Nothing sensitive anywhere: no token in git, logs, `answers.yaml` or
      `product.conf`; no real IP addresses; placeholder hostnames (`example.org`);
      no unguarded `rm -rf` on variables; the disabled GitHub Actions sample
      still disabled.

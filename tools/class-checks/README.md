# class-checks

When a bug is found, it is rarely alone. OpenBSD's practice is to treat each
bug as a *class*: find every other place with the same mistake, fix them
all, and add a check that keeps the class out. `tools/class-checks/` is
that check for the wtfbsd repositories. Every class here came from a real
finding in these repositories.

## Run it

```sh
sh tools/class-checks/run.sh [REPO_DIR...]      # default: .
```

Each hit is one line:

```
path:line: class: what to do instead
```

Paths are relative to the repository. When you pass a directory other
than `.`, they start with that directory. A summary for each repository
goes to stderr. Exit status: `0` no hits, `1` hits, `2` could not look.
"Could not look" covers a missing directory, a malformed allow-list, a file
it cannot read, a missing tool, and any scan that failed (find, grep, awk,
xargs, sort or shellcheck erroring out). A failed scan is never reported as
"no hits". `2` wins over `1`.

Requirements: a POSIX `sh`, `awk`, `find`, `grep`, `xargs -0` and `sort`.
The tests pass with FreeBSD's one-true-awk, mawk, gawk and busybox awk.
The two shellcheck classes (`unquoted-expansion`, `shellcheck`) need
`shellcheck`. Without it run.sh exits `2`. On a host that genuinely cannot
have it, `CLASS_CHECKS_ALLOW_MISSING=shellcheck` turns that into a skip,
printed on stderr, with exit `0`. Use that only where you have to; CI
should install shellcheck.

## The classes

| class | flags | do instead |
|---|---|---|
| `python-not-isolated` | `python`/`python3` run without `-I` in a shell script or build file (Makefile, Jenkinsfile, YAML); a python shebang without `-I` under `bin/`, `sbin/`, `libexec/`, `rc.d/`, `tools/` or in a `*-install` file | `python3 -I ...`, `#!/usr/local/bin/python3 -I` |
| `privilege-env-passthrough` | doas `keepenv`/`setenv`; sudo `!env_reset`, `SETENV`, `setenv`, `env_keep` of `PATH`/`LD_*`/`PYTHON*`/...; `sudo -E`, `--preserve-env`. Prose files are checked too | pass the values as arguments |
| `awk-v-variable` | `awk -v name="$var"` (awk rewrites backslash escapes in the value) | `name="$var" awk '... ENVIRON["name"] ...'` |
| `eval-nonliteral` | `eval` whose argument expands something outside single quotes | `case`, `set --`, `printf`, `read` |
| `root-write-user-dir` | in root-run files (`rc.d/`, `sbin/`, `libexec/`, `*-install`): `>`/`>>`, `cp`/`mv`/`install`/`ln` (destination) or `tee` into `$HOME`, `~`, any `*home*` variable, `/home`, `/tmp`, `/var/tmp`, `$TMPDIR`, also behind a root prefix (`"$R$_home"`) | write as the user, or into a fresh `mktemp -d` directory, and refuse symlinks |
| `tmp-predictable` | `mktemp` with no template, with fewer than six `X`s, or with `-u`; python `tempfile.mktemp()`; a fixed name in `/tmp`, `/var/tmp` or `$TMPDIR` (also `name.$$` and `${VAR:-/tmp/name}` defaults) | `mktemp "${TMPDIR:-/tmp}/NAME.XXXXXXXX"` |
| `pipe-to-shell` | `curl`/`fetch`/`wget`/`ftp ... \| sh` (or bash, python, perl, also under doas/sudo), `sh -c "$(curl ...)"`, `bash <(curl ...)`. Prose files are checked too | download, verify the checksum or signature, then run it |
| `unquoted-expansion` | shellcheck SC2086, SC2068, SC2048 | `"$var"`, `"$@"`; build lists with `set --` |
| `shellcheck` | every other shellcheck finding at warning level or above. Files without a shebang are read as POSIX sh. `rc.subr` variables that only look unused (`rcvar`, `start_cmd`, `*_flags`, OpenBSD's `daemon`, `rc_bg`, ...) are skipped | what shellcheck says |

These checks are heuristics. They read text, not ownership or data flow. A
hit is a place to look, and the allow-list records what you concluded.

## The allow-list

`.class-checks-allow` at the top of the repository, one entry per line:

```
# CLASS PATH:LINE REASON
root-write-user-dir overlay/live/usr/local/libexec/@SLUG@/live-user-session:21 runs as the live user, not root
awk-v-variable tests/fixtures/fake-bsddialog:225 the value is $((calls + 1)), a number, never a backslash
* tools/class-checks/tests/fixtures/*:* deliberate positive and negative fixtures for the class checks
```

- `CLASS` is a class name or `*`.
- `PATH` is relative to the repository. It may use `*` and `?` (`*` also
  matches `/`).
- `LINE` is a line number, or `*` for the whole file. Prefer a line
  number: when the code moves, the hit comes back and someone looks again.
- `REASON` is required and must be at least two words. Say *why* the hit is
  safe, not just that it is.

An entry with a missing or one-word reason, an unknown class, or no `:LINE`
makes run.sh exit 2 without checking the repository. An entry that hides no
hit is reported as stale. Remove stale entries.

## Add it to a repository's tests and CI

The checks live in the agents repository. Every other repository runs them
from a checkout of agents, so there is one copy of the rules.

In the repository's test script (for example `tests/run-tests.sh`):

```sh
# class checks: the bug classes of the wtfbsd repositories (agents/tools/class-checks)
agents=${WTFBSD_AGENTS:-../agents}
if [ -f "$agents/tools/class-checks/run.sh" ]; then
    if sh "$agents/tools/class-checks/run.sh" "$repo"; then
        ok "class checks"
    else
        no "class checks (see the hits above; fix them, or allow one with a reason in .class-checks-allow)"
    fi
else
    no "class checks: no agents checkout at $agents (set WTFBSD_AGENTS)"
fi
```

A missing agents checkout fails the test. It must not pass silently.

In CI (Jenkinsfile), check out agents next to the repository and run the
checks as their own stage, so a hit shows up as its own red stage:

```groovy
stage('class checks') {
    steps {
        dir('agents') { git url: 'https://github.com/wtfbsd/agents.git', branch: 'main' }
        sh 'sh agents/tools/class-checks/run.sh .'
    }
}
```

For GitHub Actions:

```yaml
- uses: actions/checkout@v4
  with: { repository: wtfbsd/agents, path: .agents }
- run: sudo apt-get install -y shellcheck
- run: sh .agents/tools/class-checks/run.sh .
```

## Add a class

When a new bug class turns up:

1. Write `tests/fixtures/CLASS/pos/` (files that must be flagged),
   `tests/fixtures/CLASS/pos.expect` (their `path:line`, one per line) and
   `tests/fixtures/CLASS/neg/` (look-alikes that must not be flagged).
2. Add `CLASS` to the `classes` list in `tests/run-tests.sh` and run the
   tests. They must fail, because the check does not exist yet.
3. Write `checks/CLASS.sh`. It sources `../lib.sh`, calls `cc_setup CLASS
   "$@"`, runs an awk program over one of the file indexes (`text`, `code`
   or `shell`) with `cc_awk`, then calls `cc_finish`. The helpers are in
   `lib.awk`. run.sh picks up every `checks/*.sh` on its own.
4. Run the tests until they pass, then run the check on every wtfbsd
   repository. Sort the hits into real ones and false positives, fix the
   false positives in the check (negative fixture first), and file the
   real ones.

```sh
sh tools/class-checks/tests/run-tests.sh
CLASS_CHECKS_DIR=/path/to/other/copy sh tools/class-checks/tests/run-tests.sh   # test another copy
```

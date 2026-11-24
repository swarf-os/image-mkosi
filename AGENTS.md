# AGENTS.md

Image-based swarf: an mkosi recipe on the ParticleOS model (A/B `/usr` with
systemd-sysupdate, signed UKI and `/usr`, LUKS passphrase without TPM), Arch
Linux packages, KDE Plasma. `SPEC.md` is the source of truth.

**At the start of every session, read `docs/STATUS.md`, then only the sections
of `SPEC.md` your step needs (its step in section 12, plus what the step points
to).**

## Agent rules
- One step per session (SPEC section 12). Do exactly its scope; anything else
  goes into `docs/STATUS.md`, not into code.
- Never decide an open question (O-n in SPEC section 13): ask the owner, in
  plain text, blocking questions first, one at a time.
- Packages only from Arch's official repositories (or the owner's own
  repository). Never AUR or any other third-party repository.
- Never guess a package, unit, option or key name: check the documentation of
  the version in use, or the image (`pacman -Si`, `pacman -Ql` at the Archive
  date in `mkosi.conf`). Cite the source and date in the ADR or the commit.
  Separate what a source says from your own inference.
- Never run `sudo`/`run0` on the owner's host. Builds and tests run in CI or in
  a VM.
- Scripts write their log to a file under `logs/` and print only `OK` or the
  useful error lines.
- Check the visible result before saying "works" or "fixed". A test fixture
  (credentials, overrides, extra disks) must never set what the test verifies;
  list the fixtures next to the result in `docs/STATUS.md`.
- One short ADR per decision in `docs/adr/NNNN-title.md`, written when decided.
- Subagent reports are leads, not facts: check any absence or any claim a
  decision rests on in the primary source before using it.
- Third-party repositories (ParticleOS, Zirconium, KDE Linux, …) are read in a
  separate directory, never executed. Zirconium is AGPL: ideas only, no code.
- Code, comments, commit messages, docs and pull requests in English.
- Before finishing: update `docs/STATUS.md` (done, left, open questions),
  commit on a branch, open a draft pull request.
- Token economy: do not re-read files you just wrote; no web browsing unless
  the step needs a fact the image or the pinned sources cannot give.

## CI facts (read before touching `.github/workflows/`)
- Runner `ubuntu-24.04`; the pinned mkosi action opens `/dev/kvm` to the
  runner user and allows unprivileged user namespaces: no sudo in our build.
- The Arch Linux Archive is often slow or cuts downloads. `scripts/build.sh`
  keeps packages and metadata in the GitHub cache (keyed by the Archive date)
  and retries; a red run is not an image failure until the build log says so.
- Signing: `scripts/signing-keys.sh` writes `mkosi.key`/`mkosi.crt` from the
  secrets `SWARF_SIGNING_KEY`/`SWARF_SIGNING_CERT`; `main` refuses to build
  without them; pull requests without them use a key made for the run.
- Claude's cloud sessions could not create a release or a secret, nor read
  run artifacts (2026-11-23): ask the owner, and give the exact command or page.

# Status

State of `swarf-os/image-mkosi`, kept by each step session (SPEC rule 9).

## Now (2026-11-24)

- Step 1 (Build bench and first boot): **done**. PR #1 merged on 2026-11-23
  (`b87927c`). First green run: 45239430422.
- Step 2 (Signatures and Secure Boot): **done**. PR #2 merged on 2026-11-24
  (`3cf5593`); last green pull request run: 45288942640.
- **`main` is red** (run 45345109518): "ERROR: secrets SWARF_SIGNING_KEY and
  SWARF_SIGNING_CERT are not set; main is only built with them". On purpose
  (D-10). The owner creates them, on the host in a temporary directory, with
  the command `mkosi genkey` runs (mkosi v27.1):
  `OPENSSL_CONF=/dev/null openssl req -new -x509 -newkey rsa:2048 -keyout mkosi.key -out mkosi.crt -days 730 -subj "/CN=swarf test key (throw-away)/" -nodes`,
  then `gh secret set SWARF_SIGNING_KEY -R swarf-os/image-mkosi < mkosi.key`
  (same for `SWARF_SIGNING_CERT` with `mkosi.crt`), deletes the directory and
  reruns the workflow.
- Seen in that run: the package cache restored was 307 bytes (nearly empty),
  and an empty cache was saved under the Archive-date key; the next build may
  download everything again. To look at in step 3.
- Next: step 3 (Encryption), once `main` is green.
- Decided on 2026-11-24: one password at first boot for LUKS and the account
  (D-15); this spec lives in this repository (D-14).

## Step 1: what exists

- `mkosi.conf`: Arch, `Snapshot=2026/11/09`, tools tree from Arch, disk image
  with split UKI and partitions, JSON manifest, systemd-boot, UKI, image
  policy `usr=signed` (since step 2), 27 root packages named.
- `/usr` is EROFS (zstd, minimized) with its verity partition; two-slot
  definitions for the installed system in `mkosi.extra/usr/lib/repart.d/`;
  btrfs root (`/var` subvolume) created at first boot, unencrypted until step 3.
- Identity: `mkosi.postinst.chroot` writes `os-release` (`ID=swarf`,
  `ID_LIKE=arch`); the initrd gets its own `os-release`
  (`mkosi.initrd.conf/mkosi.postinst`); `/etc/arch-release` removed;
  `swarf-default-hostname.service` applies `DEFAULT_HOSTNAME` when
  `/etc/hostname` is missing (the Arch initrd set `archlinux`).
- Factory `/etc`: `mkosi.finalize` copies the build-time `/etc` to
  `/usr/share/factory/etc`; `tmpfiles.d/etc.conf` links back what the system
  needs (PAM stays in `/etc/pam.d`, linked, not `/usr/lib/pam.d`).
- pacman's local database moved to `/usr/lib/pacman/local`.
- CI (`.github/workflows/build.yml`): `ubuntu-24.04`, mkosi v27.1 pinned
  (`systemd/mkosi@ecf7f57`), package and metadata cache keyed by the Archive
  date, build (`scripts/build.sh`), boot test in QEMU/KVM
  (`scripts/boot-test.sh`), logs and manifest uploaded.
- Test fixtures (`tests/credentials/`, passed with `--credential=`, never in
  the image): answers for systemd-firstboot (locale, timezone, root account
  locked with `!`) and a check unit that prints the checks, then powers off.

## Step 2: what exists

- Signed systemd-boot, UKI and `/usr` verity root hash (one key, as
  ParticleOS); `usr-verity-sig` partition; `Verity=signed`; OVMF with Secure
  Boot in setup mode, keys enrolled from `/loader/keys/auto` at first boot.
- `scripts/secureboot-test.sh` + `scripts/tamper.py`: a changed UKI, a UKI
  signed by another key, a changed `/usr` and a whole `/usr` signed by another
  key must not boot; an unchanged copy made the same way must.
- Finding: mkosi puts `usrhash=` in the signed UKI command line, so the UKI
  pins the exact `/usr` (see README).
- `scripts/signing-keys.sh`: keys from the secrets; `main` refuses to build
  without them; a pull request without them is signed with a key made for the
  run.
- `scripts/build.sh`: four tries, waiting 60, 120, then 240 s after an Archive
  download failure; CI cache keyed by the Archive date.

## Left (from SPEC section 12)

- Minor CI defect, to fix in the next pull request: the step "Show the end
  of the logs on failure" in `build.yml` fails when `logs/` is empty (the
  glob has no `nullglob`). It hides nothing, but adds a second red step.
- Steps 3 to 6 (base), then the base handover tag for pxOS (SPEC section 12).
- Steps 7 to 13 (Plasma, swarf's settings, hardware and audio, daily CI,
  hosting and real updates, Packard Bell, merge into `swarf-os/image`).

## Open questions waiting for the owner

- O-9 (Packard Bell setup mode) should be checked early: it decides whether
  that machine can run swarf with our keys at all.
- O-13: a copy of one Archive date's packages, and `ParallelDownloads=3`
  (proposed in step 1, no answer yet).
- The others wait for their step (SPEC section 13).

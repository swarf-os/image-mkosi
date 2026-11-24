# SPEC: swarf on mkosi (`swarf-os/image-mkosi`)

- Status: 1.0, 2026-11-24 (first version, from the draft of 2026-11-23). Derived from the pxOS SPEC 0.9 (Part II and steps 1 to 6 of Part III) and from the `swarf-os/image` SPEC (draft 15, 2026-11-18), plus the decisions taken while building steps 1 and 2 in this repository. Lives as `SPEC.md` at the root of `swarf-os/image-mkosi`; this work has its own Claude project since 2026-11-24 (D-14).
- Owner: François (GitHub `fbmguerin`). Authors: the owner and Claude.
- Audience: the owner, then Claude Code sessions (one step of section 12 per session).
- Language: the owner talks French in chat. Code, comments, commit messages and docs are in English.
- This spec stands alone. Where an item came from another spec, appendix A says where; nothing here needs the other spec to be read.

## 0. How to read this spec

Read only the sections your task needs. A step session reads its step in section 12, plus the sections the step points to.

### Status tags

| Tag | Meaning |
|-----|---------|
| [D] | Decided by the owner. Do not change without asking. |
| [P] | Proposed by Claude, not confirmed yet. Implement only if a step says so, otherwise ask. |
| [O] | Open. Needs an owner decision. The step that resolves it is named. |
| [V] | Verified in documentation or source code (sources in section 15). |
| [U] | Unverified assumption. Check before relying on it. |

### Rules for Claude Code sessions

1. One step per session. Do exactly the step's scope. Anything else you notice goes into `docs/STATUS.md`, not into code.
2. Never decide an [O] item. Stop and ask the owner. Ask blocking questions first, one at a time if possible, in plain text.
3. Dependencies: only packages from Arch Linux's official repositories, or from the owner's own repository. Never third-party repositories (no AUR, no Copr, no PPA, no OBS). Anything new needs the owner's approval.
4. Never guess a package, unit, file or key name: check the documentation of the version in use, or the image itself (`pacman -Si`, `pacman -Ql` at the Archive date of `mkosi.conf`), and cite the source. Separate what a source says from your own inference. Reports from subagents are leads, not facts.
5. Check the visible result before saying something "works". A test fixture must never set what the test verifies.
6. Never use sudo or run0 on the owner's host. Builds and tests run in CI or in a VM.
7. Scripts write their logs to a file and print only `OK` or the useful error lines.
8. One short ADR per decision in `docs/adr/NNNN-title.md`, written when decided (the `swarf-os/image` habit).
9. Before finishing: update `docs/STATUS.md` (done, left, open questions), commit on a branch, open a draft pull request.
10. Token economy (the owner uses a subscription): read only the sections you need, do not re-read files you just wrote, do not browse the web unless the step needs a fact you cannot find in the image or the pinned sources.
11. Cite steps by number and name, for example "step 3 (Encryption)". Open questions are O-n, decisions D-n, both of this spec.

### Related projects

- **`swarf-os/image`**: the current swarf (Fedora bootc + KDE Plasma, `ghcr.io/swarf-os/image:stable`, ISO with the Anaconda WebUI). The owner's daily system. Untouched by this work. Its SPEC, `AGENTS.md`, `PROGRESS.md` and 46 ADRs (`docs/adr/`) are the source of swarf's package choices and settings (section 9.2).
- **pxOS / pxDE** (organization `pxhq`, its own Claude project and spec): an OS with its own desktop (Quickshell on niri). pxOS uses the same base model, and **takes over the console base built here in steps 1 to 6** (section 12, "Base handover"). This repository does not depend on pxOS; pxOS depends on this repository's base. Lessons flow both ways.

## 1. What this is (plain words)

- **The next swarf.** The same goal as swarf (a minimal KDE Plasma system the owner controls, built and tested by a CI), rebuilt on an image-based model instead of Fedora bootc. If it proves itself, it is merged into `swarf-os/image` and replaces the bootc recipe there [D, D-6].
- **Image-based OS.** The CI builds the whole system as one image; machines receive that exact image. No package manager is used on the installed machine.
- **Signed `/usr`.** All programs live in `/usr`. At build time the CI computes a fingerprint of the whole `/usr` partition (dm-verity) and signs it with the owner's key. At boot, Secure Boot checks the kernel (UKI); the kernel then checks every block of `/usr` it reads against the signed fingerprint. Any change (malware, a tampered disk) makes the read fail. Without Secure Boot, changes to `/usr` are still refused, but someone holding the machine can replace the kernel itself.
- **A/B updates.** Two `/usr` slots: the running version and a spare. An update writes the new version into the spare slot and adds its kernel; the boot loader gives it 3 tries; if it never boots, the previous version is used again. This is the automatic rollback that bootc did not give swarf (`swarf-os/image` ADR 0034).
- **The owner is the distributor.** The CI builds, tests, signs and publishes images; machines only accept images signed by the owner's keys.

## 2. Goals and non-goals

- [D] Minimal system: the owner names every root package; the CI keeps the full dependency closure (mkosi JSON manifest) (D-2).
- [D] Own identity: `os-release`, `issue`, boot entries and the initrd name only swarf; no Arch branding left (criterion 6). Unlike `swarf-os/image`, no upstream logo is kept: there is no Fedora logo question any more.
- [D] Built and tested by a CI before it reaches any machine; automatic rollback (A/B, boot counting).
- [D] Channels `testing` then `stable`: nothing reaches `stable` without passing tests (D-3).
- [D] Little maintenance on installed machines; no package layering on them (D-11).
- [D] KDE Plasma, Wayland only (D-7).
- [P] Carried over from `swarf-os/image` (its SPEC, "Goal"), to confirm in step 8: not wanted by default: Bluetooth, printing, modems, remote access (ssh server, RDP, VNC), X11 session, telemetry, apps imposed by the distribution. The audio server is O-8.
- Non-goals: support, a roadmap, public promotion. The repository is public to simplify deployment and let others reuse the code (as `swarf-os/image`).

## 3. Model

- [D] **mkosi** (build) + **systemd-repart** (partitions) + **systemd-sysupdate** (A/B updates) + **systemd-sysinstall** (installer), following ParticleOS. **Our own recipe in our own repository**: ParticleOS is a model, not a dependency; we do not track its main branch (D-1).
- [D] **Package provider: Arch** (D-2). Reasons: every needed package is official and current, and this model needs a recent systemd, which Arch ships within weeks while Fedora keeps one systemd major version per release.
- [V] systemd 262 or newer is required: `systemd-sysinstall` appeared in 261; its Varlink API, the `systemd-cryptenroll` first-boot wizard and the `io.systemd.CryptEnroll` Varlink API in 262. Arch had `systemd` 262.2-1 on 2026-11-17.
- Why sysupdate rather than bootc: automatic rollback, `/usr` sealed by default, installer maintained by systemd, no rpm-ostree overlap, no Fedora branding. Cost: no delta updates (section 8).
- Rejected: bootc for this repository (that is `swarf-os/image`); Fedora's signed shim on Arch images; Anaconda, Calamares; the OBS systemd repository (third party).
- [P] Fallback only if the sysupdate model fails in steps 1 to 6: mkosi + Fedora + bootc. The recipe may stay two-distribution capable (`mkosi.conf.d/arch/`, `mkosi.conf.d/fedora/`, as ParticleOS) [P, not done yet: the recipe is Arch only today].
- [P] Variants are stacked mkosi profiles of one recipe (section 5).

### 3.1 ParticleOS: what we take and what we change

Read on 2026-11-17 in the repository (commit b605add, 2026-11-05).

- [V] Status: active, maintained by systemd developers. Its README says it is "still in development" with "no backwards compatibility guarantees at all", and asks for mkosi's main branch. We pin a released mkosi instead (D-9).
- [V] What we take:
  - Partition layout (`mkosi.extra/usr/lib/repart.d/`): ESP 1 GB; two `/usr` slots, each with its verity and verity-signature partitions (`/usr` is EROFS, zstd, minimized); root partition (btrfs, `/var` subvolume) created at first boot. Done in steps 1 and 2.
  - Kernel policy: `systemd.image_policy` with `usr=signed` (done in step 2) and `root=encrypted` (step 3); `root=dissect mount.usr=dissect`.
  - sysupdate transfers (`mkosi.sysupdate/`): versioned `/usr`, verity and UKI; `InstancesMax=2`; boot counting `TriesLeft=3` (step 5).
  - UKI profiles (`mkosi.uki-profiles/`): Live System, Installer (`system-install.target`), factory reset, emergency, debug (step 6).
  - `/etc` handling: the whole build-time `/etc` is copied to `/usr/share/factory/etc` and linked back with tmpfiles (`mkosi.finalize`, `tmpfiles.d/etc.conf`, done in step 1 with a list redone for Arch).
  - Arch specifics: pacman's local database moved into the image (`/usr/lib/pacman/local`, done in step 1).
  - Desktop profile: Plymouth in the initrd (`InitrdProfiles=plymouth`, `plymouth.use-simpledrm splash`) (step 7).
- What we change:
  - [D] No TPM: root uses `Encrypt=key-file` instead of `tpm2`; passphrase and recovery key enrolled at first boot (section 7).
  - [P] No systemd-homed (ParticleOS creates users with `homectl firstboot`): a classic user, `/home` inside the encrypted root, created at first boot by our own unit (D-15).
  - [P] No swap partition (ParticleOS's is TPM-encrypted); zram only (`zram-generator`). Hibernation out of scope.
  - [D] No OBS systemd repository: third party (D-2), and Arch's systemd 262 has what we need.
  - [D] Our own identity: our own `os-release`, `issue`, initrd `os-release` and boot entry titles, then an audit of the image for leftovers (criterion 6; done in step 1).
  - [P] Updates come from our server (`url-file`), not from local builds (section 8).
  - [D] ParticleOS's VM conveniences (root password `particleos`, autologin credentials for `mkosi vm`, serial debug shells) never reach release images (checked in step 1).
- [V] Zirconium (read 2026-11-23): its `sysupdate` profile is a near copy of ParticleOS's, marked "THIS PROFILE SHOULD NOT BE USED BY DEFAULT", with Secure Boot disabled, a throw-away key made in CI, TPM encryption and serial debug shells. Its CI pushes `/usr`, verity, signature and UKI to GHCR with oras, but its transfer files read a local path, so machines do not fetch updates from the registry. Ideas taken: stacked profiles, the CI structure. AGPL-3.0: ideas only, no code (D-6).

### 3.2 KDE Linux: the closest existing system

- [V] KDE Linux (KDE's own image, docs page "History & Architecture", modified 2026-11-04): "The base system comes from Arch Linux packages"; the image is "an ISO-compatible `.raw` disk image built using `mkosi`"; `/` is a read-write btrfs volume with `/usr` mounted on top as an EROFS image; `/home` is a btrfs subvolume; systemd-boot; an update downloads a new OS image and its UKI, and "3-4 of these OS images and their UKIs are cached on disk"; apps come from Flathub through Discover; no package manager; `/etc` is updated from `/usr/share/factory/etc` by a helper.
- [V] LWN, "KDE Linux" (2025-09-10, alpha): "The project uses systemd-sysupdate under the hood"; up to five OS images kept for rollback; updates through Discover or `updatectl update`; "Support for UEFI Secure Boot is currently missing" (may be outdated). Its developer page (2026-11): built with `mkosi` in a Docker container; recipe at https://invent.kde.org/kde-linux/kde-linux.
- [V] Installation page (2026-11-04, Testing edition): download an `.iso` (checked with `SHA256SUMS`), write it with KDE's ISO Image Writer (Ventoy not supported); the stick boots a "Live Session" with a welcome wizard; an "Install KDE Linux" icon opens the installer; the whole disk is erased ("the most reliable option"); UEFI only, 50 GB; "Ensure that Secure Boot is disabled" until KDE Linux supports it. Not stated: the installer's tool, what it asks, encryption, first-boot account, login.
- [U] Neither page mentions ParticleOS: KDE Linux uses the same building blocks (mkosi, sysupdate, EROFS `/usr`, factory `/etc`), but nothing read says it derives from ParticleOS. Not stated either: encryption, installer, login. The recipe was not read (`invent.kde.org` was blocked by this session's network policy on 2026-11-24).
- [V] A Discover backend for systemd-sysupdate exists (Alpine package `discover-backend-sysupdate`); whether Arch's `discover` package ships it is [U] (O-10).
- [P] Read KDE Linux's recipe before step 7 (Plasma packages, Discover, Plymouth, session start), for ideas only; check its licence before copying anything. Why we do not simply use KDE Linux: our own keys, LUKS passphrase without TPM, every root package named by the owner, swarf's settings, Arch Archive freeze.

## 4. Packages and build

- [D] Only Arch's official repositories, plus the owner's own repository if swarf ever ships its own packages. Never someone else's repository (D-2).
- [D] Packages frozen on the Arch Linux Archive at one date for all repositories (`Snapshot=` in `mkosi.conf`, 2026/11/09 today), kept about 14 days behind today; the date moves forward only after the image passed its tests (D-3).
- [D] mkosi pinned in CI: v27.1 through the action `systemd/mkosi@ecf7f5702bb2052b7a69cab3fe7d37bc3b9ad77b`, upgraded deliberately (D-9).
- [V] Root packages are named in `mkosi.conf` (`Packages=`); the build writes a JSON manifest of the full closure (`ManifestFormat=json`), uploaded by the CI.
- [V] Lessons of step 1 (CI runs of 2026-11-23): the Archive (`archive.archlinux.org`, one host) is often slow or cuts downloads; the `*.archive.pkgbuild.com` names tried as mirrors did not answer from GitHub. Mitigations in place: `mkosi.pkgcache` and `mkosi.cache` (repository metadata) kept in the GitHub cache, keyed by the Archive date; `--cache-only=metadata` once metadata exists; four tries spaced 60, 120 then 240 s (step 2 branch). `mkosi.tools` cannot be cached (files unreadable to the runner user).
- [O] O-13: if the Archive stays this unstable, keep our own copy of the packages of one Archive date (GitHub release or R2) [P, proposed in step 1, no answer yet]. A `ParallelDownloads=3` setting was also proposed and not answered.
- [P] The `swarf-os/image` package lists (`whitelist.txt`, 228 entries; `blacklist.txt`) are translated to Arch names in steps 7 and 8, every name checked with `pacman -Si` at the Archive date. [U] Inference to check: pacman does not install optional dependencies, so most of the Fedora blacklist (weak dependencies) has no Arch equivalent; what remains becomes a "must not be in the manifest" check in CI.

## 5. Profiles, variants and optional features

- [P] Profiles (stacked, `--profile=`):
  - `base`: console system (steps 1 to 6). Kept free of KDE and of anything swarf-specific except the identity, so pxOS can take it over (section 12, "Base handover"). [P] Keep the identity in one place (one `os-release` template fed by `ImageId=` and the version) to make that easy.
  - `plasma`: KDE Plasma, Plymouth, Flatpak and swarf's settings (steps 7 and 8).
  - `dev`: development VM (mutable, not encrypted, ssh server), never published.
  - The Installer UKI profile (step 6).
- [D] No package layering on installed machines (D-11). Instead: **image variants** built from the same recipe and each tested by the CI; **system extensions** (`systemd-sysext`), small signed images overlaid on `/usr`, built and tested by the CI; **Flatpak** for applications; **containers** (distrobox/toolbox) for command-line and development tools.
- [V] Extension rules (systemd docs): the extension's `extension-release` `ID=` must match the host (unless `_any`), then `SYSEXT_LEVEL=` if the host defines it, else `VERSION_ID=`. sysupdate optional features (`sysupdate.d/*.feature`, `Features=` in transfer files) are downloaded and updated in lock-step with the OS; disabling one removes it. Services in an extension need `EXTENSION_RELOAD_MANAGER=1` or `EXTENSION_RESTART_UNITS=` plus a `.wants/` link.
- [O] O-8: audio. `swarf-os/image` has no audio server and gives one `rpm-ostree install` command for machines that want sound (its ADR 0035). Layering is impossible here. Choices: audio in the `plasma` image; an audio variant; or an audio system extension as an optional feature. Step 9.

## 6. Installation

- [D] Same experience as swarf: write an image to a USB stick, boot it, get a live session and an installer that installs the same system.
- [V] The mkosi disk image itself is written to the stick (`mkosi burn`, or any tool that writes raw images); its boot menu offers "Live System" and "Installer" (UKI profiles). No ISO, no Anaconda: this replaces `swarf-os/image` ADRs 0019, 0020, 0022, 0023 and 0026.
- [V] **systemd-sysinstall** (systemd 261+): terminal installer started by the Installer profile. It asks for the target disk, erase or not, and firmware boot entry registration; partitions with systemd-repart (`/usr/lib/repart.sysinstall.d/`, else `/usr/lib/repart.d/`); installs the kernel (`bootctl link`) and systemd-boot (`bootctl install`); copies locale, keymap and timezone as credentials (encrypted with the TPM if present, otherwise with the null key). It never asks for a user or root password: first boot does (D-15).
- [V] sysinstall defers partitions marked `FactoryReset=yes` and empty slots to first boot: the encrypted root is created by systemd-repart on the target machine at its first boot.
- [V] Varlink API `io.systemd.SysInstall` (262): `Run` and `ListCandidateDevices`. No passphrase field: encryption comes from the repart definitions. A graphical front-end is out of scope; the stock terminal installer is used.
- [O] O-11: the Packard Bell moves from `swarf-os/image` by a reinstall (different disk layout; bootc state is not reused); `/home` saved first. Step 12.

## 7. Boot chain, Secure Boot, encryption and account

### Secure Boot
- [D] Owner's machines: Secure Boot on, with **the owner's own keys only**, enrolled in setup mode; firmware setup protected by a password. Public: **no shim**; users either enroll the keys in setup mode, or disable Secure Boot (D-4).
- [V] mkosi signs systemd-boot, the UKI and the `/usr` verity root hash; keys are made with `mkosi genkey`; they may live on a smartcard or YubiKey through PKCS#11. Keys are never shipped in the image.
- [V] Enrollment: systemd-boot's `secure-boot-enroll` defaults to `if-safe`, which enrolls automatically only inside a VM; on real hardware it shows a boot menu entry for the keys under `/loader/keys/<name>/` (`manual`), or enrolls them with `force`. mkosi puts the enrollment files in `/loader/keys/auto` (`SecureBootAutoEnroll=` defaults to yes).
- [D] During the experiment: one throw-away key made for this repository signs systemd-boot, the UKI and the verity root hash (as ParticleOS); it lives in the repository secrets `SWARF_SIGNING_KEY` and `SWARF_SIGNING_CERT`; it is replaced by the real keys when O-5 is settled. A push to `main` is only built with these secrets; a pull request without access to them is signed with a key made for that run, which tests the signing path but proves nothing about the key (D-10).
- [O] O-9: the Packard Bell. The `swarf-os/image` SPEC says its Secure Boot "cannot be turned off". Our keys need setup mode (clearing the platform key) or a custom-key mode in its firmware menu. If neither exists, this machine cannot run swarf with our keys. To check on the machine, before step 12 and best right away (owner, a few minutes in the firmware menu).
- [O] O-6: also put Microsoft's UEFI CAs in `db` next to our keys (option ROMs, dual boot)? Firmware updates: fwupd's EFI binary must then be signed by our key [U]. Step 12.
- [V] Background: Microsoft's UEFI CA 2011 (signs shims) expired in June 2026; new shims are signed only by the 2023 CA. Own keys avoid this dependency.

### Encryption
- [D] Full-disk LUKS2, unlocked by a real passphrase typed at boot. **No TPM.** No SSD hardware encryption (Opal), no biometrics (D-5).
- [P] Layout: one encrypted root partition (btrfs) holding `/etc`, `/var` and `/home`; no separate home partition (`home=absent` in the image policy); no swap partition.
- [V] Passphrase without TPM, as systemd allows it:
  1. systemd-repart with `Encrypt=key-file` and no key file uses an empty key ("useful for setting up encrypted partitions during early first boot that receive their user-supplied password only in a later setup step").
  2. At first boot: enroll the passphrase and wipe the empty key (`systemd-cryptenroll --unlock-empty --password --wipe-slot=empty`), then enroll a recovery key (`systemd-cryptenroll --recovery-key`).
- [U] systemd's own `systemd-cryptenroll-firstboot.service` (262, in the initrd at first boot) calls `--firstboot --prompt-suppress=password,recovery,fido2 --unlock-headless`; a slot without token counts as a password slot, so the empty key makes this wizard skip. Hence O-1: our own first-boot unit, or a drop-in on systemd's wizard. Step 3.
- [D] Key slots: one user slot; one **recovery key** slot, created at first boot, shown once and stored offline by the user (D-5). [V] Recovery keys carry a `systemd-recovery` LUKS2 token.
- [V] `io.systemd.CryptEnroll` Varlink API (262, polkit `auth_admin`): `Enroll`, `ListSlots`, `MakeRecoveryKey`.

### Account
- [D] First-boot account (D-15): the first-boot unit asks a user name and a password **once**, and uses that password for the LUKS slot and for the classic user account. `swarf-os/image` instead lets Plasma Setup create the account at first boot, with two passwords that can be the same by choice.
- [D] Accepted consequence (inference, not tested): Plasma's own password change (System Settings, `passwd`) changes the account password only, not the LUKS passphrase, so the two drift apart after the first change. A small tool that changes both may come later (D-15).

### Keyboard layout at the passphrase prompt
- [D] The layout chosen at install time must be the same at the LUKS prompt, on the console and in Plasma, otherwise an AZERTY user types two different passwords.
- [V] Lesson from `swarf-os/image` (ADR 0037): the LUKS prompt layout was fixed by the kernel argument `vconsole.keymap=` set at install time; Plymouth takes the layout from this argument or from the initramfs `vconsole.conf` (Plymouth 24.004.60 sources read for that ADR).
- [U] Here the command line is inside the signed UKI, so (O-3): (a) sysinstall copies the keymap as a credential and systemd-vconsole-setup reads `vconsole.keymap` (since 253): check that the credential reaches the initrd before the prompt with Secure Boot on, and that Plymouth follows it; or (b) a command-line addon signed by our key, one per layout. Step 4. Plasma's layout follows the same setting in step 7.

### Boot splash and session
- [P] Plymouth with a stock theme (swarf did no branding work: `swarf-os/image` ADR 0025 used `plymouth-theme-spinner`), in the initrd, with the fonts it needs for the passphrase prompt. Step 7.
- [O] O-7: session start. Autologin into Plasma after the LUKS unlock (the passphrase already proved who is there; one password typed per boot), or the Plasma login screen as in `swarf-os/image` (two prompts per boot). Step 7.

## 8. Updates, distribution and hosting

- [D] The owner is the distributor: the CI builds the image from Arch packages at the Archive date, tests it in a VM (boot, LUKS, Plasma, rollback), signs it and publishes it, first to `testing`, then to `stable`.
- [V] Transport: sysupdate downloads whole compressed partition images and files (`url-file`), listed in a `SHA256SUMS` manifest; no delta mechanism. Each update downloads the full `/usr` (EROFS + zstd) and the UKI. [V] sysupdate has no OCI registry source (no match for "oci" in `src/sysupdate`, systemd main, 2026-11-23): GHCR, where `swarf-os/image` publishes today, cannot be the update source without an extra tool on the machine.
- [V] Manifest signature: `SHA256SUMS` signed with GPG and checked against a keyring shipped in the image (ParticleOS's OBS setup). [U] sysupdate checks it by default (`Verify=`, for `url-file` and `url-tar` only): recheck before step 5.
- [P] Keys, kept outside the image: Secure Boot (UKI), verity (`/usr`), manifest (GPG); plus a pacman repository key only if swarf ships its own packages. One key covers Secure Boot and verity during the experiment (D-10).
- [V] Rollback: two installed versions (`InstancesMax=2`), boot counting (`TriesLeft=3`).
- [P] Channels: two directories on the server (`testing/`, `stable/`); promotion copies the very same signed files from `testing/` to `stable/`, so what was tested is what ships (the idea of `swarf-os/image` ADR 0016, "promotion by retag"). [U] Per-machine channel by overriding transfer files in `/etc/sysupdate.d/` (O-4).
- [P] Security fast lane: all repositories are frozen at one date, so a fast lane is a complete snapshot moved forward and tested sooner, not a single patched package.
- [V] Hosting facts (2026-11-17): Cloudflare R2 costs $0.015 per GB-month, free egress; GitHub Releases is free with no bandwidth limit but each file must be under 2 GiB. `swarf-os/image` already has an R2 bucket `swarf-os-iso` (private, EU jurisdiction) and a Worker `get.swarf-os.workers.dev` (its ADRs 0029 to 0031, 0046). [P] R2 for the update files; sizes to be measured in step 11.
- [O] O-5: hosting, the real keys and where they live, how CI signs with them, promotion rules. Step 11.
- [O] O-10: update front-end. `swarf-os/image` updates through Discover, unattended, staged, never rebooting (its ADRs 0009, 0011). Here: Discover's sysupdate backend if Arch ships it (section 3.2), else `systemd-sysupdate.timer` plus a notification. Step 11 (checked in step 7).
- [D] Flatpak: Flathub only, system-wide; apps installed on demand, nothing preinstalled (`swarf-os/image` ADR 0027) [P: carried over in step 8].

## 9. The Plasma desktop and swarf's settings

### 9.1 Plasma profile (step 7)
- [D] KDE Plasma, Wayland session only (XWayland kept), Qt 6 only.
- [P] Packages: the Plasma core of `swarf-os/image` (`plasma-desktop`, `plasma-workspace`, `kwin`, …), Discover, Dolphin, Filelight, Konsole, System Settings, and the KDE apps kept in its ADR 0002 (Ark, Gwenview, KWrite, KCalc, Spectacle, KolourPaint, Partition Manager, KInfoCenter, Help Center, KMenuEdit), as Arch packages, every name checked [U].
- [P] KDE defaults in `/usr/share/swarf/xdg/`, read through `XDG_CONFIG_DIRS`; `/etc` keeps only named files (swarf's rule since Kyanite).
- [P] Login and session per O-7; account per D-15; layout per O-3.
- [P] Hardware of the Packard Bell: Intel graphics, Intel AX101 Wi-Fi firmware, UPower for the battery (`swarf-os/image` ADR 0028), as Arch packages [U: Arch splits `linux-firmware` into several packages; names to check]. Step 9.

### 9.2 What carries over from `swarf-os/image`

Classification by Claude from the ADR titles and decision lines (read 2026-11-23) [P]: to confirm item by item in steps 7 to 12, one ADR here per item kept.

- **Carry over (same intent, Arch names and paths):** 0003 hardening (sysctl in `/usr/lib/sysctl.d/`), 0004 telemetry off, 0005 KWallet off, 0006 quiet Plasma defaults, 0007 closed firewall zone `swarf` (`dhcpv6-client`, `mdns`), 0012 task manager with icons and text, 0017 drift issue and daily schedule, 0027 apps on demand (Waterfox, VLC from Flathub), 0028 laptop hardware, 0032 docs-only pull requests skip the build, 0040 Packard Bell as the hardware target.
- **Adapt to the new model:** 0002 package lists (Arch names), 0008 image hygiene, 0010 Discover reviews blocked (`/etc/hosts` becomes a factory file), 0015 manifest gate (mkosi manifest), 0016 promotion by retag (copy of signed files), 0018 CI runner (now `ubuntu-24.04` with the KVM udev rule), 0024 quiet console (`quiet` in the UKI command line), 0025 Plymouth and fonts, 0036 README, 0037 LUKS prompt keymap (step 4), 0042 login screen theme (with O-7), 0044 and 0045 pull request feed.
- **Replaced by the model:** 0009 and 0011 Discover updates and reboot (O-10), 0013 public GHCR image (sysupdate has no OCI source), 0014 following Fedora `latest` (the Archive date replaces it), 0019, 0020, 0022, 0023, 0026 ISO, Anaconda and its settings (sysinstall), 0029 to 0031 and 0046 ISO hosting (R2 may host update files instead, O-5), 0034 manual rollback (automatic now), 0035 audio by layering (O-8), 0033 switching an installed Kinoite (reinstall, O-11).
- **Not applicable:** 0001 and 0038 Fedora versions, 0021 offline Flatpaks (already superseded), 0039 and 0043 Discover with bootc, 0041 `systemd-remount-fs` on composefs (no composefs here [U]), 0030 visual word of the download page (only if a download page comes back).

## 10. Machines

- [D] Intel NUC (i5-8259U, Iris Plus 655, 16 GB): the owner's main machine; host OS Fedora Kinoite / `swarf-os/image`. Builds and boot tests run in GitHub Actions, not on it (D-8). A local VM may run there for manual checks, rootless.
- [D] Packard Bell laptop (Intel AX101 Wi-Fi): the hardware target (O-9 first).
- [D] Framework Laptop 13 Pro (Intel Core Ultra Series 3): only receives an OS the owner fully controls and that has run without trouble for a month on the owner's other machines; never a trial or a first install (D-12). Linux 6.18 minimum, 7.0+ recommended (Framework matrix, Oct 2026).
- [V] CI runners: GitHub standard runners (`ubuntu-24.04`, 4 vCPU for a public repository) have `/dev/kvm` as `root:kvm 0660` and the `runner` user is not in `kvm`; it works after the udev rule `99-kvm4all.rules` (MODE 0666) from GitHub's changelog of 2024-04-02 (run 45183077202). The pinned mkosi action sets this up.

## 11. Tests and acceptance criteria

### Tests

| # | Test | Step |
|---|------|------|
| 1 | Minimal composition and identity: console image from our package list only; check `os-release`, boot entries, initrd name, hostname, enabled services; then the Plasma delta. | 1 (done), 7 |
| 2 | Update failure and rollback: interrupt download and write, publish a non-booting version, check the previous one still boots. | 5 |
| 3 | Secure Boot with our keys (OVMF in setup mode): a changed UKI, a UKI signed by another key, a changed `/usr` and a `/usr` signature by another key must not boot; an unchanged copy must. | 2 |
| 4 | Encryption and shared state: passphrase, update, rollback, recovery key; `/etc`, `/var`, users and Flatpaks survive. | 3, 5, 11 |
| 5 | Install from a USB stick on a blank disk (live + installer), network off; then Plasma. | 6 (console), 12 (real) |
| 6 | Size of an update download and hosting cost per release. | 11 |
| 7 | Plasma boot test in CI: the session (or login screen, O-7) is reached, `systemctl --failed` is empty, no unwanted package or service (the promotion rule of `swarf-os/image`). | 7, 10 |

### Base acceptance criteria (steps 1 to 6)

Cited by number in section 12; all in a VM with OVMF Secure Boot (our keys enrolled) and no TPM:
1. installs from a virtual USB stick onto a blank virtual disk, network off;
2. first boot enrolls passphrase and recovery key; `systemd-cryptenroll` then lists only a password slot and a recovery slot;
3. reboot asks the passphrase; the recovery key also opens the disk;
4. update A → B works; C (deliberately broken) fails 3 times and the machine returns to B by itself;
5. a tampered UKI and a tampered `/usr` are refused;
6. `os-release`, `issue` and boot entries show only the image's own name;
7. scripts log to a file and print only OK or useful errors.

### swarf acceptance (before step 13)
- [P] One month of daily use on the Packard Bell without trouble, with at least two real updates and one forced rollback seen.

## 12. Plan

One step per session. Sizes: S (small), M (one session), L (a full session with one risky topic). Template: Needs root, Size, Depends on, Scope, Out of scope (when useful), Done when. "Criteria n" refers to section 11.

### Base (steps 1 to 6): console only

#### Step 1: Build bench and first boot (done, PR #1 merged 2026-11-23)
- Needs root: CI only. Size: L. Depends on: nothing.
- Scope: mkosi recipe, `base` profile (console); mkosi pinned; build without sudo; our own `os-release` and `issue`; systemd-boot and UKI; A/B `/usr` layout with verity, image policy, factory `/etc`; no ParticleOS VM convenience; logs to a file.
- Done when: the `base` image boots to a console in the VM; criteria 6 and 7; no ParticleOS credential or debug shell in the release configuration.
- Result: first green run 45239430422. Fixes found on the way: test credentials answer systemd-firstboot (it blocks without them); the Arch initrd set the hostname `archlinux` (fixed by our initrd `os-release` and `swarf-default-hostname.service`).

#### Step 2: Signatures and Secure Boot (done, PR #2 merged 2026-11-24)
- Needs root: CI only. Size: M. Depends on: 1.
- Scope: throw-away keys (D-10); signed systemd-boot, UKI and `/usr` verity signature (`usr=signed`); OVMF in setup mode, keys enrolled at first boot.
- Done when: criterion 5, plus an image signed by another key is refused (test 3).

#### Step 3: Encryption
- Needs root: VM or CI only. Size: M to L. Depends on: 2.
- Scope: root with `Encrypt=key-file` and the empty key, created at first boot; O-1; the first-boot unit enrolls the passphrase, wipes the empty key and creates the recovery key; `root=encrypted` in the image policy.
- Done when: criteria 2 and 3, with a test passphrase identical in AZERTY and QWERTY (the layout is step 4).

#### Step 4: Account and keyboard
- Needs root: VM or CI only. Size: M to L. Depends on: 3.
- Scope: D-15 (one password, typed once, for the LUKS slot and the account) and O-3.
- Done when: the account exists after first boot with the same password as the passphrase, typed once; a passphrase that differs between AZERTY and QWERTY works at the LUKS prompt and on the console with an AZERTY install; same layout everywhere, variant included.

#### Step 5: Updates and rollback
- Needs root: VM or CI only. Size: M to L. Depends on: 2.
- Scope: sysupdate transfers pointing to a local HTTP server; three published versions A, B and C (deliberately broken); signed `SHA256SUMS`, or `Verify=no` explicitly accepted for this step and written in `docs/STATUS.md`.
- Done when: criterion 4; an interrupted download leaves the running version intact; `/etc` and `/var` survive the update.

#### Step 6: Installer and base acceptance
- Needs root: VM or CI only. Size: M. Depends on: 4, 5.
- Scope: Installer UKI profile with the stock systemd-sysinstall; one script that runs every criterion. Before writing it, read how KDE Linux builds its live session and its installer in its recipe (3.2; the owner's wish, 2026-11-24): ideas only.
- Done when: criterion 1, then criteria 1 to 7 chained by one script on a blank virtual disk.

#### Base handover (after step 6)
- [P] Tag the commit that passed step 6 (for example `base-1`) and write `docs/base-handover.md`: what the `base` profile contains, the lessons, the known gaps. pxOS takes the base from there in its own step 7; how (copy, shared profiles or other) is decided on the pxOS side. Until then, keep `base` neutral (section 5).
- [D] What pxOS expects of the base (pxOS SPEC II-9). A decision here that breaks one of these points is told to the owner, who decides whether pxOS adds it in its step 7:
  1. signed `/usr` (verity, `usr=signed`) and signed UKI, Secure Boot with the owner's keys;
  2. a LUKS2 root opened by a passphrase, no TPM, plus a recovery key slot;
  3. a classic user created at first boot, not systemd-homed, with one password typed once for the LUKS slot and the account (D-15);
  4. the installed keyboard layout at the LUKS prompt and on the console;
  5. A/B updates with rollback (sysupdate) and the stock installer (sysinstall);
  6. the identity replaceable in one place, and the factory `/etc` scheme.

### swarf (steps 7 to 13)

#### Step 7: Plasma session
- Needs root: VM or CI only. Size: L. Depends on: 6.
- Scope: `plasma` profile (9.1); O-7; Plymouth in the initrd with a stock theme and fonts; Plasma's keyboard layout from the system setting; Flatpak with the Flathub remote; read KDE Linux's recipe first (3.2); check O-10 (Discover's sysupdate backend on Arch).
- Done when: the encrypted, signed image boots in the VM to Plasma as decided in O-7; test 7 passes in CI; a Flathub app installs.

#### Step 8: swarf's settings
- Needs root: VM or CI only. Size: M. Depends on: 7.
- Scope: the "carry over" and "adapt" items of 9.2 that concern the image (hardening, telemetry, KWallet, quiet defaults, firewall zone, task manager, Discover reviews, apps on demand), each with its ADR and an automated check.
- Done when: every item is in the image and checked by the CI boot test.

#### Step 9: Laptop hardware and audio
- Needs root: VM or CI only. Size: M. Depends on: 7.
- Scope: Packard Bell firmware and UPower (9.1); O-8 decided and built.
- Done when: the firmware files are in the image (manifest); audio exists as decided in O-8 and its CI test passes.

#### Step 10: Daily CI and promotion
- Needs root: CI only. Size: M. Depends on: 7.
- Scope: daily build at the Archive date; manifest gate (packages and units, no versions); boot test (tests 1, 3 and 7); `testing` then `stable`; drift issue on failure; Archive date bump by pull request when tests pass; logic in `scripts/`, YAML only calls them.
- Done when: a scheduled run builds, tests and promotes; a failing test keeps `stable` and opens the drift issue.

#### Step 11: Hosting and real updates
- Needs root: CI only. Size: M to L. Depends on: 5, 10.
- Scope: O-5 (hosting, real keys replacing the throw-away ones, how CI signs); signed `SHA256SUMS`; sysupdate transfers pointing to the server; O-10; tests 4 and 6.
- Done when: a VM installed from `stable` updates itself from the server to a newer `stable`, Flatpaks and `/home` intact; download size and monthly cost recorded.

#### Step 12: Real installation on the Packard Bell
- Needs root: on the machine, by the owner. Size: M. Depends on: 11, O-9.
- Scope: O-11 (migration), O-6 (Microsoft CAs, fwupd); install from a USB stick; Secure Boot with our keys; real Wi-Fi, battery, brightness, audio as in O-8.
- Done when: the machine installs, boots with Secure Boot on our keys, unlocks with the passphrase and reaches Plasma; hardware works or its gaps are listed. Then the month of daily use (section 11).

#### Step 13: Merge into `swarf-os/image`
- Needs root: no. Size: M. Depends on: 12 and the swarf acceptance (section 11).
- Scope: the recipe replaces the bootc one in `swarf-os/image` (the bootc recipe archived on a branch or tag [P]); `swarf-os/image` moves to AGPL-3.0-or-later (D-6); README (install, updates, rollback, audio); ADRs carried; this spec becomes that repository's `SPEC.md`.
- Done when: `swarf-os/image` builds the new image in CI; the owner's machines follow it.

## 13. Open questions

| ID | Question | Resolved by |
|----|----------|-------------|
| O-1 | First-boot enrollment: our own unit or a drop-in on systemd's wizard | Step 3 |
| O-2 | ~~First-boot account~~ Closed 2026-11-24: one password (D-15) | Done |
| O-3 | Keyboard layout at the LUKS prompt: sysinstall credential or signed command-line addon | Step 4 |
| O-4 | Channel selection per machine (override in `/etc/sysupdate.d/`?) | Step 5 or later |
| O-5 | Hosting, real keys and where they live, how CI signs, promotion rules | Step 11 |
| O-6 | Microsoft UEFI CAs in `db` next to our keys; fwupd with our keys | Step 12 |
| O-7 | Session start: autologin into Plasma after the LUKS unlock, or the Plasma login screen | Step 7 |
| O-8 | Audio: in the image, an audio variant, or an audio system extension | Step 9 |
| O-9 | Packard Bell: can its firmware enter setup mode or accept custom keys? | Owner, before step 12 (best now) |
| O-10 | Update front-end: Discover's sysupdate backend on Arch, or the sysupdate timer plus a notification | Step 11 (checked in step 7) |
| O-11 | Migration of the Packard Bell from `swarf-os/image`: reinstall, `/home` saved first | Step 12 |
| O-12 | Keep the recipe two-distribution capable (Fedora fallback), or Arch only | Step 6 |
| O-13 | Own copy of one Archive date's packages if the Archive stays unstable; `ParallelDownloads=3` | When the Archive fails again |

## 14. Decision log

| ID | Decision | Tag | Date |
|----|----------|-----|------|
| D-1 | Image-based model: our own mkosi recipe on the ParticleOS model (A/B with systemd-sysupdate, signed `/usr`, systemd-sysinstall), not bootc | [D] | 2026-11-18 |
| D-2 | Arch as package provider: official repositories plus the owner's own repository only; never AUR or another third-party repository | [D] | 2026-11-17 / 18 |
| D-3 | Packages frozen on the Arch Linux Archive at one date, moved forward only after the tests pass; only tested snapshots are published (`testing`, then `stable`) | [D] | before 2026-11-17 |
| D-4 | Secure Boot with the owner's own keys only (setup mode); no shim; public users enroll the keys or disable Secure Boot | [D] | 2026-11-18 |
| D-5 | LUKS2 passphrase at boot, no TPM, a recovery key in its own slot | [D] | 2026-11-17 |
| D-6 | Repository `swarf-os/image-mkosi`, public, AGPL-3.0-or-later; merged into `swarf-os/image` if it proves itself, which then moves to AGPL too; no code derived from Zirconium | [D] | 2026-11-23 |
| D-7 | KDE Plasma (Wayland) on this base; the console base (steps 1 to 6) is also the base of pxOS | [D] | 2026-11-23 |
| D-8 | Build and boot tests in GitHub Actions (public repository, KVM through the udev rule); nothing runs on the owner's host | [D] | 2026-11-23 |
| D-9 | mkosi v27.1 pinned through `systemd/mkosi@ecf7f57`, upgraded deliberately | [D] | 2026-11-23 |
| D-10 | Throw-away signing key for the experiment in repository secrets `SWARF_SIGNING_KEY` and `SWARF_SIGNING_CERT`, replaced by the real keys with O-5; `main` only built with them | [D] | 2026-11-23 |
| D-11 | No package layering on installed machines; options are image variants or signed system extensions; apps are Flatpaks; tools go in containers | [D] | 2026-11-17 |
| D-12 | The Framework 13 Pro only receives an OS the owner fully controls and that ran a month without trouble on the owner's other machines | [D] | 2026-11-23 |
| D-13 | Plan in simply numbered steps, one step per session; no codes such as OS0 or sub-steps such as 6b | [D] | 2026-11-23 |
| D-14 | This work has its own Claude project and this spec (`SPEC.md` in this repository), split from the pxOS project after step 2 | [D] | 2026-11-23 / 24 |
| D-15 | First-boot account: one password typed once for the LUKS slot and the account (also what pxOS needs); the drift after a password change in Plasma is accepted for now | [D] | 2026-11-24 |

## 15. Sources

- ParticleOS, commit b605add (README, `mkosi.conf`, `mkosi.conf.d/arch/`, `mkosi.extra/usr/lib/repart.d/`, `mkosi.sysupdate/`, `mkosi.uki-profiles/`, `mkosi.profiles/`, `mkosi.finalize`): https://github.com/systemd/particleos
- systemd, commit d26f3cb of 2026-11-17 (`NEWS` for 261 and 262; `man/systemd-sysinstall.xml`, `man/systemd-repart.xml`, `man/repart.d.xml`, `man/systemd-cryptenroll.xml`, `man/sysupdate.d.xml`, `man/sysupdate.features.xml`, `man/systemd-sysext.xml`, `man/loader.conf.xml`; `units/systemd-cryptenroll-firstboot.service`; `src/sysinstall/sysinstall.c`; `src/cryptenroll/`; `src/shared/varlink-io.systemd.SysInstall.c`, `varlink-io.systemd.CryptEnroll.c`): https://github.com/systemd/systemd
- mkosi v27.1 manual and code (`mkosi/bootloader.py`: Secure Boot auto-enrollment; `genkey`): https://github.com/systemd/mkosi
- Zirconium, read 2026-11-23 (`mkosi.conf`, `Justfile`, `mkosi.profiles/sysupdate/`, `.github/workflows/`): https://github.com/zirconium-dev/zirconium
- KDE Linux, "History & Architecture" (modified 2026-11-04): https://linux.kde.org/docs/background/
- KDE Linux installation page: https://linux.kde.org/docs/install/
- KDE Linux developer page: https://linux.kde.org/docs/kde-linux-dev/ ; LWN, "KDE Linux" (2025-09-10): https://lwn.net/SubscriberLink/1037166/caa6979c16a99c9e
- Discover sysupdate backend (Alpine package): https://pkgs.alpinelinux.org/package/edge/community/x86/discover-backend-sysupdate
- `swarf-os/image`: `SPEC.md` (draft 15), `AGENTS.md`, `PROGRESS.md`, `whitelist.txt`, `blacklist.txt`, `docs/adr/0001` to `0046`, read 2026-11-23: https://github.com/swarf-os/image
- Arch packages: https://archlinux.org/packages/core/x86_64/systemd/
- Secure Boot certificate expiration (Red Hat): https://www.redhat.com/en/blog/expiration-secure-boot-signing-certificates-2026
- Cloudflare R2 pricing: https://developers.cloudflare.com/r2/pricing
- GitHub Releases limits: https://docs.github.com/en/repositories/releasing-projects-on-github/about-releases
- GitHub, KVM on standard runners (changelog 2024-04-02): https://github.blog/changelog/2024-04-02-github-actions-hardware-accelerated-android-virtualization-now-available/
- Framework Linux support matrix: https://knowledgebase.frame.work/framework-component-linux-support-matrix-B1gwmFtPgg
- ParticleOS at FOSDEM 2026: https://fosdem.org/2026/events/attachments/DVVAV9-particle-os-from-trad-distro-to-immutable-image/slides/267652/fosdem_20_tcaoshr.pdf
- All Systems Go 2026, sysinstall and graphical installers: https://cfp.all-systems-go.io/all-systems-go-2026/talk/SBUXXA/
- Research report "Une base Linux personnelle construite en CI" (2026-11-09), in the pxOS project files (`recherche/base-linux-ci-2026-11-09.md`); copy it into this project if needed.

## Appendix A. Where each item came from

### From the pxOS SPEC 0.9

| This spec | pxOS SPEC 0.9 |
|-----------|---------------|
| 1 What this is | II-0, II-9 |
| 2 Goals | II-1 |
| 3, 3.1 Model, ParticleOS | II-2, II-2.1 |
| 4 Packages and build | II-3 (D-22 → D-3) |
| 5 Profiles and extensions | II-4 |
| 6 Installation | II-5 |
| 7 Boot chain, encryption, account | II-6 |
| 8 Updates and hosting | II-7 |
| 11 Tests and criteria | II-10, II-11 (criteria numbered the same) |
| 12 Steps 1 to 6 | Part III, steps 1 to 6 (same numbers and names) |

| This spec | pxOS SPEC 0.9 |
|-----------|---------------|
| D-1 | D-39 |
| D-2 | D-40, D-12 |
| D-3 | II-3 (former D-22, D-23) |
| D-4 | D-41 |
| D-5 | II-6 [D], D-35 |
| D-6 | D-47, D-51 |
| D-7 | D-47 |
| D-11 | D-38 |
| D-12 | D-52 |
| D-13 | D-46 |
| O-1 | O-25 |
| O-2, D-15 | O-18 (and D-34 for pxOS) |
| O-4 | O-20 |
| O-5 | O-22 |
| O-6 | O-24 |
| O-12 | II-2 [P] (two-distribution recipe) |

Code comments that cite the pxOS SPEC (to update when this spec lands in the repository): `mkosi.conf` ("SPEC II-3", "D-22", "SPEC II-7"), `.github/workflows/build.yml` ("SPEC II-3"), `mkosi.postinst.chroot` ("SPEC II-1, criterion 6"), `scripts/signing-keys.sh` ("SPEC II-7", "SPEC II-6"), `scripts/secureboot-test.sh` ("SPEC II-10 test 3, II-11 criterion 5"). Criteria keep their numbers.

### From the `swarf-os/image` SPEC (draft 15)

Goal and "not wanted by default" (2), rules for agents (0), package lists and KDE apps (9.1), settings (9.2), Flatpak and apps on demand (8, 9.2), updates through Discover (O-10), Packard Bell and its Secure Boot (7, 10), Cloudflare hosting (8), CI promotion and drift issue (12, step 10).

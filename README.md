# swarf-os/image-mkosi

Experimental rebuild of swarf-os on an image-based model: an mkosi recipe on the
ParticleOS model (A/B `/usr` updated by systemd-sysupdate, signed UKI, LUKS),
Arch Linux packages, KDE Plasma. If it works out, it will be merged into
`swarf-os/image`.

Status: step 2 (signatures and Secure Boot). The console image boots in a VM
with Secure Boot enforced by our own keys, and `/usr` is refused unless its
verity root hash carries our signature (`usr=signed`).

## Signing keys

mkosi reads `mkosi.key` and `mkosi.crt` next to `mkosi.conf` (never committed).
One key signs systemd-boot, the UKI and the `/usr` verity root hash, and its
certificate is put on the ESP for Secure Boot enrollment (`/loader/keys/auto`)
and in `/usr/lib/verity.d`.

During the experiment these are throw-away keys made for this repository with
`mkosi genkey`, stored in the repository secrets `SWARF_SIGNING_KEY` (the
private key) and `SWARF_SIGNING_CERT` (the certificate). They will be replaced
by the real keys when hosting is decided. A push to `main` is only built with
them; a pull request without access to them is signed with a key made for that
run.

## Tests (CI, in a VM with OVMF Secure Boot in setup mode)

- `scripts/boot-test.sh`: our keys are enrolled at first boot, then the image
  boots with Secure Boot enabled, to a console, with our identity only.
- `scripts/secureboot-test.sh`: a changed UKI, a UKI signed by another key, a
  changed `/usr`, and a whole `/usr` rebuilt and signed by another key (new
  hash tree, signature and partition UUIDs) must not boot; an unchanged copy
  made the same way must.

The UKI command line carries `usrhash=` (added by mkosi), so the signed UKI
pins the exact `/usr` it boots. Swapping only the signature partition for one
made by another key over the same root hash changes nothing and still boots;
the signature partition matters where no UKI pins the hash (sysupdate,
`systemd-dissect`).

## License

AGPL-3.0-or-later, see `LICENSE`.

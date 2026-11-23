Test-only credentials (in `credentials/`) passed to the VM by `scripts/boot-test.sh`
(`mkosi --credential=tests/credentials vm`). They never reach the image.

- `firstboot.*`, `passwd.hashed-password.root` (`!`, account locked): answer
  systemd-firstboot so the unattended boot does not stop at its prompts.
  Account creation at first boot is step 4.
- `systemd.extra-unit.swarf-ci-check.service` and the `multi-user.target`
  drop-in: print the checks on the console, then power off.

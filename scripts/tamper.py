#!/usr/bin/python3
# SPDX-License-Identifier: AGPL-3.0-or-later
"""Make a tampered copy of the built disk image for the Secure Boot tests.

Usage: tamper.py CASE IMAGE OUTPUT WORKDIR

CASE is one of:
  uki-control     UKI copied out of the ESP and written back unchanged (must boot)
  uki-modified    UKI command line changed from usr=signed to usr=verity
  uki-other-key   UKI signature replaced by one made with another key
  usr-modified    one byte of /usr changed (the EROFS superblock)
  usr-other-key   /usr changed, its hash tree rebuilt and signed by another key

Runs inside `mkosi box` (tools tree: mtools, sbsigntools, openssl). The other
key is created in WORKDIR the first time it is needed.
"""

import base64
import hashlib
import json
import struct
import subprocess
import sys
import uuid
from pathlib import Path

ESP_TYPE = uuid.UUID("c12a7328-f81f-11d2-ba4b-00a0c93ec93b")
SECTOR = 512
EROFS_MAGIC = 0xE0F5E1E2  # little-endian u32 at byte 1024 of an EROFS image


def run(*cmd: str, **kw) -> subprocess.CompletedProcess:
    return subprocess.run(cmd, check=True, **kw)


def partitions(image: Path) -> list[dict]:
    """Read the primary GPT: type, name, byte offset and size of each entry."""
    with image.open("rb") as f:
        f.seek(SECTOR)
        hdr = f.read(92)
        if hdr[:8] != b"EFI PART":
            sys.exit(f"ERROR: no GPT header in {image}")
        entries_lba, count, size = struct.unpack_from("<QII", hdr, 72)
        f.seek(entries_lba * SECTOR)
        table = f.read(count * size)
    parts = []
    for i in range(count):
        e = table[i * size : (i + 1) * size]
        ptype = uuid.UUID(bytes_le=e[:16])
        if ptype.int == 0:
            continue
        first, last = struct.unpack_from("<QQ", e, 32)
        name = e[56:128].decode("utf-16-le").rstrip("\0")
        parts.append(
            {
                "number": i + 1,
                "type": ptype,
                "name": name,
                "offset": first * SECTOR,
                "size": (last - first + 1) * SECTOR,
            }
        )
    return parts


def find(parts: list[dict], kind: str) -> dict:
    """kind: esp (by type), usr or sig (by the labels set in mkosi.repart/)."""
    match = {
        "esp": lambda p: p["type"] == ESP_TYPE,
        "usr": lambda p: p["name"].startswith("swarf_") and "_verity" not in p["name"],
        "verity": lambda p: p["name"].startswith("swarf_") and p["name"].endswith("_verity"),
        "sig": lambda p: p["name"].startswith("swarf_") and p["name"].endswith("_verity_sig"),
    }[kind]
    hits = [p for p in parts if match(p)]
    if len(hits) != 1:
        sys.exit(f"ERROR: expected one {kind} partition, found {len(hits)}: {parts}")
    return hits[0]


def other_key(work: Path) -> tuple[Path, Path]:
    key, crt = work / "other.key", work / "other.crt"
    if not key.exists():
        # Same command as `mkosi genkey` (mkosi/__init__.py, v27.1), another name.
        run(
            "openssl", "req", "-new", "-x509", "-newkey", "rsa:2048",
            "-keyout", str(key), "-out", str(crt), "-days", "30",
            "-subj", "/CN=not swarf/", "-nodes",
            stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL,
        )  # fmt: skip
    return key, crt


def patch(image: Path, offset: int, data: bytes) -> None:
    with image.open("r+b") as f:
        f.seek(offset)
        f.write(data)


def uki_case(case: str, image: Path, work: Path) -> str:
    esp = find(partitions(image), "esp")
    fs = f"{image}@@{esp['offset']}"
    listing = run("mdir", "-/", "-b", "-i", fs, "::/EFI/Linux", capture_output=True, text=True).stdout
    ukis = [line.strip() for line in listing.splitlines() if line.strip().lower().endswith(".efi")]
    if len(ukis) != 1:
        sys.exit(f"ERROR: expected one UKI in /EFI/Linux on the ESP, found: {ukis}")
    uki = ukis[0]
    local = work / "uki.efi"
    run("mcopy", "-n", "-o", "-i", fs, uki, str(local))

    if case == "uki-modified":
        data = local.read_bytes()
        if data.count(b"usr=signed") != 1:
            sys.exit("ERROR: 'usr=signed' not found exactly once in the UKI")
        local.write_bytes(data.replace(b"usr=signed", b"usr=verity"))
        what = "command line usr=signed -> usr=verity, signature kept"
    elif case == "uki-other-key":
        key, crt = other_key(work)
        run("sbattach", "--remove", str(local), stdout=subprocess.DEVNULL)
        run("sbsign", "--key", str(key), "--cert", str(crt), "--output", str(local), str(local),
            stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)  # fmt: skip
        what = "signature replaced by one from another key"
    else:
        what = "copied out and back unchanged"

    run("mcopy", "-o", "-i", fs, str(local), uki)
    return f"{uki}: {what}"


def usr_case(case: str, image: Path, work: Path) -> str:
    parts = partitions(image)
    if case == "usr-modified":
        usr = find(parts, "usr")
        with image.open("rb") as f:
            f.seek(usr["offset"] + 1024)
            (magic,) = struct.unpack("<I", f.read(4))
        if magic != EROFS_MAGIC:
            sys.exit(f"ERROR: no EROFS superblock in partition {usr['name']}")
        patch(image, usr["offset"] + 1024 + 8, b"\xff")
        return f"{usr['name']}: one byte of the EROFS superblock changed"

    # usr-other-key: a whole /usr made and signed by someone else, as a
    # careful attacker would: change the data, rebuild the verity hash tree,
    # sign the new root hash with another key, and give the partitions the
    # UUIDs that systemd derives from that root hash. Only our signed UKI,
    # which carries our usrhash=, stands in the way.
    usr, verity, sig = find(parts, "usr"), find(parts, "verity"), find(parts, "sig")
    last = usr["offset"] + usr["size"] - 1  # padding at the end of /usr: EROFS still mounts
    with image.open("rb") as f:
        f.seek(last)
        byte = f.read(1)
    patch(image, last, bytes([byte[0] ^ 0xFF]))

    data, tree = work / "usr.img", work / "verity.img"
    for part, path in ((usr, data), (verity, tree)):
        with image.open("rb") as f, path.open("wb") as out:
            f.seek(part["offset"])
            out.write(f.read(part["size"]))
    out = run(
        "veritysetup", "format", "--hash=sha256", "--data-block-size=4096", "--hash-block-size=4096",
        str(data), str(tree), capture_output=True, text=True,
    ).stdout  # fmt: skip
    roothash = next(line.split(":", 1)[1].strip() for line in out.splitlines() if line.startswith("Root hash:"))
    patch(image, verity["offset"], tree.read_bytes())

    key, crt = other_key(work)
    # systemd-repart signs the root hash as a hex string: PKCS#7, detached,
    # no attributes, binary (src/repart/repart.c, v258).
    signed = run(
        "openssl", "smime", "-sign", "-binary", "-noattr", "-outform", "DER",
        "-inkey", str(key), "-signer", str(crt),
        input=roothash.encode(), capture_output=True,
    ).stdout  # fmt: skip
    der = run("openssl", "x509", "-in", str(crt), "-outform", "DER", capture_output=True).stdout
    new = {
        "rootHash": roothash,
        "certificateFingerprint": hashlib.sha256(der).hexdigest(),
        "signature": base64.b64encode(signed).decode(),
    }
    text = json.dumps(new, separators=(",", ":")).encode()
    if len(text) + 1 > sig["size"]:
        sys.exit("ERROR: new signature does not fit in the partition")
    patch(image, sig["offset"], text + b"\0" * (sig["size"] - len(text)))

    # Partition UUIDs: first and second half of the root hash (systemd-repart).
    for part, half in ((usr, roothash[:32]), (verity, roothash[32:64])):
        run("sfdisk", "--quiet", "--part-uuid", str(image), str(part["number"]), str(uuid.UUID(half)),
            stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)  # fmt: skip
    return f"/usr changed, hash tree rebuilt, root hash {roothash[:12]}… signed by another key, UUIDs updated"


def main() -> None:
    case, image, output, work = sys.argv[1], Path(sys.argv[2]), Path(sys.argv[3]), Path(sys.argv[4])
    work.mkdir(parents=True, exist_ok=True)
    run("cp", "--sparse=always", str(image), str(output))
    if case.startswith("uki-"):
        print(uki_case(case, output, work))
    elif case in ("usr-modified", "usr-other-key"):
        print(usr_case(case, output, work))
    else:
        sys.exit(f"ERROR: unknown case {case}")


if __name__ == "__main__":
    main()

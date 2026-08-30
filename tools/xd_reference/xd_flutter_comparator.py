#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""Deterministic XD ↔ Flutter golden comparator (``MERZOX-UI-GOLDEN-I5-I6-D3``).

This tool produces **reproducible measurements** between an already accepted
Flutter baseline golden and the locked XD reference artboard for the same seed.

It is deliberately *not*:

* a visual auto-fixer — it never writes to a Flutter golden, the ``.xd``
  package, the exporter source, or any production source;
* a mapping discovery tool — the XD↔Flutter semantic mapping is **locked** in
  ``golden_mapping.json`` and selected by manifest id. The comparator will never
  pick a different artboard because its MAE happens to be smaller;
* a parity gate — there is **no** pixel-perfect / parity threshold anywhere in
  this module. Structural validation passes or fails; visual numbers are only
  measurements.

Everything here is Python standard library plus the sibling
``xd_reference_exporter`` module. No Pillow, numpy, OpenCV, imageio or scipy.
"""

from __future__ import annotations

import argparse
import hashlib
import json
import re
import math
import os
import struct
import sys
import zlib
from dataclasses import dataclass
from pathlib import Path, PurePosixPath
from typing import Any, Dict, List, Mapping, Optional, Sequence, Tuple

MODULE_DIR = Path(__file__).resolve().parent
if str(MODULE_DIR) not in sys.path:
    sys.path.insert(0, str(MODULE_DIR))

import xd_reference_exporter as xdref  # noqa: E402  (sibling module, path set above)


# ---------------------------------------------------------------------------
# Constants — the locked contract.
# ---------------------------------------------------------------------------

#: Iteration stamp for this comparator.
COMPARATOR_ITERATION = "MERZOX-UI-GOLDEN-I5-I6-D3"

#: Schema of ``golden_mapping.json``.
MAPPING_SCHEMA = "merzox.xd_flutter_mapping/1"

#: Schema of the comparison report this tool emits.
REPORT_SCHEMA = "merzox.xd_flutter_comparison/1"

#: The canonical Merzox comparison viewport. Both sides are measured here.
TARGET_WIDTH = 375
TARGET_HEIGHT = 812

#: The seed names a mapping may declare.
#:
#: The accepted corpus is the mapping file itself, not a constant here: freezing
#: the names would mean no further artboard could ever be measured. What is
#: still guaranteed is structural - a seed name must match this shape, names
#: must be unique, and the report follows mapping order exactly - so a mapping
#: cannot silently acquire a malformed or duplicated entry.
SEED_NAME_PATTERN = re.compile(r"^[a-z][a-z0-9_]*$")

#: The smallest corpus that is still a corpus.
MINIMUM_MAPPING_ENTRIES = 1

#: ``--seed`` value that selects every mapping entry, in mapping order.
SEED_ALL = "all"

#: Accepted normalization policies.
NORMALIZATION_EXACT = "exact"
NORMALIZATION_EXTEND_FINAL_ROW = "extend_final_row_to_812"
#: A tall artboard is a SCROLLABLE screen, not a tall screen. The corpus draws
#: below-the-fold content inline so it is visible to the reader; the device
#: viewport is still 375x812, so the comparable state is the artboard's TOP
#: 812 rows - the screen before the user scrolls.
NORMALIZATION_CROP_TOP = "crop_top_to_812"
SUPPORTED_NORMALIZATIONS: Tuple[str, ...] = (
    NORMALIZATION_EXACT,
    NORMALIZATION_EXTEND_FINAL_ROW,
    NORMALIZATION_CROP_TOP,
)

#: Both height policies require the artboard to be the target width exactly.
#: A different width is a real shape mismatch, never something to paper over.
NORMALIZATION_SOURCE_WIDTH = 375

#: Retained for the report and for callers that named the original constants.
EXTEND_SOURCE_WIDTH = NORMALIZATION_SOURCE_WIDTH

#: The only measurement status this tool emits. Never "passed"/"parity".
MEASUREMENT_STATUS_MEASURED = "measured"

#: Integer BT.601 weights for the deterministic *coarse* luma metric. The
#: quotient is floor-divided, which is exactly what makes it "coarse": the
#: metric is integer-quantised and therefore bit-reproducible on every host.
COARSE_LUMA_WEIGHTS: Tuple[int, int, int] = (299, 587, 114)
COARSE_LUMA_DENOMINATOR = 1000

#: Channel tolerances for the "within N" ratios.
WITHIN_5_TOLERANCE = 5
WITHIN_10_TOLERANCE = 10

#: Machine-readable statement of what these numbers are — and are not.
MEASUREMENT_POLICY: Dict[str, Any] = {
    "metrics_are_measurements_only": True,
    "metrics_are_pass_fail": False,
    "parity_threshold_exists": False,
    "parity_threshold": None,
    "pixel_perfect_claimed": False,
    "semantic_mapping_is_locked": True,
    "semantic_mapping_selected_by_visual_score": False,
    "semantic_mapping_selector": "xd_manifest_id",
    "structural_validation_is_fail_closed": True,
    "exporter_unsupported_nodes_are_fail_closed": True,
    "measurement_status_vocabulary": [MEASUREMENT_STATUS_MEASURED],
    "notes": (
        "Visual metrics in this report are diagnostic measurements only. No "
        "parity, pixel-perfect or pass/fail threshold exists. The XD artboard "
        "for each seed is fixed by manifest id in golden_mapping.json and is "
        "never chosen from the lowest MAE. Visual remediation is a later phase."
    ),
}

#: Repository root, derived deterministically from this file's location:
#: ``<repo>/tools/xd_reference/xd_flutter_comparator.py``. The current working
#: directory is deliberately never consulted.
REPO_ROOT = Path(__file__).resolve().parents[2]

#: Default mapping location — the sibling ``golden_mapping.json``.
DEFAULT_MAPPING_PATH = MODULE_DIR / "golden_mapping.json"

#: Required entry / nested-``xd`` fields.
REQUIRED_ENTRY_FIELDS: Tuple[str, ...] = (
    "seed",
    "flutter_golden",
    "xd",
    "normalization",
    "semantic_reason",
)
REQUIRED_XD_FIELDS: Tuple[str, ...] = (
    "name",
    "manifest_id",
    "artboard_path",
    "width",
    "height",
)

PNG_SIGNATURE = b"\x89PNG\r\n\x1a\n"

#: PNG colour types this decoder supports, mapped to their sample count.
PNG_COLOR_TYPE_CHANNELS: Dict[int, int] = {0: 1, 2: 3, 4: 2, 6: 4}


class ComparatorError(RuntimeError):
    """Raised for every structural / configuration / decoding failure."""


# ---------------------------------------------------------------------------
# Standard-library PNG decoding.
# ---------------------------------------------------------------------------


@dataclass(frozen=True)
class DecodedImage:
    """A decoded, non-interlaced, 8-bit image expanded to straight RGBA."""

    width: int
    height: int
    pixels: bytes  #: ``width * height * 4`` bytes, row-major, R,G,B,A.

    def __post_init__(self) -> None:
        expected = self.width * self.height * 4
        if len(self.pixels) != expected:
            raise ComparatorError(
                "Decoded RGBA buffer is "
                f"{len(self.pixels)} bytes but {self.width}x{self.height} "
                f"requires {expected}."
            )

    @property
    def stride(self) -> int:
        """Bytes per RGBA row."""
        return self.width * 4

    def row(self, y: int) -> bytes:
        if not 0 <= y < self.height:
            raise ComparatorError(f"Row {y} is outside a {self.height}-row image.")
        return self.pixels[y * self.stride : (y + 1) * self.stride]

    def pixel(self, x: int, y: int) -> Tuple[int, int, int, int]:
        if not 0 <= x < self.width or not 0 <= y < self.height:
            raise ComparatorError(
                f"Pixel ({x}, {y}) is outside a {self.width}x{self.height} image."
            )
        offset = (y * self.width + x) * 4
        return (
            self.pixels[offset],
            self.pixels[offset + 1],
            self.pixels[offset + 2],
            self.pixels[offset + 3],
        )

    def rgba_tuples(self) -> List[Tuple[int, int, int, int]]:
        """Every pixel as an ``(r, g, b, a)`` tuple, row-major."""
        data = self.pixels
        return [
            (data[i], data[i + 1], data[i + 2], data[i + 3])
            for i in range(0, len(data), 4)
        ]

    def sha256(self) -> str:
        """SHA-256 of the normalized RGBA byte stream."""
        return hashlib.sha256(self.pixels).hexdigest()


def _paeth_predictor(a: int, b: int, c: int) -> int:
    """The PNG Paeth predictor (left, above, upper-left)."""
    p = a + b - c
    pa = abs(p - a)
    pb = abs(p - b)
    pc = abs(p - c)
    if pa <= pb and pa <= pc:
        return a
    if pb <= pc:
        return b
    return c


def _iter_png_chunks(data: bytes) -> List[Tuple[str, bytes]]:
    """Split a PNG byte stream into ``(type, payload)`` chunks, CRC-verified."""
    chunks: List[Tuple[str, bytes]] = []
    offset = len(PNG_SIGNATURE)
    total = len(data)
    seen_iend = False
    while offset < total:
        if offset + 8 > total:
            raise ComparatorError("Truncated PNG: incomplete chunk header.")
        (length,) = struct.unpack(">I", data[offset : offset + 4])
        raw_type = data[offset + 4 : offset + 8]
        try:
            chunk_type = raw_type.decode("ascii")
        except UnicodeDecodeError as exc:
            raise ComparatorError("Truncated PNG: non-ASCII chunk type.") from exc
        payload_start = offset + 8
        payload_end = payload_start + length
        if payload_end + 4 > total:
            raise ComparatorError(f"Truncated PNG: incomplete '{chunk_type}' chunk.")
        payload = data[payload_start:payload_end]
        (expected_crc,) = struct.unpack(">I", data[payload_end : payload_end + 4])
        actual_crc = zlib.crc32(raw_type + payload) & 0xFFFFFFFF
        if actual_crc != expected_crc:
            raise ComparatorError(f"PNG chunk '{chunk_type}' failed its CRC check.")
        chunks.append((chunk_type, payload))
        offset = payload_end + 4
        if chunk_type == "IEND":
            seen_iend = True
            break
    if not seen_iend:
        raise ComparatorError("Truncated PNG: no IEND chunk.")
    return chunks


def decode_png(data: bytes) -> DecodedImage:
    """Decode a PNG byte stream to straight RGBA using only the stdlib.

    Supported — and nothing else, every other mode is refused explicitly:
    8-bit depth, non-interlaced, colour types 0 (grey), 2 (truecolour),
    4 (grey+alpha) and 6 (truecolour+alpha), scanline filters 0..4 including
    Paeth reconstruction.
    """
    if not isinstance(data, (bytes, bytearray)):
        raise ComparatorError("PNG input must be bytes.")
    data = bytes(data)
    if not data.startswith(PNG_SIGNATURE):
        raise ComparatorError("Not a PNG: bad 8-byte signature.")

    chunks = _iter_png_chunks(data)
    if not chunks or chunks[0][0] != "IHDR":
        raise ComparatorError("Invalid PNG: first chunk is not IHDR.")
    if len(chunks[0][1]) != 13:
        raise ComparatorError("Invalid PNG: IHDR payload is not 13 bytes.")
    if sum(1 for name, _ in chunks if name == "IHDR") != 1:
        raise ComparatorError("Invalid PNG: more than one IHDR chunk.")

    width, height, bit_depth, color_type, compression, filter_method, interlace = (
        struct.unpack(">IIBBBBB", chunks[0][1])
    )
    if width == 0 or height == 0:
        raise ComparatorError(f"Unsupported PNG: zero dimension {width}x{height}.")
    if color_type not in PNG_COLOR_TYPE_CHANNELS:
        raise ComparatorError(
            f"Unsupported PNG colour type {color_type}; this decoder supports "
            f"{sorted(PNG_COLOR_TYPE_CHANNELS)} only."
        )
    if bit_depth != 8:
        raise ComparatorError(
            f"Unsupported PNG bit depth {bit_depth}; only 8 is supported."
        )
    if compression != 0:
        raise ComparatorError(f"Unsupported PNG compression method {compression}.")
    if filter_method != 0:
        raise ComparatorError(f"Unsupported PNG filter method {filter_method}.")
    if interlace != 0:
        raise ComparatorError(
            f"Unsupported PNG interlace method {interlace}; only non-interlaced "
            "(0) is supported."
        )

    idat = b"".join(payload for name, payload in chunks if name == "IDAT")
    if not idat:
        raise ComparatorError("Invalid PNG: no IDAT data.")
    try:
        raw = zlib.decompress(idat)
    except zlib.error as exc:
        raise ComparatorError(f"Invalid PNG: IDAT stream is not valid zlib: {exc}")

    channels = PNG_COLOR_TYPE_CHANNELS[color_type]
    stride = width * channels
    if len(raw) != height * (stride + 1):
        raise ComparatorError(
            "Invalid PNG: decompressed size "
            f"{len(raw)} does not match {height} scanlines of {stride + 1} bytes."
        )

    previous = bytearray(stride)
    scanlines: List[bytearray] = []
    position = 0
    for y in range(height):
        filter_type = raw[position]
        position += 1
        line = bytearray(raw[position : position + stride])
        position += stride
        if filter_type == 0:
            pass
        elif filter_type == 1:
            for i in range(channels, stride):
                line[i] = (line[i] + line[i - channels]) & 0xFF
        elif filter_type == 2:
            for i in range(stride):
                line[i] = (line[i] + previous[i]) & 0xFF
        elif filter_type == 3:
            for i in range(stride):
                left = line[i - channels] if i >= channels else 0
                line[i] = (line[i] + ((left + previous[i]) >> 1)) & 0xFF
        elif filter_type == 4:
            for i in range(stride):
                left = line[i - channels] if i >= channels else 0
                upper_left = previous[i - channels] if i >= channels else 0
                line[i] = (
                    line[i] + _paeth_predictor(left, previous[i], upper_left)
                ) & 0xFF
        else:
            raise ComparatorError(
                f"Unsupported PNG scanline filter {filter_type} on row {y}."
            )
        scanlines.append(line)
        previous = line

    out = bytearray(width * height * 4)
    cursor = 0
    for line in scanlines:
        if color_type == 6:
            out[cursor : cursor + stride] = line
            cursor += stride
            continue
        for x in range(width):
            base = x * channels
            if color_type == 0:
                grey = line[base]
                out[cursor] = grey
                out[cursor + 1] = grey
                out[cursor + 2] = grey
                out[cursor + 3] = 255
            elif color_type == 2:
                out[cursor] = line[base]
                out[cursor + 1] = line[base + 1]
                out[cursor + 2] = line[base + 2]
                out[cursor + 3] = 255
            else:  # color_type == 4 (grey + alpha)
                grey = line[base]
                out[cursor] = grey
                out[cursor + 1] = grey
                out[cursor + 2] = grey
                out[cursor + 3] = line[base + 1]
            cursor += 4

    return DecodedImage(width=width, height=height, pixels=bytes(out))


def decode_png_file(path: "os.PathLike[str] | str") -> DecodedImage:
    """Decode a PNG file, prefixing decode failures with the file path."""
    resolved = Path(path)
    try:
        data = resolved.read_bytes()
    except OSError as exc:
        raise ComparatorError(f"Cannot read PNG '{resolved}': {exc}")
    try:
        return decode_png(data)
    except ComparatorError as exc:
        raise ComparatorError(f"{resolved}: {exc}")


def sha256_file(path: "os.PathLike[str] | str") -> str:
    """SHA-256 of a file's raw bytes."""
    resolved = Path(path)
    digest = hashlib.sha256()
    try:
        with resolved.open("rb") as handle:
            for block in iter(lambda: handle.read(1 << 20), b""):
                digest.update(block)
    except OSError as exc:
        raise ComparatorError(f"Cannot hash '{resolved}': {exc}")
    return digest.hexdigest()


# ---------------------------------------------------------------------------
# Normalization.
# ---------------------------------------------------------------------------


@dataclass(frozen=True)
class NormalizationResult:
    """The normalized XD reference plus a record of what was done to it."""

    image: DecodedImage
    policy: str
    source_width: int
    source_height: int
    appended_row_count: int
    #: Rows dropped from the BOTTOM by `crop_top_to_812`, i.e. the artboard's
    #: below-the-fold content. Zero for every other policy.
    below_fold_row_count: int = 0

    def to_dict(self) -> Dict[str, Any]:
        return {
            "policy": self.policy,
            "source_width": self.source_width,
            "source_height": self.source_height,
            "normalized_width": self.image.width,
            "normalized_height": self.image.height,
            "appended_row_count": self.appended_row_count,
            "below_fold_row_count": self.below_fold_row_count,
            "scaled": False,
            "interpolated": False,
            "cropped": self.below_fold_row_count > 0,
            "translated": False,
            "color_adjusted": False,
            "normalized_rgba_sha256": self.image.sha256(),
        }


def normalize_reference(
    image: DecodedImage,
    *,
    policy: str,
    declared_width: int,
    declared_height: int,
    target_width: int = TARGET_WIDTH,
    target_height: int = TARGET_HEIGHT,
) -> NormalizationResult:
    """Bring a decoded XD reference onto the target surface.

    Exactly two policies exist. Neither scales, interpolates, crops, translates
    or colour-corrects. Any other shape mismatch is a structural failure.
    """
    if policy == NORMALIZATION_EXACT:
        if (declared_width, declared_height) != (target_width, target_height):
            raise ComparatorError(
                f"Normalization '{policy}' requires the mapping XD dimensions to "
                f"equal the target {target_width}x{target_height}, got "
                f"{declared_width}x{declared_height}."
            )
        if (image.width, image.height) != (target_width, target_height):
            raise ComparatorError(
                f"Normalization '{policy}' requires a decoded XD reference of "
                f"{target_width}x{target_height}, got {image.width}x{image.height}."
            )
        return NormalizationResult(
            image=image,
            policy=policy,
            source_width=image.width,
            source_height=image.height,
            appended_row_count=0,
        )

    if policy == NORMALIZATION_EXTEND_FINAL_ROW:
        _require_height_policy_target(policy, target_width, target_height)
        _require_declared_matches_decoded(policy, image, declared_width, declared_height)
        if declared_height >= target_height:
            raise ComparatorError(
                f"Normalization '{policy}' requires an XD height below the "
                f"target {target_height}, got {declared_height}. An artboard "
                f"at or above the target is '{NORMALIZATION_EXACT}' or "
                f"'{NORMALIZATION_CROP_TOP}'."
            )

        appended = target_height - image.height
        final_row = image.row(image.height - 1)
        extended = image.pixels + final_row * appended
        return NormalizationResult(
            image=DecodedImage(
                width=image.width,
                height=target_height,
                pixels=extended,
            ),
            policy=policy,
            source_width=image.width,
            source_height=image.height,
            appended_row_count=appended,
        )

    if policy == NORMALIZATION_CROP_TOP:
        _require_height_policy_target(policy, target_width, target_height)
        _require_declared_matches_decoded(policy, image, declared_width, declared_height)
        if declared_height <= target_height:
            raise ComparatorError(
                f"Normalization '{policy}' requires an XD height above the "
                f"target {target_height}, got {declared_height}. An artboard "
                f"at or below the target is '{NORMALIZATION_EXACT}' or "
                f"'{NORMALIZATION_EXTEND_FINAL_ROW}'."
            )

        # The first viewport, byte for byte. Rows below it are the artboard's
        # below-the-fold content: the screen has them, the user has not
        # scrolled to them, and this measurement is of the unscrolled state.
        kept = image.pixels[: target_height * image.stride]
        return NormalizationResult(
            image=DecodedImage(
                width=image.width,
                height=target_height,
                pixels=kept,
            ),
            policy=policy,
            source_width=image.width,
            source_height=image.height,
            appended_row_count=0,
            below_fold_row_count=image.height - target_height,
        )

    raise ComparatorError(
        f"Unsupported normalization policy '{policy}'; accepted policies are "
        f"{list(SUPPORTED_NORMALIZATIONS)}."
    )


def _require_height_policy_target(
    policy: str, target_width: int, target_height: int
) -> None:
    """Both height policies exist only for the canonical Merzox surface."""
    if (target_width, target_height) != (TARGET_WIDTH, TARGET_HEIGHT):
        raise ComparatorError(
            f"Normalization '{policy}' only targets "
            f"{TARGET_WIDTH}x{TARGET_HEIGHT}, got {target_width}x{target_height}."
        )


def _require_declared_matches_decoded(
    policy: str, image: "DecodedImage", declared_width: int, declared_height: int
) -> None:
    """The mapping's declared shape must be the shape that actually decoded.

    Checked before either height policy runs, so a mapping that quietly
    disagrees with its own artboard is a structural failure rather than a
    silently reshaped measurement.
    """
    if declared_width != NORMALIZATION_SOURCE_WIDTH:
        raise ComparatorError(
            f"Normalization '{policy}' requires an XD width of "
            f"{NORMALIZATION_SOURCE_WIDTH}, got {declared_width}."
        )
    if (image.width, image.height) != (declared_width, declared_height):
        raise ComparatorError(
            f"Normalization '{policy}' requires a decoded XD reference of "
            f"{declared_width}x{declared_height}, got "
            f"{image.width}x{image.height}."
        )


# ---------------------------------------------------------------------------
# Metrics — measurements only. No thresholds live here.
# ---------------------------------------------------------------------------


def coarse_luma(red: int, green: int, blue: int) -> int:
    """Integer-quantised BT.601 luma. Floor division is what makes it coarse."""
    weight_r, weight_g, weight_b = COARSE_LUMA_WEIGHTS
    return (
        weight_r * red + weight_g * green + weight_b * blue
    ) // COARSE_LUMA_DENOMINATOR


def compute_metrics(reference: DecodedImage, flutter: DecodedImage) -> Dict[str, Any]:
    """Measure two identically sized RGBA images.

    Colour-distance metrics use the RGB channels; ``exact_pixel_diff_ratio``
    uses complete RGBA equality. Every accumulator is an exact Python integer
    and each is divided exactly once at the end, so the result is independent
    of iteration order and reproducible on any host.
    """
    if (reference.width, reference.height) != (flutter.width, flutter.height):
        raise ComparatorError(
            "Cannot measure images of different sizes: reference is "
            f"{reference.width}x{reference.height}, Flutter golden is "
            f"{flutter.width}x{flutter.height}."
        )

    ref = reference.pixels
    flu = flutter.pixels
    pixel_count = reference.width * reference.height
    channel_count = pixel_count * 3

    abs_sum = 0
    square_sum = 0
    within_5 = 0
    within_10 = 0
    differing_pixels = 0
    luma_abs_sum = 0

    for i in range(0, len(ref), 4):
        r0, g0, b0, a0 = ref[i], ref[i + 1], ref[i + 2], ref[i + 3]
        r1, g1, b1, a1 = flu[i], flu[i + 1], flu[i + 2], flu[i + 3]

        dr = r0 - r1 if r0 >= r1 else r1 - r0
        dg = g0 - g1 if g0 >= g1 else g1 - g0
        db = b0 - b1 if b0 >= b1 else b1 - b0

        abs_sum += dr + dg + db
        square_sum += dr * dr + dg * dg + db * db

        if dr <= WITHIN_5_TOLERANCE:
            within_5 += 1
        if dg <= WITHIN_5_TOLERANCE:
            within_5 += 1
        if db <= WITHIN_5_TOLERANCE:
            within_5 += 1

        if dr <= WITHIN_10_TOLERANCE:
            within_10 += 1
        if dg <= WITHIN_10_TOLERANCE:
            within_10 += 1
        if db <= WITHIN_10_TOLERANCE:
            within_10 += 1

        if r0 != r1 or g0 != g1 or b0 != b1 or a0 != a1:
            differing_pixels += 1

        l0 = coarse_luma(r0, g0, b0)
        l1 = coarse_luma(r1, g1, b1)
        luma_abs_sum += l0 - l1 if l0 >= l1 else l1 - l0

    return {
        "width": reference.width,
        "height": reference.height,
        "pixel_count": pixel_count,
        "rgb_channel_count": channel_count,
        "differing_pixel_count": differing_pixels,
        "rgb_mae": abs_sum / channel_count,
        "rgb_rms": math.sqrt(square_sum / channel_count),
        "exact_pixel_diff_ratio": differing_pixels / pixel_count,
        "rgb_channels_within_5_ratio": within_5 / channel_count,
        "rgb_channels_within_10_ratio": within_10 / channel_count,
        "coarse_luma_mae": luma_abs_sum / pixel_count,
    }


# ---------------------------------------------------------------------------
# Mapping contract.
# ---------------------------------------------------------------------------


@dataclass(frozen=True)
class MappingEntry:
    """One locked XD↔Flutter seed mapping."""

    seed: str
    flutter_golden: str
    xd_name: str
    xd_manifest_id: str
    xd_artboard_path: str
    xd_width: int
    xd_height: int
    normalization: str
    semantic_reason: str


@dataclass(frozen=True)
class GoldenMapping:
    """The validated ``golden_mapping.json`` contract."""

    schema: str
    target_width: int
    target_height: int
    entries: Tuple[MappingEntry, ...]

    def seeds(self) -> Tuple[str, ...]:
        return tuple(entry.seed for entry in self.entries)


def _require_str(container: Mapping[str, Any], key: str, where: str) -> str:
    value = container.get(key)
    if not isinstance(value, str) or not value.strip():
        raise ComparatorError(f"{where}: '{key}' must be a non-empty string.")
    return value


def _require_int(container: Mapping[str, Any], key: str, where: str) -> int:
    value = container.get(key)
    if isinstance(value, bool) or not isinstance(value, int) or value <= 0:
        raise ComparatorError(f"{where}: '{key}' must be a positive integer.")
    return value


def resolve_repo_relative(relative: str, repo_root: Path) -> Path:
    """Resolve a repository-relative POSIX path, refusing any escape."""
    if not isinstance(relative, str) or not relative.strip():
        raise ComparatorError("Repository-relative path must be a non-empty string.")
    if "\\" in relative:
        raise ComparatorError(
            f"Repository-relative path '{relative}' must use '/' separators."
        )
    pure = PurePosixPath(relative)
    if pure.is_absolute():
        raise ComparatorError(
            f"Repository-relative path '{relative}' must not be absolute."
        )
    if any(part == ".." for part in pure.parts):
        raise ComparatorError(
            f"Repository-relative path '{relative}' escapes the repository root."
        )
    root = Path(os.path.normpath(str(Path(repo_root).absolute())))
    candidate = Path(os.path.normpath(str(root / pure)))
    try:
        candidate.relative_to(root)
    except ValueError:
        raise ComparatorError(
            f"Repository-relative path '{relative}' escapes the repository root."
        )
    return candidate


def validate_mapping(
    payload: Any, *, repo_root: "os.PathLike[str] | str" = REPO_ROOT
) -> GoldenMapping:
    """Validate the mapping document, fail-closed on every contract breach."""
    root = Path(repo_root)

    if not isinstance(payload, dict):
        raise ComparatorError("Mapping must be a JSON object.")

    schema = payload.get("schema")
    if schema != MAPPING_SCHEMA:
        raise ComparatorError(
            f"Mapping schema must be '{MAPPING_SCHEMA}', got {schema!r}."
        )

    surface = payload.get("target_surface")
    if not isinstance(surface, dict):
        raise ComparatorError("Mapping 'target_surface' must be an object.")
    target_width = _require_int(surface, "width", "Mapping target_surface")
    target_height = _require_int(surface, "height", "Mapping target_surface")
    if (target_width, target_height) != (TARGET_WIDTH, TARGET_HEIGHT):
        raise ComparatorError(
            f"Mapping target surface must be exactly {TARGET_WIDTH}x{TARGET_HEIGHT}, "
            f"got {target_width}x{target_height}."
        )

    raw_entries = payload.get("entries")
    if not isinstance(raw_entries, list):
        raise ComparatorError("Mapping 'entries' must be a list.")
    if len(raw_entries) < MINIMUM_MAPPING_ENTRIES:
        raise ComparatorError(
            f"Mapping must contain at least {MINIMUM_MAPPING_ENTRIES} entry, "
            f"got {len(raw_entries)}."
        )

    entries: List[MappingEntry] = []
    for index, raw in enumerate(raw_entries):
        where = f"Mapping entry #{index}"
        if not isinstance(raw, dict):
            raise ComparatorError(f"{where} must be an object.")
        for field in REQUIRED_ENTRY_FIELDS:
            if field not in raw:
                raise ComparatorError(f"{where}: required field '{field}' is missing.")

        seed = _require_str(raw, "seed", where)
        where = f"Mapping entry '{seed}'"
        flutter_golden = _require_str(raw, "flutter_golden", where)
        semantic_reason = _require_str(raw, "semantic_reason", where)
        normalization = _require_str(raw, "normalization", where)
        if normalization not in SUPPORTED_NORMALIZATIONS:
            raise ComparatorError(
                f"{where}: unsupported normalization policy '{normalization}'; "
                f"accepted policies are {list(SUPPORTED_NORMALIZATIONS)}."
            )

        xd = raw.get("xd")
        if not isinstance(xd, dict):
            raise ComparatorError(f"{where}: 'xd' must be an object.")
        for field in REQUIRED_XD_FIELDS:
            if field not in xd:
                raise ComparatorError(
                    f"{where}: required field 'xd.{field}' is missing."
                )
        xd_name = _require_str(xd, "name", f"{where} xd")
        xd_manifest_id = _require_str(xd, "manifest_id", f"{where} xd")
        xd_artboard_path = _require_str(xd, "artboard_path", f"{where} xd")
        xd_width = _require_int(xd, "width", f"{where} xd")
        xd_height = _require_int(xd, "height", f"{where} xd")

        if normalization == NORMALIZATION_EXACT and (xd_width, xd_height) != (
            target_width,
            target_height,
        ):
            raise ComparatorError(
                f"{where}: normalization '{NORMALIZATION_EXACT}' requires XD "
                f"dimensions {target_width}x{target_height}, got "
                f"{xd_width}x{xd_height}."
            )
        if normalization in (
            NORMALIZATION_EXTEND_FINAL_ROW,
            NORMALIZATION_CROP_TOP,
        ):
            if xd_width != NORMALIZATION_SOURCE_WIDTH:
                raise ComparatorError(
                    f"{where}: normalization '{normalization}' requires an XD "
                    f"width of {NORMALIZATION_SOURCE_WIDTH}, got {xd_width}."
                )
            if normalization == NORMALIZATION_EXTEND_FINAL_ROW:
                if not 0 < xd_height < target_height:
                    raise ComparatorError(
                        f"{where}: normalization "
                        f"'{NORMALIZATION_EXTEND_FINAL_ROW}' requires an XD "
                        f"height below {target_height}, got {xd_height}."
                    )
            elif xd_height <= target_height:
                raise ComparatorError(
                    f"{where}: normalization '{NORMALIZATION_CROP_TOP}' "
                    f"requires an XD height above {target_height}, got "
                    f"{xd_height}."
                )

        # Fail closed on a golden path that leaves the repository.
        resolve_repo_relative(flutter_golden, root)

        entries.append(
            MappingEntry(
                seed=seed,
                flutter_golden=flutter_golden,
                xd_name=xd_name,
                xd_manifest_id=xd_manifest_id,
                xd_artboard_path=xd_artboard_path,
                xd_width=xd_width,
                xd_height=xd_height,
                normalization=normalization,
                semantic_reason=semantic_reason,
            )
        )

    _reject_duplicates([e.seed for e in entries], "seed")
    _reject_duplicates([e.xd_manifest_id for e in entries], "XD manifest id")
    _reject_duplicates([e.xd_artboard_path for e in entries], "XD artboard path")

    for entry in entries:
        if not SEED_NAME_PATTERN.match(entry.seed):
            raise ComparatorError(
                f"Seed name '{entry.seed}' is malformed; a seed must match "
                f"{SEED_NAME_PATTERN.pattern}."
            )

    return GoldenMapping(
        schema=MAPPING_SCHEMA,
        target_width=target_width,
        target_height=target_height,
        entries=tuple(entries),
    )


def _reject_duplicates(values: Sequence[str], label: str) -> None:
    seen: Dict[str, int] = {}
    for value in values:
        seen[value] = seen.get(value, 0) + 1
    duplicates = sorted(value for value, count in seen.items() if count > 1)
    if duplicates:
        raise ComparatorError(f"Mapping contains duplicate {label}(s): {duplicates}.")


def load_mapping(
    path: "os.PathLike[str] | str | None" = None,
    *,
    repo_root: "os.PathLike[str] | str" = REPO_ROOT,
) -> GoldenMapping:
    """Read and validate the mapping document."""
    mapping_path = Path(path) if path is not None else DEFAULT_MAPPING_PATH
    if not mapping_path.is_file():
        raise ComparatorError(f"Mapping file not found: {mapping_path}")
    try:
        payload = json.loads(mapping_path.read_text(encoding="utf-8"))
    except (OSError, ValueError) as exc:
        raise ComparatorError(f"Cannot read mapping '{mapping_path}': {exc}")
    return validate_mapping(payload, repo_root=repo_root)


def select_entries(mapping: GoldenMapping, seed: str) -> List[MappingEntry]:
    """Resolve ``--seed`` to mapping entries, preserving mapping order."""
    if seed == SEED_ALL:
        return list(mapping.entries)
    for entry in mapping.entries:
        if entry.seed == seed:
            return [entry]
    raise ComparatorError(
        f"Unknown seed '{seed}'; accepted values are "
        f"{[SEED_ALL] + list(mapping.seeds())}."
    )


# ---------------------------------------------------------------------------
# Exporter integration.
# ---------------------------------------------------------------------------


def positive_counts(raw: Any, label: str) -> Dict[str, int]:
    """Keep only strictly positive integer counters, in sorted key order."""
    if not isinstance(raw, dict):
        raise ComparatorError(f"Exporter report '{label}' must be an object.")
    result: Dict[str, int] = {}
    for key in sorted(raw):
        value = raw[key]
        if isinstance(value, bool) or not isinstance(value, int):
            raise ComparatorError(
                f"Exporter report '{label}[{key}]' must be an integer."
            )
        if value > 0:
            result[str(key)] = value
    return result


def verify_manifest_identity(
    package: "xdref.XdPackage", entry: MappingEntry
) -> "xdref.ManifestArtboard":
    """Prove the locked manifest id resolves to the locked identity.

    Selection is **by manifest id only** — there is deliberately no display-name
    fallback, because the corpus contains colliding artboard names.
    """
    matches = [
        artboard
        for artboard in package.artboards()
        if artboard.manifest_id == entry.xd_manifest_id
    ]
    if not matches:
        raise ComparatorError(
            f"Seed '{entry.seed}': manifest id '{entry.xd_manifest_id}' is absent "
            "from the XD package."
        )
    if len(matches) > 1:
        raise ComparatorError(
            f"Seed '{entry.seed}': manifest id '{entry.xd_manifest_id}' resolves to "
            f"{len(matches)} artboards; it must be unique."
        )
    artboard = matches[0]
    if artboard.path != entry.xd_artboard_path:
        raise ComparatorError(
            f"Seed '{entry.seed}': manifest id '{entry.xd_manifest_id}' resolves to "
            f"artboard path '{artboard.path}' but the mapping locks "
            f"'{entry.xd_artboard_path}'."
        )
    if artboard.name != entry.xd_name:
        raise ComparatorError(
            f"Seed '{entry.seed}': manifest id '{entry.xd_manifest_id}' resolves to "
            f"artboard name '{artboard.name}' but the mapping locks "
            f"'{entry.xd_name}'."
        )
    actual = (int(artboard.width), int(artboard.height))
    if actual != (entry.xd_width, entry.xd_height):
        raise ComparatorError(
            f"Seed '{entry.seed}': manifest id '{entry.xd_manifest_id}' resolves to "
            f"{actual[0]}x{actual[1]} but the mapping locks "
            f"{entry.xd_width}x{entry.xd_height}."
        )
    return artboard


def verify_export_identity(report: Mapping[str, Any], entry: MappingEntry) -> None:
    """Fail closed if the exporter selected a different artboard identity."""
    pairs = (
        ("selected_artboard_id", entry.xd_manifest_id),
        ("selected_artboard_path", entry.xd_artboard_path),
        ("selected_artboard_name", entry.xd_name),
    )
    for field, expected in pairs:
        actual = report.get(field)
        if actual != expected:
            raise ComparatorError(
                f"Seed '{entry.seed}': the exporter report's '{field}' is "
                f"{actual!r} but the mapping locks {expected!r}."
            )


def exporter_summary(report: Mapping[str, Any], entry: MappingEntry) -> Dict[str, Any]:
    """Deterministic exporter provenance, fail-closed on unsupported nodes."""
    unsupported = positive_counts(
        report.get("unsupported_node_counts", {}), "unsupported_node_counts"
    )
    if unsupported:
        raise ComparatorError(
            f"Seed '{entry.seed}': the XD reference is visually incomplete — the "
            f"exporter reported unsupported nodes {unsupported}. A visually "
            "incomplete reference is never measured as if it were complete."
        )
    return {
        "iteration": report.get("iteration"),
        "schema": report.get("schema"),
        "handled_node_counts": positive_counts(
            report.get("handled_node_counts", {}), "handled_node_counts"
        ),
        "unsupported_node_counts": unsupported,
        "brand_normalization_enabled": bool(
            report.get("brand_normalization_enabled", False)
        ),
        "brand_replacement_count": report.get("brand_replacement_count"),
    }


def artifact_stem(entry: MappingEntry) -> str:
    """Deterministic artifact stem, e.g. ``splash.xd``."""
    return f"{entry.seed}.xd"


# ---------------------------------------------------------------------------
# Comparison.
# ---------------------------------------------------------------------------


def compare_entry(
    entry: MappingEntry,
    *,
    xd_path: Path,
    artifact_dir: Path,
    repo_root: Path,
    target_width: int = TARGET_WIDTH,
    target_height: int = TARGET_HEIGHT,
) -> Dict[str, Any]:
    """Measure one seed and return its deterministic result object."""
    golden_path = resolve_repo_relative(entry.flutter_golden, repo_root)
    if not golden_path.is_file():
        raise ComparatorError(
            f"Seed '{entry.seed}': Flutter golden not found at "
            f"'{entry.flutter_golden}' (resolved to {golden_path})."
        )

    flutter_image = decode_png_file(golden_path)
    if (flutter_image.width, flutter_image.height) != (target_width, target_height):
        raise ComparatorError(
            f"Seed '{entry.seed}': Flutter golden is "
            f"{flutter_image.width}x{flutter_image.height}, expected the target "
            f"surface {target_width}x{target_height}."
        )

    with xdref.XdPackage(xd_path) as package:
        verify_manifest_identity(package, entry)

    stem = artifact_stem(entry)
    svg_path = artifact_dir / f"{stem}.svg"
    png_path = artifact_dir / f"{stem}.png"
    report_path = artifact_dir / f"{stem}.report.json"

    result = xdref.export_artboard(
        xd_path,
        artboard_id=entry.xd_manifest_id,
        output_svg=svg_path,
        output_png=png_path,
        report_json=report_path,
        normalize_brand=True,
        render_png=True,
    )
    verify_export_identity(result.report, entry)
    exporter = exporter_summary(result.report, entry)

    if not png_path.is_file():
        raise ComparatorError(
            f"Seed '{entry.seed}': the exporter produced no PNG at {png_path}."
        )
    xd_png_sha = sha256_file(png_path)
    xd_image = decode_png_file(png_path)

    normalization = normalize_reference(
        xd_image,
        policy=entry.normalization,
        declared_width=entry.xd_width,
        declared_height=entry.xd_height,
        target_width=target_width,
        target_height=target_height,
    )
    metrics = compute_metrics(normalization.image, flutter_image)

    return {
        "seed": entry.seed,
        "flutter": {
            "golden_path": entry.flutter_golden,
            "width": flutter_image.width,
            "height": flutter_image.height,
            "file_sha256": sha256_file(golden_path),
        },
        "xd": {
            "artboard_name": entry.xd_name,
            "manifest_id": entry.xd_manifest_id,
            "artboard_path": entry.xd_artboard_path,
            "native_width": entry.xd_width,
            "native_height": entry.xd_height,
            "exported_width": xd_image.width,
            "exported_height": xd_image.height,
            "exported_png_sha256": xd_png_sha,
        },
        "normalization": normalization.to_dict(),
        "exporter": exporter,
        "metrics": metrics,
        "measurement_status": MEASUREMENT_STATUS_MEASURED,
        "semantic_reason": entry.semantic_reason,
    }


def build_report(results: Sequence[Mapping[str, Any]]) -> Dict[str, Any]:
    """Assemble the top-level report around already-measured results."""
    return {
        "schema": REPORT_SCHEMA,
        "mapping_schema": MAPPING_SCHEMA,
        "target_surface": {"width": TARGET_WIDTH, "height": TARGET_HEIGHT},
        "measurement_policy": dict(MEASUREMENT_POLICY),
        "results": [dict(result) for result in results],
    }


def serialize_report(report: Mapping[str, Any]) -> str:
    """Deterministic serialization: sorted keys, 2-space indent, one newline."""
    return json.dumps(report, ensure_ascii=False, sort_keys=True, indent=2) + "\n"


def run_comparison(
    *,
    xd_path: "os.PathLike[str] | str",
    seed: str,
    artifact_dir: "os.PathLike[str] | str",
    mapping_path: "os.PathLike[str] | str | None" = None,
    repo_root: "os.PathLike[str] | str" = REPO_ROOT,
) -> Dict[str, Any]:
    """Validate everything, measure the selected seeds, return the report."""
    root = Path(repo_root)
    mapping = load_mapping(mapping_path, repo_root=root)
    entries = select_entries(mapping, seed)

    package_path = Path(xd_path)
    if not package_path.is_file():
        raise ComparatorError(f"XD package not found: {package_path}")

    artifacts = Path(artifact_dir)
    try:
        artifacts.mkdir(parents=True, exist_ok=True)
    except OSError as exc:
        raise ComparatorError(f"Cannot create artifact directory '{artifacts}': {exc}")

    results = [
        compare_entry(
            entry,
            xd_path=package_path,
            artifact_dir=artifacts,
            repo_root=root,
            target_width=mapping.target_width,
            target_height=mapping.target_height,
        )
        for entry in entries
    ]
    return build_report(results)


# ---------------------------------------------------------------------------
# CLI.
# ---------------------------------------------------------------------------


def build_arg_parser() -> argparse.ArgumentParser:
    parser = argparse.ArgumentParser(
        prog="xd_flutter_comparator.py",
        description=(
            "Produce deterministic measurements between accepted Merzox Flutter "
            "seed goldens and their locked XD reference artboards. Metrics are "
            "diagnostic measurements only — no parity threshold exists."
        ),
    )
    parser.add_argument("--xd", required=True, help="Path to the design .xd package.")
    # Deliberately not `choices=`: the accepted set lives in the mapping file,
    # which is not read until after parsing. `select_entries` validates the
    # value against the loaded mapping and names every accepted seed on failure.
    parser.add_argument(
        "--seed",
        required=True,
        help=(
            "Seed to measure, or 'all' for every mapping entry in mapping "
            "order. Accepted values come from the mapping file."
        ),
    )
    parser.add_argument(
        "--output-json", required=True, help="Path of the deterministic report."
    )
    parser.add_argument(
        "--artifact-dir",
        required=True,
        help="Directory for the per-seed working SVG/PNG/report artifacts.",
    )
    parser.add_argument(
        "--mapping",
        default=None,
        help=f"Mapping document (default: {DEFAULT_MAPPING_PATH.name} beside this script).",
    )
    return parser


def main(argv: Optional[Sequence[str]] = None) -> int:
    xdref.force_utf8_streams()
    args = build_arg_parser().parse_args(argv)

    try:
        report = run_comparison(
            xd_path=args.xd,
            seed=args.seed,
            artifact_dir=args.artifact_dir,
            mapping_path=args.mapping,
        )
    except (ComparatorError, xdref.XdExportError) as exc:
        print(f"xd_flutter_comparator: {exc}", file=sys.stderr)
        return 2
    except OSError as exc:
        print(f"xd_flutter_comparator: {exc}", file=sys.stderr)
        return 2

    output_path = Path(args.output_json)
    if str(output_path.parent) not in ("", "."):
        output_path.parent.mkdir(parents=True, exist_ok=True)
    output_path.write_text(serialize_report(report), encoding="utf-8")

    for result in report["results"]:
        metrics = result["metrics"]
        print(
            f"{result['seed']}: measured  "
            f"rgb_mae={metrics['rgb_mae']:.6f}  "
            f"rgb_rms={metrics['rgb_rms']:.6f}  "
            f"exact_pixel_diff_ratio={metrics['exact_pixel_diff_ratio']:.6f}"
        )
    print(f"Report written to {output_path}")
    return 0


if __name__ == "__main__":  # pragma: no cover - CLI entry point
    raise SystemExit(main())

#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""Merzox XD reference exporter (iteration I2-R2).

Reads an Adobe XD ``.xd`` package directly as a ZIP archive, selects a single
artboard by its exact canonical manifest name, and exports it as:

    AGC  ->  self-contained SVG  ->  PNG (installed Edge/Chrome, headless)

This is an *engineering reference* exporter. It is not Adobe XD and it makes no
pixel-perfect claim. Every approximation it makes is recorded in the JSON
report instead of being silently applied.

Only the Python standard library is required.
"""

from __future__ import annotations

import argparse
import base64
import json
import math
import os
import re
import shutil
import subprocess
import sys
import tempfile
import zipfile
from collections import OrderedDict
from dataclasses import dataclass, field
from pathlib import Path
from typing import Any, Dict, List, Optional, Sequence, Tuple

# ---------------------------------------------------------------------------
# Exporter identity.
# ---------------------------------------------------------------------------

#: The calibration iteration this exporter currently implements. Every report it
#: stamps must carry this value; update it whenever a calibrated iteration lands.
EXPORTER_ITERATION = "MERZOX-UI-GOLDEN-I3-R2-D7-I1"

#: Serialization/schema version of the single-artboard JSON report. Deliberately
#: independent of EXPORTER_ITERATION: the field set only changes when the schema
#: changes, so a new calibration iteration does NOT bump this.
REPORT_SCHEMA = "merzox.xd_reference_exporter/1"

#: Serialization/schema version of the all-artboard batch summary. Independent of
#: both the exporter iteration and the single-artboard report schema.
BATCH_REPORT_SCHEMA = "merzox.xd_reference_batch/1"

#: Filename of the deterministic batch summary written into --output-dir.
BATCH_REPORT_FILENAME = "batch-report.json"

#: The only two batch-entry status values. "success" means artifact generation
#: succeeded - it says nothing about rendering fidelity; unsupported renderer
#: features are reported separately via unsupported_node_counts.
BATCH_STATUS_SUCCESS = "success"
BATCH_STATUS_FAILED = "failed"

#: Fallback slug for an artboard whose name contains no slug-able characters.
ARTBOARD_SLUG_FALLBACK = "artboard"

#: Number of leading manifest-id characters used to disambiguate output stems.
ARTBOARD_STEM_ID_LENGTH = 8

#: Canonical suffix of an artboard's AGC file, used to reject AGC paths where a
#: canonical artwork directory path is required.
AGC_PATH_SUFFIX = "/graphics/graphicContent.agc"

#: SVG geometry tags whose closure is guaranteed, so they may act as their own
#: interior clip region when emulating XD inside-stroke alignment. A path counts
#: only when it ends in an explicit closepath; `line` is never eligible.
INSIDE_STROKE_CLOSED_TAGS = frozenset({"rect", "circle", "ellipse", "polygon"})

#: XD inside-stroke emulation renders a centred stroke at this multiple of the
#: declared width and clips away the outward half.
INSIDE_STROKE_WIDTH_MULTIPLIER = 2

#: Physical corner order of a compact AGC rectangle's four-value ``shape.r``
#: list. Proven against the corpus: index 0 is the top-left corner and the list
#: runs clockwise from there.
#:
#:     r[0] = top-left
#:     r[1] = top-right
#:     r[2] = bottom-right
#:     r[3] = bottom-left
#:
#: Every helper below consumes and produces radii in exactly this order.
AGC_CORNER_ORDER = ("top-left", "top-right", "bottom-right", "bottom-left")

#: Reporting key for a rectangle whose four corner radii are not all equal and
#: which is therefore emitted as an exact deterministic SVG path.
RECT_NON_UNIFORM_RADIUS_KEY = "rect:non-uniform-corner-radius"

#: Reporting key for a non-uniform rectangle whose declared radii overflowed a
#: side and were reduced by the proportional-overlap policy below.
RECT_RADIUS_OVERLAP_SCALED_KEY = "rect:corner-radius-overlap-scaled"

#: Reporting key for an image fill laid out against local bounds derived from a
#: path's own ``d`` by :func:`strict_absolute_mlc_z_bounds`, because the stored
#: geometry carried no reliable bounds. Counted in ``handled_node_counts``.
PATTERN_DERIVED_PATH_BOUNDS_KEY = "fill:pattern:path-bounds-derived"

# ---------------------------------------------------------------------------
# Deterministic, documented approximation constants.
# ---------------------------------------------------------------------------

#: XD ``uxdesign#blur`` ``blurAmount`` -> SVG ``feGaussianBlur/@stdDeviation``.
#: XD expresses blur as an artist-facing 0..50 "amount"; SVG expresses it as a
#: Gaussian standard deviation. The mapping below is a deterministic linear
#: approximation, NOT an exact reproduction of XD's own blur kernel.
BLUR_AMOUNT_TO_STD_DEVIATION = 0.5

#: XD drop shadow ``r`` (blur radius) -> SVG ``feDropShadow/@stdDeviation``.
SHADOW_RADIUS_TO_STD_DEVIATION = 0.5

#: Adobe XD image-fill "cover" semantics: preserve the bitmap aspect ratio,
#: scale until the shape is fully covered, crop the overflow.
COVER_PRESERVE_ASPECT_RATIO = "xMidYMid slice"

#: XD "stretch" semantics: distort the bitmap onto the shape bounds exactly.
STRETCH_PRESERVE_ASPECT_RATIO = "none"

#: Scale-behavior spellings XD is known to use, normalised to alphanumerics.
SCALE_BEHAVIOR_COVER_TOKENS = frozenset({"fill", "cover", "scalecover", "scalefill"})
SCALE_BEHAVIOR_STRETCH_TOKENS = frozenset({"stretch", "scalestretch"})

#: Reported scale-behavior key used when XD declares none at all.
SCALE_BEHAVIOR_UNSPECIFIED = "unspecified"

#: Blend modes that mean "no blending" and must NOT be reported as unsupported.
NEUTRAL_BLEND_MODES = frozenset({"normal", "source-over", "sourceover"})

#: The ONLY blend mode calibrated against the authentic XD preview (I2-D3).
#: Every other non-neutral mode stays unsupported; this is not generalised.
CALIBRATED_BLEND_MODE = "soft-light"

#: Strategy labels used in ``blend_mode_application_counts``.
BLEND_STRATEGY_SAFE_OPACITY_GROUP = "safe-opacity-group"
BLEND_STRATEGY_UNSUPPORTED = "unsupported"

#: Literal legacy brand token replaced when brand normalization is supplied.
BRAND_SOURCE_TOKEN = "Bictov"

#: Some XD artboards store the legacy logo as a vector brand mark followed by
#: this exact text tail. Only a complete text chunk equal to this token is
#: normalized; ordinary text merely containing the substring is untouched.
BRAND_SEGMENTED_SOURCE_TOKEN = "ictove"

BRAND_TARGET_TOKEN = "Merzox"

#: Font families we ship inside the SVG as data URIs.
TAJAWAL_ALIASES = (
    "Tajawal",
    "Tajawal-Regular",
    "Tajawal-Medium",
    "Tajawal-Bold",
    "Tajawal-Light",
)

#: XD font style name -> CSS font-weight used when we synthesise a weight.
FONT_WEIGHT_BY_STYLE_NAME = OrderedDict(
    (
        ("thin", 100),
        ("extralight", 200),
        ("ultralight", 200),
        ("light", 300),
        ("regular", 400),
        ("normal", 400),
        ("book", 400),
        ("medium", 500),
        ("semibold", 600),
        ("demibold", 600),
        ("extrabold", 800),
        ("ultrabold", 800),
        ("bold", 700),
        ("black", 900),
        ("heavy", 900),
    )
)

DEFAULT_FONT_RELATIVE_PATH = Path("assets") / "fonts" / "Tajawal-Regular.ttf"


class XdExportError(RuntimeError):
    """Raised for user-facing, non-recoverable export failures."""


# ---------------------------------------------------------------------------
# Small formatting helpers.
# ---------------------------------------------------------------------------


def fmt_num(value: Any, default: float = 0.0) -> str:
    """Format a number deterministically (no locale, no float noise)."""
    try:
        number = float(value)
    except (TypeError, ValueError):
        number = float(default)
    if number != number or number in (float("inf"), float("-inf")):
        number = float(default)
    if abs(number) < 1e15 and float(int(number)) == number:
        return str(int(number))
    text = f"{number:.6f}".rstrip("0").rstrip(".")
    return text or "0"


def to_float(value: Any, default: float = 0.0) -> float:
    try:
        return float(value)
    except (TypeError, ValueError):
        return float(default)


def xml_escape(text: Any, attribute: bool = False) -> str:
    out = str(text).replace("&", "&amp;").replace("<", "&lt;").replace(">", "&gt;")
    if attribute:
        out = out.replace('"', "&quot;").replace("'", "&apos;")
    return out


def attrs_to_string(attrs: "OrderedDict[str, Any]") -> str:
    parts = []
    for key, value in attrs.items():
        if value is None:
            continue
        parts.append(f'{key}="{xml_escape(value, attribute=True)}"')
    return " ".join(parts)


def clamp01(value: float) -> float:
    return max(0.0, min(1.0, value))


# ---------------------------------------------------------------------------
# Non-uniform rounded-rectangle geometry.
#
# Radii are always handled as the proven AGC tuple (tl, tr, br, bl); see
# AGC_CORNER_ORDER.
# ---------------------------------------------------------------------------


def scale_corner_radii(
    width: Any, height: Any, radii: Sequence[Any]
) -> Tuple[Tuple[float, float, float, float], float]:
    """Apply the renderer's deterministic proportional-overlap policy.

    Two radii sharing a side may together demand more than that side's length.
    The policy - the same one CSS ``border-radius`` and Canvas ``roundRect``
    specify - computes one common factor from the most-violated side and scales
    ALL FOUR radii by it, so the shape's corner proportions are preserved::

        factor = min(1, w/(tl+tr), h/(tr+br), w/(bl+br), h/(tl+bl))

    Corners are never clamped independently. This is the exporter's documented
    overlap policy; it is NOT a claim of parity with Adobe's undocumented
    internal Scenegraph capping algorithm.

    Returns ``((tl, tr, br, bl), factor)``; ``factor`` is exactly ``1.0`` when
    nothing overlapped and the radii are returned numerically unchanged.
    """
    values = list(radii) + [0.0] * 4
    tl, tr, br, bl = (max(0.0, to_float(v)) for v in values[:4])
    w = max(0.0, to_float(width))
    h = max(0.0, to_float(height))

    factor = 1.0
    for span, total in (
        (w, tl + tr),  # top
        (h, tr + br),  # right
        (w, bl + br),  # bottom
        (h, tl + bl),  # left
    ):
        if total > 0.0:
            factor = min(factor, span / total)

    if factor >= 1.0:
        return (tl, tr, br, bl), 1.0
    return (tl * factor, tr * factor, br * factor, bl * factor), factor


def rounded_rect_path_data(
    x: Any, y: Any, width: Any, height: Any, radii: Sequence[float]
) -> str:
    """Build the closed clockwise path of a rectangle with four corner radii.

    ``radii`` must already have passed through :func:`scale_corner_radii`. The
    path starts at the end of the top-left corner and runs TL -> TR -> BR -> BL,
    using a quarter-circle arc for every non-zero corner and a plain straight
    endpoint for every zero corner, so the output is byte-deterministic.
    """
    tl, tr, br, bl = (to_float(v) for v in list(radii)[:4])
    x = to_float(x)
    y = to_float(y)
    w = to_float(width)
    h = to_float(height)

    def arc(radius: float, end_x: float, end_y: float) -> str:
        # Quarter circle, clockwise (sweep-flag 1), always the short arc.
        return (
            f"A {fmt_num(radius)},{fmt_num(radius)} 0 0 1 "
            f"{fmt_num(end_x)},{fmt_num(end_y)}"
        )

    commands = [f"M {fmt_num(x + tl)},{fmt_num(y)}"]
    commands.append(f"L {fmt_num(x + w - tr)},{fmt_num(y)}")
    if tr > 0.0:
        commands.append(arc(tr, x + w, y + tr))
    commands.append(f"L {fmt_num(x + w)},{fmt_num(y + h - br)}")
    if br > 0.0:
        commands.append(arc(br, x + w - br, y + h))
    commands.append(f"L {fmt_num(x + bl)},{fmt_num(y + h)}")
    if bl > 0.0:
        commands.append(arc(bl, x, y + h - bl))
    commands.append(f"L {fmt_num(x)},{fmt_num(y + tl)}")
    if tl > 0.0:
        commands.append(arc(tl, x + tl, y))
    commands.append("Z")
    return " ".join(commands)


# ---------------------------------------------------------------------------
# Strict local path bounds (D7-I1).
#
# A deliberately tiny, fail-closed reader for ONE explicitly supported path
# subset. It exists only so an image fill on a closed absolute M/L/C/Z path can
# be laid out against real geometry instead of the natural-bitmap fallback. It
# is NOT a general SVG path library and must never grow into one: anything it
# does not recognise returns None and the caller keeps its documented fallback.
# ---------------------------------------------------------------------------

#: The complete set of commands this reader accepts, mapped to their exact
#: argument count. Absolute/uppercase only - no relative forms, no H/V/S/Q/T/A.
STRICT_PATH_COMMAND_ARITY = OrderedDict([("M", 2), ("L", 2), ("C", 6), ("Z", 0)])

#: The only characters permitted *between* tokens. Anything else is a parse
#: failure rather than something to skip, so a stray character cannot be
#: silently ignored the way a loose ``re.findall()`` would ignore it.
STRICT_PATH_SEPARATORS = frozenset(" \t\r\n\f\v,")

#: A single SVG number. Deliberately explicit: no bare ``.``, no ``nan``/``inf``
#: spellings (those are letters and are rejected as stray characters), and an
#: exponent must carry at least one digit.
_STRICT_PATH_NUMBER = re.compile(
    r"[-+]?(?:[0-9]+\.[0-9]*|\.[0-9]+|[0-9]+)(?:[eE][-+]?[0-9]+)?"
)


def _cubic_axis_extrema(
    p0: float, p1: float, p2: float, p3: float
) -> Tuple[float, float]:
    """Exact ``(min, max)`` of one coordinate of a cubic Bezier segment.

    The segment's derivative is the quadratic ``a t^2 + b t + c`` (up to the
    constant factor 3) with::

        a = -p0 + 3 p1 - 3 p2 + p3
        b = 2 (p0 - 2 p1 + p2)
        c = p1 - p0

    Both endpoints plus every derivative root strictly inside ``0 < t < 1`` are
    evaluated. The control points themselves are never used as bounds and the
    curve is never sampled.
    """
    low = min(p0, p3)
    high = max(p0, p3)

    a = -p0 + 3.0 * p1 - 3.0 * p2 + p3
    b = 2.0 * (p0 - 2.0 * p1 + p2)
    c = p1 - p0

    roots: List[float] = []
    if a == 0.0:
        if b != 0.0:
            roots.append(-c / b)
    else:
        discriminant = b * b - 4.0 * a * c
        if discriminant >= 0.0:
            root = math.sqrt(discriminant)
            roots.append((-b + root) / (2.0 * a))
            roots.append((-b - root) / (2.0 * a))

    for t in roots:
        if not math.isfinite(t) or not (0.0 < t < 1.0):
            continue
        s = 1.0 - t
        value = (
            s * s * s * p0
            + 3.0 * s * s * t * p1
            + 3.0 * s * t * t * p2
            + t * t * t * p3
        )
        if not math.isfinite(value):
            continue
        low = min(low, value)
        high = max(high, value)
    return low, high


def _strict_path_commands(text: str) -> Optional[List[Tuple[str, List[float]]]]:
    """Tokenise the WHOLE string, or fail.

    Every command letter must appear explicitly and be followed by exactly its
    own argument count. Implicit repetition (``M 0 0 10 10``), missing or excess
    arguments, unknown letters and stray characters are all rejected.
    """
    length = len(text)
    index = 0

    def skip_separators(position: int) -> int:
        while position < length and text[position] in STRICT_PATH_SEPARATORS:
            position += 1
        return position

    commands: List[Tuple[str, List[float]]] = []
    index = skip_separators(index)
    while index < length:
        letter = text[index]
        arity = STRICT_PATH_COMMAND_ARITY.get(letter)
        if arity is None:
            # Lowercase/relative forms, H/V/S/Q/T/A, and any stray character all
            # land here. Nothing is skipped and nothing is guessed.
            return None
        index += 1

        arguments: List[float] = []
        for _ in range(arity):
            index = skip_separators(index)
            match = _STRICT_PATH_NUMBER.match(text, index)
            if match is None:
                return None
            try:
                value = float(match.group(0))
            except ValueError:  # pragma: no cover - the regex already guarantees it
                return None
            if not math.isfinite(value):
                return None
            arguments.append(value)
            index = match.end()

        commands.append((letter, arguments))
        index = skip_separators(index)

    return commands


def strict_absolute_mlc_z_bounds(
    path_data: Any,
) -> Optional[Tuple[float, float, float, float]]:
    """Exact local bounds of a closed absolute ``M``/``L``/``C``/``Z`` path.

    Returns ``(x, y, width, height)`` for the explicitly supported subset, or
    ``None`` for **everything** else - lowercase/relative commands, ``H``,
    ``V``, ``S``, ``Q``, ``T``, ``A``, implicit command repetition, wrong
    argument counts, stray characters, non-finite numbers, an unclosed subpath,
    an empty path, or bounds with a non-positive width or height.

    Cubic extrema are solved analytically (see :func:`_cubic_axis_extrema`); the
    curve is never sampled and control points are never used as a bounding box.
    """
    if not isinstance(path_data, str):
        return None
    commands = _strict_path_commands(path_data)
    if not commands:
        return None

    min_x = min_y = float("inf")
    max_x = max_y = float("-inf")

    def include(x: float, y: float) -> None:
        nonlocal min_x, min_y, max_x, max_y
        min_x = min(min_x, x)
        max_x = max(max_x, x)
        min_y = min(min_y, y)
        max_y = max(max_y, y)

    current: Optional[Tuple[float, float]] = None
    subpath_start: Optional[Tuple[float, float]] = None
    closed_subpaths = 0

    for letter, arguments in commands:
        if letter == "M":
            # A previous subpath must already be closed: this fallback exists
            # only for closed fill geometry, so an open one fails closed.
            if subpath_start is not None:
                return None
            current = (arguments[0], arguments[1])
            subpath_start = current
            include(*current)
        elif letter == "L":
            if current is None or subpath_start is None:
                return None
            current = (arguments[0], arguments[1])
            include(*current)
        elif letter == "C":
            if current is None or subpath_start is None:
                return None
            x0, y0 = current
            x1, y1, x2, y2, x3, y3 = arguments
            low_x, high_x = _cubic_axis_extrema(x0, x1, x2, x3)
            low_y, high_y = _cubic_axis_extrema(y0, y1, y2, y3)
            include(low_x, low_y)
            include(high_x, high_y)
            current = (x3, y3)
        else:  # "Z"
            if current is None or subpath_start is None:
                return None
            # The closing line adds no new extremum: both of its endpoints are
            # already included. Only the subpath state changes.
            current = subpath_start
            subpath_start = None
            closed_subpaths += 1

    if subpath_start is not None or closed_subpaths == 0:
        return None
    if not (
        math.isfinite(min_x)
        and math.isfinite(min_y)
        and math.isfinite(max_x)
        and math.isfinite(max_y)
    ):
        return None

    width = max_x - min_x
    height = max_y - min_y
    if width <= 0.0 or height <= 0.0:
        return None
    return min_x, min_y, width, height


def color_to_css(color: Any) -> Tuple[Optional[str], float]:
    """Normalise an AGC colour object to ``(#rrggbb, alpha)``.

    Handles ``{"mode": "RGB", "value": {...}, "alpha": a}``, bare
    ``{"r":..,"g":..,"b":..}`` and plain CSS strings.
    """
    if color is None:
        return None, 1.0
    if isinstance(color, str):
        return color, 1.0
    if not isinstance(color, dict):
        return None, 1.0

    alpha = clamp01(to_float(color.get("alpha", color.get("a", 1.0)), 1.0))

    value = color.get("value")
    if not isinstance(value, dict):
        value = color

    if isinstance(value.get("hex"), str):
        return value["hex"], alpha

    red = int(round(clamp01(to_float(value.get("r"), 0.0) / 255.0) * 255))
    green = int(round(clamp01(to_float(value.get("g"), 0.0) / 255.0) * 255))
    blue = int(round(clamp01(to_float(value.get("b"), 0.0) / 255.0) * 255))
    return f"#{red:02x}{green:02x}{blue:02x}", alpha


def guess_image_mime(data: bytes) -> str:
    if data.startswith(b"\x89PNG\r\n\x1a\n"):
        return "image/png"
    if data.startswith(b"\xff\xd8\xff"):
        return "image/jpeg"
    if data.startswith(b"GIF87a") or data.startswith(b"GIF89a"):
        return "image/gif"
    if data.startswith(b"RIFF") and data[8:12] == b"WEBP":
        return "image/webp"
    if data.startswith(b"BM"):
        return "image/bmp"
    stripped = data.lstrip()[:256]
    if stripped.startswith(b"<?xml") or stripped.startswith(b"<svg"):
        return "image/svg+xml"
    return "image/png"


def bytes_to_data_uri(data: bytes, mime: Optional[str] = None) -> str:
    mime = mime or guess_image_mime(data)
    return f"data:{mime};base64,{base64.b64encode(data).decode('ascii')}"


def normalize_scale_behavior_token(value: Any) -> str:
    """Reduce a scaleBehavior spelling to bare lowercase alphanumerics."""
    return "".join(ch for ch in str(value).lower() if ch.isalnum())


def classify_scale_behavior(value: Any) -> Tuple[str, str]:
    """Map an XD ``scaleBehavior`` to ``(mode, reported_key)``.

    ``mode`` is one of ``"cover"``, ``"stretch"`` or ``"unknown"``. The reported
    key is the raw XD spelling (or ``"unspecified"``) so the report stays
    faithful to the source file rather than to our normalisation.
    """
    if value is None or (isinstance(value, str) and not value.strip()):
        # Adobe image fills default to cover; nothing is being guessed here.
        return "cover", SCALE_BEHAVIOR_UNSPECIFIED
    reported = str(value).strip()
    token = normalize_scale_behavior_token(reported)
    if token in SCALE_BEHAVIOR_COVER_TOKENS:
        return "cover", reported
    if token in SCALE_BEHAVIOR_STRETCH_TOKENS:
        return "stretch", reported
    return "unknown", reported


def normalize_blend_mode(value: Any) -> Optional[str]:
    """Return a non-neutral blend mode verbatim, or ``None`` if it is neutral."""
    if not isinstance(value, str):
        return None
    token = value.strip()
    if not token:
        return None
    if token.lower().replace("_", "-") in NEUTRAL_BLEND_MODES:
        return None
    if token.lower().replace("-", "") in NEUTRAL_BLEND_MODES:
        return None
    return token


def extract_blend_mode(node: Dict[str, Any]) -> Optional[str]:
    """Read a node's non-neutral blend mode, or ``None`` if it has none."""
    style = node.get("style") if isinstance(node.get("style"), dict) else {}
    raw = style.get("blendMode")
    if raw is None:
        raw = node.get("blendMode")
    if raw is None:
        ux = (node.get("meta") or {}).get("ux") or {}
        if isinstance(ux, dict):
            raw = ux.get("blendMode")
    return normalize_blend_mode(raw)


def node_opacity(node: Dict[str, Any]) -> Optional[float]:
    """Return a node's explicitly declared style opacity, if any."""
    style = node.get("style") if isinstance(node.get("style"), dict) else {}
    if "opacity" not in style:
        return None
    return to_float(style.get("opacity"), 1.0)


def explicit_group_opacity(node: Dict[str, Any]) -> Optional[float]:
    """Opacity of a *group* that is explicitly and strictly between 0 and 1."""
    if node.get("type") != "group" and not isinstance(node.get("group"), dict):
        return None
    value = node_opacity(node)
    if value is None or not (0.0 < value < 1.0):
        return None
    return value


def font_weight_for_style_name(style_name: Optional[str]) -> int:
    if not style_name:
        return 400
    normalised = str(style_name).replace(" ", "").replace("-", "").lower()
    for token, weight in FONT_WEIGHT_BY_STYLE_NAME.items():
        if token in normalised:
            return weight
    return 400


# ---------------------------------------------------------------------------
# Reporting.
# ---------------------------------------------------------------------------


class ExportReport:
    """Machine readable record of what was rendered and what was approximated."""

    def __init__(self) -> None:
        self.source_xd: Optional[str] = None
        self.selected_artboard_name: Optional[str] = None
        self.selected_artboard_path: Optional[str] = None
        self.selected_artboard_id: Optional[str] = None
        self.artboard_bounds: Dict[str, float] = {}
        self.svg_width: float = 0.0
        self.svg_height: float = 0.0
        self.viewbox: Optional[str] = None
        self.viewbox_origin_source: Optional[str] = None
        self.browser_path: Optional[str] = None
        self.browser_return_code: Optional[int] = None
        self.output_svg: Optional[str] = None
        self.output_png: Optional[str] = None

        self.node_type_counts: Dict[str, int] = {}
        self.handled_node_counts: Dict[str, int] = {}
        self.unsupported_node_counts: Dict[str, int] = {}

        self.unresolved_sync_refs: int = 0
        self.resolved_sync_refs: int = 0
        self.pattern_fill_count: int = 0
        self.resolved_pattern_fill_count: int = 0
        self.unresolved_pattern_fill_count: int = 0
        self.resource_ids_used: List[str] = []
        self.pattern_scale_behavior_counts: Dict[str, int] = {}
        self.pattern_fills: List[Dict[str, Any]] = []
        self.blend_mode_counts: Dict[str, int] = {}
        self.blend_mode_application_counts: Dict[str, int] = {}
        self.blend_mode_applications: List[Dict[str, Any]] = []
        self.gradient_fill_count: int = 0
        self.text_node_count: int = 0
        self.invisible_node_count: int = 0

        self.fonts_requested: List[str] = []
        self.embedded_fonts: List[str] = []
        self.non_embedded_fonts: List[str] = []
        self.synthetic_tajawal_weight_limitation: bool = True

        self.visible_drop_shadow_count: int = 0
        self.visible_blur_count: int = 0
        self.hidden_blur_count: int = 0
        self.unsupported_background_blur_count: int = 0
        self.clip_path_count: int = 0

        self.brand_normalization_enabled: bool = False
        self.brand_replacement_count: int = 0

        self.warnings: List[str] = []
        self.limitations: List[str] = []

    # -- counters ---------------------------------------------------------
    def count_node_type(self, node_type: str) -> None:
        self.node_type_counts[node_type] = self.node_type_counts.get(node_type, 0) + 1

    def count_handled(self, key: str) -> None:
        self.handled_node_counts[key] = self.handled_node_counts.get(key, 0) + 1

    def count_unsupported(self, key: str, warning: Optional[str] = None) -> None:
        self.unsupported_node_counts[key] = self.unsupported_node_counts.get(key, 0) + 1
        if warning:
            self.warn(warning)

    def warn(self, message: str) -> None:
        if message not in self.warnings:
            self.warnings.append(message)

    def note_limitation(self, message: str) -> None:
        if message not in self.limitations:
            self.limitations.append(message)

    def note_resource(self, resource_id: str) -> None:
        if resource_id and resource_id not in self.resource_ids_used:
            self.resource_ids_used.append(resource_id)

    def note_font_request(self, family: str) -> None:
        if family and family not in self.fonts_requested:
            self.fonts_requested.append(family)

    def count_scale_behavior(self, key: str) -> None:
        self.pattern_scale_behavior_counts[key] = (
            self.pattern_scale_behavior_counts.get(key, 0) + 1
        )

    def count_blend_mode(self, value: str) -> None:
        self.blend_mode_counts[value] = self.blend_mode_counts.get(value, 0) + 1

    def count_blend_application(self, key: str) -> None:
        self.blend_mode_application_counts[key] = (
            self.blend_mode_application_counts.get(key, 0) + 1
        )

    def note_blend_application(self, details: Dict[str, Any]) -> None:
        self.blend_mode_applications.append(details)

    def note_pattern_fill(self, details: Dict[str, Any]) -> None:
        self.pattern_fills.append(details)

    # -- serialisation ----------------------------------------------------
    def to_dict(self) -> Dict[str, Any]:
        return OrderedDict(
            [
                ("schema", REPORT_SCHEMA),
                ("iteration", EXPORTER_ITERATION),
                ("source_xd", self.source_xd),
                ("selected_artboard_name", self.selected_artboard_name),
                ("selected_artboard_path", self.selected_artboard_path),
                ("selected_artboard_id", self.selected_artboard_id),
                ("artboard_bounds", self.artboard_bounds),
                ("svg_width", self.svg_width),
                ("svg_height", self.svg_height),
                ("viewbox", self.viewbox),
                ("viewbox_origin_source", self.viewbox_origin_source),
                ("output_svg", self.output_svg),
                ("output_png", self.output_png),
                ("browser_path", self.browser_path),
                ("browser_return_code", self.browser_return_code),
                ("node_type_counts", dict(sorted(self.node_type_counts.items()))),
                ("handled_node_counts", dict(sorted(self.handled_node_counts.items()))),
                (
                    "unsupported_node_counts",
                    dict(sorted(self.unsupported_node_counts.items())),
                ),
                ("resolved_sync_refs", self.resolved_sync_refs),
                ("unresolved_sync_refs", self.unresolved_sync_refs),
                ("pattern_fill_count", self.pattern_fill_count),
                ("resolved_pattern_fill_count", self.resolved_pattern_fill_count),
                ("unresolved_pattern_fill_count", self.unresolved_pattern_fill_count),
                (
                    "pattern_scale_behavior_counts",
                    dict(sorted(self.pattern_scale_behavior_counts.items())),
                ),
                ("pattern_fills", list(self.pattern_fills)),
                ("gradient_fill_count", self.gradient_fill_count),
                ("resource_ids_used", sorted(self.resource_ids_used)),
                ("blend_mode_counts", dict(sorted(self.blend_mode_counts.items()))),
                (
                    "blend_mode_application_counts",
                    dict(sorted(self.blend_mode_application_counts.items())),
                ),
                ("blend_mode_applications", list(self.blend_mode_applications)),
                ("text_node_count", self.text_node_count),
                ("invisible_node_count", self.invisible_node_count),
                ("fonts_requested", sorted(self.fonts_requested)),
                ("embedded_fonts", list(self.embedded_fonts)),
                ("non_embedded_fonts", sorted(self.non_embedded_fonts)),
                (
                    "synthetic_tajawal_weight_limitation",
                    self.synthetic_tajawal_weight_limitation,
                ),
                ("visible_drop_shadow_count", self.visible_drop_shadow_count),
                ("visible_blur_count", self.visible_blur_count),
                ("hidden_blur_count", self.hidden_blur_count),
                (
                    "unsupported_background_blur_count",
                    self.unsupported_background_blur_count,
                ),
                ("clip_path_count", self.clip_path_count),
                ("brand_normalization_enabled", self.brand_normalization_enabled),
                ("brand_replacement_count", self.brand_replacement_count),
                (
                    "approximation_mapping",
                    {
                        "blur_amount_to_std_deviation": BLUR_AMOUNT_TO_STD_DEVIATION,
                        "shadow_radius_to_std_deviation": SHADOW_RADIUS_TO_STD_DEVIATION,
                    },
                ),
                ("limitations", list(self.limitations)),
                ("warnings", list(self.warnings)),
            ]
        )


# ---------------------------------------------------------------------------
# XD package access.
# ---------------------------------------------------------------------------


@dataclass
class ManifestArtboard:
    """A canonical artboard entry as declared by the XD manifest."""

    name: str
    manifest_id: Optional[str]
    path: str
    x: float
    y: float
    width: float
    height: float

    @property
    def agc_path(self) -> str:
        return f"{self.path}/graphics/graphicContent.agc"

    def bounds_dict(self) -> Dict[str, float]:
        return {"x": self.x, "y": self.y, "width": self.width, "height": self.height}


class XdPackage:
    """Thin, read-only accessor over an ``.xd`` ZIP package."""

    MANIFEST_CANDIDATES = ("manifest", "manifest.json")
    SHARED_AGC_CANDIDATES = (
        "resources/graphics/graphicContent.agc",
        "resources/graphicContent.agc",
    )

    def __init__(self, path: "os.PathLike[str] | str") -> None:
        self.path = Path(path)
        if not self.path.is_file():
            raise XdExportError(f"XD package not found: {self.path}")
        if not zipfile.is_zipfile(self.path):
            raise XdExportError(f"Not a readable ZIP/XD package: {self.path}")
        self._zip = zipfile.ZipFile(self.path, "r")
        self._names = set(self._zip.namelist())
        self._manifest: Optional[Dict[str, Any]] = None

    # -- lifecycle --------------------------------------------------------
    def __enter__(self) -> "XdPackage":
        return self

    def __exit__(self, *_exc: Any) -> None:
        self.close()

    def close(self) -> None:
        try:
            self._zip.close()
        except Exception:  # pragma: no cover - best effort cleanup
            pass

    # -- raw access -------------------------------------------------------
    def names(self) -> List[str]:
        return sorted(self._names)

    def has(self, name: str) -> bool:
        return name in self._names

    def read_bytes(self, name: str) -> bytes:
        if name not in self._names:
            raise KeyError(name)
        return self._zip.read(name)

    def read_json(self, name: str) -> Dict[str, Any]:
        raw = self.read_bytes(name)
        return json.loads(raw.decode("utf-8-sig", errors="replace"))

    # -- manifest ---------------------------------------------------------
    @property
    def manifest(self) -> Dict[str, Any]:
        if self._manifest is None:
            for candidate in self.MANIFEST_CANDIDATES:
                if self.has(candidate):
                    self._manifest = self.read_json(candidate)
                    break
            else:
                raise XdExportError(
                    f"No manifest entry found inside XD package: {self.path}"
                )
        return self._manifest

    def artboards(self) -> List[ManifestArtboard]:
        found: List[ManifestArtboard] = []
        self._walk_manifest(self.manifest, "", found)
        return found

    def _walk_manifest(
        self, node: Any, prefix: str, out: List[ManifestArtboard]
    ) -> None:
        if not isinstance(node, dict):
            return
        raw_path = node.get("path")
        current = prefix
        if isinstance(raw_path, str) and raw_path not in ("", "/"):
            current = f"{prefix}/{raw_path}" if prefix else raw_path
        if self._is_artboard_entry(node):
            x, y, width, height = self._extract_bounds(node)
            out.append(
                ManifestArtboard(
                    name=str(node.get("name", "")),
                    manifest_id=node.get("id"),
                    path=current,
                    x=x,
                    y=y,
                    width=width,
                    height=height,
                )
            )
        for child in node.get("children", []) or []:
            self._walk_manifest(child, current, out)

    @staticmethod
    def _is_artboard_entry(node: Dict[str, Any]) -> bool:
        if node.get("type") == "artboard":
            return True
        path = node.get("path")
        return isinstance(path, str) and path.startswith("artboard-") and "name" in node

    @staticmethod
    def _extract_bounds(node: Dict[str, Any]) -> Tuple[float, float, float, float]:
        bounds = node.get("uxdesign#bounds") or node.get("bounds")
        if isinstance(bounds, dict):
            return (
                to_float(bounds.get("x")),
                to_float(bounds.get("y")),
                to_float(bounds.get("width")),
                to_float(bounds.get("height")),
            )
        return (
            to_float(node.get("uxdesign#x")),
            to_float(node.get("uxdesign#y")),
            to_float(node.get("uxdesign#width")),
            to_float(node.get("uxdesign#height")),
        )

    def find_artboard_by_exact_name(self, name: str) -> ManifestArtboard:
        """Exact (character-for-character) canonical manifest name lookup."""
        matches = [ab for ab in self.artboards() if ab.name == name]
        if len(matches) == 1:
            return matches[0]
        if len(matches) > 1:
            # Manifest ids are ASCII and survive any terminal encoding, so they
            # keep the diagnostic actionable even if the name renders poorly.
            detail = ", ".join(f"{ab.manifest_id} ({ab.path})" for ab in matches)
            raise XdExportError(
                f"Artboard name {name!r} is ambiguous; matched {len(matches)} "
                f"entries: {detail}. Select one with --artboard-id or "
                "--artboard-path instead."
            )
        available = [ab.name for ab in self.artboards()]
        near = [candidate for candidate in available if name.strip() in candidate]
        hint = f" Similar names: {near[:5]}" if near else ""
        raise XdExportError(
            f"Artboard {name!r} not found. The package declares "
            f"{len(available)} artboards.{hint}"
        )

    def find_artboard_by_manifest_id(self, manifest_id: str) -> ManifestArtboard:
        """Canonical machine selector: the manifest id is unique per artboard."""
        if not isinstance(manifest_id, str) or not manifest_id.strip():
            raise XdExportError("An artboard manifest id must be a non-empty string.")
        wanted = manifest_id.strip()
        matches = [ab for ab in self.artboards() if ab.manifest_id == wanted]
        if len(matches) == 1:
            return matches[0]
        if len(matches) > 1:
            paths = ", ".join(ab.path for ab in matches)
            raise XdExportError(
                f"Manifest id {wanted!r} is ambiguous; it matched {len(matches)} "
                f"artboards: {paths}. Refusing to guess."
            )
        raise XdExportError(
            f"No artboard with manifest id {wanted!r}. The package declares "
            f"{len(self.artboards())} artboards; run --list-artboards to see them."
        )

    def find_artboard_by_path(self, path: str) -> ManifestArtboard:
        """Secondary stable selector: the canonical ``artwork/artboard-<uuid>``."""
        if not isinstance(path, str) or not path.strip():
            raise XdExportError("An artboard path must be a non-empty string.")
        # A single trailing slash is normalised; nothing else is guessed.
        wanted = path.strip().rstrip("/")
        if wanted.endswith(AGC_PATH_SUFFIX):
            raise XdExportError(
                f"{path!r} is an AGC file path. --artboard-path expects the canonical "
                f"artwork directory instead, e.g. "
                f"{wanted[: -len(AGC_PATH_SUFFIX)]!r}."
            )
        matches = [ab for ab in self.artboards() if ab.path == wanted]
        if len(matches) == 1:
            return matches[0]
        if len(matches) > 1:
            ids = ", ".join(str(ab.manifest_id) for ab in matches)
            raise XdExportError(
                f"Artboard path {wanted!r} is ambiguous; it matched {len(matches)} "
                f"artboards: {ids}. Refusing to guess."
            )
        raise XdExportError(
            f"No artboard at path {wanted!r}. Expected a canonical manifest artwork "
            "path such as 'artwork/artboard-<uuid>'; run --list-artboards to see them."
        )

    # -- graphics ---------------------------------------------------------
    def read_artboard_agc(self, artboard: ManifestArtboard) -> Dict[str, Any]:
        tail = "/graphics/graphicContent.agc"
        leaf = artboard.path.rsplit("/", 1)[-1]
        candidates = [artboard.agc_path]
        candidates.extend(
            name
            for name in sorted(self._names)
            if name.endswith(tail) and f"/{leaf}/" in f"/{name}"
        )
        for candidate in candidates:
            if self.has(candidate):
                return self.read_json(candidate)
        raise XdExportError(
            f"graphicContent.agc not found for artboard {artboard.name!r} "
            f"(expected {artboard.agc_path})"
        )

    def read_shared_agc(self) -> Optional[Dict[str, Any]]:
        for candidate in self.SHARED_AGC_CANDIDATES:
            if self.has(candidate):
                try:
                    return self.read_json(candidate)
                except (ValueError, KeyError):
                    return None
        return None

    def read_resource(self, resource_id: str) -> Optional[bytes]:
        """Resolve ``resources/<uid>`` (with tolerant suffix fallback)."""
        if not resource_id:
            return None
        direct = f"resources/{resource_id}"
        if self.has(direct):
            return self.read_bytes(direct)
        prefix = direct + "."
        for name in sorted(self._names):
            if name.startswith(prefix):
                return self.read_bytes(name)
        for name in sorted(self._names):
            if name.rsplit("/", 1)[-1] == resource_id:
                return self.read_bytes(name)
        return None


# ---------------------------------------------------------------------------
# Resource + symbol indexing.
# ---------------------------------------------------------------------------


def child_nodes_of(node: Dict[str, Any]) -> List[Dict[str, Any]]:
    """Return the child list of an AGC container node, whatever wraps it."""
    for container_key in ("group", "artboard", "clipPath", "compound", "symbol"):
        container = node.get(container_key)
        if isinstance(container, dict) and isinstance(container.get("children"), list):
            return [c for c in container["children"] if isinstance(c, dict)]
    if isinstance(node.get("children"), list):
        return [c for c in node["children"] if isinstance(c, dict)]
    return []


class AgcResourceIndex:
    """Index of AGC ``resources`` (gradients, clipPaths, shared symbols)."""

    def __init__(
        self,
        artboard_agc: Dict[str, Any],
        shared_agc: Optional[Dict[str, Any]] = None,
    ) -> None:
        self.gradients: Dict[str, Any] = {}
        self.clip_paths: Dict[str, Any] = {}
        self.symbols: Dict[str, Any] = {}
        for source in (shared_agc, artboard_agc):
            if isinstance(source, dict):
                self._absorb(source)

    def _absorb(self, agc: Dict[str, Any]) -> None:
        resources = agc.get("resources")
        if isinstance(resources, dict):
            for key, value in resources.items():
                if key == "gradients" and isinstance(value, dict):
                    self.gradients.update(value)
                elif key == "clipPaths" and isinstance(value, dict):
                    self.clip_paths.update(value)
            meta_ux = (resources.get("meta") or {}).get("ux") or {}
            if isinstance(meta_ux, dict):
                self._collect_symbols(meta_ux.get("symbols"))
        self._collect_symbols(agc.get("children"))

    def _collect_symbols(self, nodes: Any) -> None:
        if isinstance(nodes, dict):
            nodes = [nodes]
        if not isinstance(nodes, list):
            return
        for node in nodes:
            if not isinstance(node, dict):
                continue
            ux = (node.get("meta") or {}).get("ux") or {}
            if isinstance(ux, dict):
                for key in ("symbolId", "componentId", "guid"):
                    identifier = ux.get(key)
                    if isinstance(identifier, str):
                        self.symbols.setdefault(identifier, node)
            for key in ("symbolId", "componentId", "guid", "id"):
                identifier = node.get(key)
                if isinstance(identifier, str):
                    self.symbols.setdefault(identifier, node)
            self._collect_symbols(child_nodes_of(node))

    def gradient(self, gradient_id: str) -> Optional[Dict[str, Any]]:
        value = self.gradients.get(gradient_id)
        return value if isinstance(value, dict) else None

    def clip_path(self, clip_id: str) -> Optional[Any]:
        return self.clip_paths.get(clip_id)

    def symbol(self, symbol_id: str) -> Optional[Dict[str, Any]]:
        value = self.symbols.get(symbol_id)
        return value if isinstance(value, dict) else None


class ResourceLoader:
    """Converts ``resources/<uid>`` blobs into cached data URIs."""

    def __init__(self, package: XdPackage, report: ExportReport) -> None:
        self._package = package
        self._report = report
        self._cache: Dict[str, Optional[str]] = {}

    def data_uri_for(self, resource_id: str) -> Optional[str]:
        if resource_id in self._cache:
            return self._cache[resource_id]
        data = self._package.read_resource(resource_id)
        uri = bytes_to_data_uri(data) if data else None
        if uri is None:
            self._report.warn(
                f"Image resource 'resources/{resource_id}' could not be resolved "
                "inside the XD package."
            )
        else:
            self._report.note_resource(resource_id)
        self._cache[resource_id] = uri
        return uri


# ---------------------------------------------------------------------------
# Font embedding.
# ---------------------------------------------------------------------------


class FontEmbedder:
    """Builds the ``@font-face`` CSS block embedded in the SVG."""

    def __init__(self, font_path: Optional[Path], report: ExportReport) -> None:
        self.font_path = Path(font_path) if font_path else None
        self._report = report
        self._data_uri: Optional[str] = None
        if self.font_path and self.font_path.is_file():
            payload = self.font_path.read_bytes()
            self._data_uri = (
                "data:font/ttf;base64," + base64.b64encode(payload).decode("ascii")
            )
            report.embedded_fonts = list(TAJAWAL_ALIASES)
            report.synthetic_tajawal_weight_limitation = True
            report.note_limitation(
                "Only Tajawal-Regular.ttf is embedded. The Tajawal Light/Medium/Bold "
                "aliases resolve to the same regular outlines and rely on browser "
                "weight synthesis, so glyph weight is approximated, not typographically "
                "exact."
            )
        else:
            report.embedded_fonts = []
            report.synthetic_tajawal_weight_limitation = False
            report.warn(
                f"Font file not found: {self.font_path}. No @font-face was embedded; "
                "text rendering will fall back to browser fonts."
            )

    @property
    def available(self) -> bool:
        return self._data_uri is not None

    def is_embedded_family(self, family: Any) -> bool:
        if not self.available or not family:
            return False
        return "tajawal" in str(family).replace(" ", "").replace("-", "").lower()

    def css(self) -> str:
        if not self._data_uri:
            return ""
        blocks: List[str] = []
        for alias in TAJAWAL_ALIASES:
            weight = (
                font_weight_for_style_name(alias.split("-", 1)[1])
                if "-" in alias
                else 400
            )
            blocks.append(
                "@font-face{"
                f"font-family:'{alias}';"
                "font-style:normal;"
                f"font-weight:{weight};"
                "font-display:block;"
                f"src:url('{self._data_uri}') format('truetype');"
                "}"
            )
        # Family-level aliases so XD "Tajawal" + weight requests also resolve.
        for weight in (300, 400, 500, 700):
            blocks.append(
                "@font-face{"
                "font-family:'Tajawal';"
                "font-style:normal;"
                f"font-weight:{weight};"
                "font-display:block;"
                f"src:url('{self._data_uri}') format('truetype');"
                "}"
            )
        return "".join(blocks)


# ---------------------------------------------------------------------------
# SVG document / defs management.
# ---------------------------------------------------------------------------


class SvgDocument:
    """Holds ``<defs>`` entries and hands out deterministic generated IDs."""

    def __init__(self) -> None:
        self._defs: List[str] = []
        self._counters: Dict[str, int] = {}
        self._named_clip_ids: Dict[str, str] = {}

    def new_id(self, prefix: str) -> str:
        index = self._counters.get(prefix, 0) + 1
        self._counters[prefix] = index
        return f"mxg-{prefix}-{index}"

    def add_def(self, markup: str) -> None:
        self._defs.append(markup)

    def defs_markup(self, indent: str = "    ") -> str:
        return "\n".join(indent + line for line in self._defs)

    def register_named_clip(self, key: str, clip_id: str) -> None:
        self._named_clip_ids[key] = clip_id

    def named_clip(self, key: str) -> Optional[str]:
        return self._named_clip_ids.get(key)

    @property
    def has_defs(self) -> bool:
        return bool(self._defs)


# ---------------------------------------------------------------------------
# AGC -> SVG rendering.
# ---------------------------------------------------------------------------


@dataclass
class RenderOptions:
    normalize_brand: bool = False


@dataclass
class ShapeGeometry:
    """A single SVG geometry element plus the local paint bounds of its box.

    ``bounds_reliable`` marks geometries whose local paint bounds are derived
    directly from declared XD values (rect/circle/ellipse). Image fills are laid
    out against those bounds; anything else falls back and says so in the report
    rather than pretending it knows the box.
    """

    tag: str
    attrs: "OrderedDict[str, Any]" = field(default_factory=OrderedDict)
    origin: Tuple[float, float] = (0.0, 0.0)
    size: Tuple[float, float] = (0.0, 0.0)
    bounds_reliable: bool = False


def normalize_pattern_payload(candidate: Any) -> Optional[Dict[str, Any]]:
    """Unwrap the real pattern payload.

    AGC exposes patterns in more than one shape::

        {"type": "pattern", "pattern": {...actual...}}
        style.fill = {"type": "pattern", "pattern": {...actual...}}
        style.fill = {"type": "pattern", "pattern": {"type": "pattern",
                                                     "pattern": {...actual...}}}

    The ``uid`` never lives on the outer wrapper, so descend until no further
    ``pattern`` member exists and return the innermost object.
    """
    depth = 0
    current = candidate
    while isinstance(current, dict) and isinstance(current.get("pattern"), dict):
        current = current["pattern"]
        depth += 1
        if depth > 8:  # defensive: malformed self-referencing payloads
            break
    return current if isinstance(current, dict) else None


def pattern_resource_uid(pattern: Dict[str, Any]) -> Optional[str]:
    """Resolve the image blob id: ``pattern.meta.ux.uid`` -> ``resources/<uid>``."""
    ux = (pattern.get("meta") or {}).get("ux") or {}
    if isinstance(ux, dict):
        for key in ("uid", "uidRef"):
            value = ux.get(key)
            if isinstance(value, str) and value:
                return value
    href = pattern.get("href")
    if isinstance(href, str) and href:
        return href.split("/")[-1]
    return None


@dataclass
class BlendHoistDecision:
    """What the exporter decided to do about one node's XD blend mode."""

    blend_mode: str
    strategy: str
    safe_hoist: bool
    reason: str
    source_node_name: Optional[str] = None
    target_group_name: Optional[str] = None
    source_opacity: Optional[float] = None
    target_opacity: Optional[float] = None

    @property
    def application_key(self) -> str:
        return f"{self.blend_mode}:{self.strategy}"

    def to_dict(self) -> Dict[str, Any]:
        return OrderedDict(
            [
                ("blend_mode", self.blend_mode),
                ("strategy", self.strategy),
                ("safe_hoist", self.safe_hoist),
                ("reason", self.reason),
                ("source_node_name", self.source_node_name),
                ("target_group_name", self.target_group_name),
                ("source_opacity", self.source_opacity),
                ("target_opacity", self.target_opacity),
            ]
        )


class BlendHoistPlan:
    """Result of the blend pre-pass: per-source decisions and per-group targets."""

    def __init__(self) -> None:
        self._decisions: Dict[int, BlendHoistDecision] = {}
        self._targets: Dict[int, str] = {}

    def record(self, node: Dict[str, Any], decision: BlendHoistDecision) -> None:
        self._decisions[id(node)] = decision

    def add_target(self, group: Dict[str, Any], blend_mode: str) -> None:
        self._targets[id(group)] = blend_mode

    def decision_for(self, node: Dict[str, Any]) -> Optional[BlendHoistDecision]:
        return self._decisions.get(id(node))

    def blend_for_target(self, node: Dict[str, Any]) -> Optional[str]:
        return self._targets.get(id(node))

    @property
    def safe_hoist_count(self) -> int:
        return len(self._targets)


class BlendHoistPlanner:
    """Decides, before rendering, where a calibrated soft-light may be applied.

    Iteration I2-D3 measured the authentic XD Splash preview and found that
    applying ``mix-blend-mode: soft-light`` to the *Repeat Grid* opacity group -
    while leaving both the group's 0.5 and the image's 0.12 opacity untouched -
    dropped MAE from 5.149241 to 0.457513. Applying it on the blended node
    itself, or on the painted shape, made the error worse.

    This planner reproduces only that calibrated structure, and only when it can
    prove the hoist cannot disturb unrelated painted content. Anything it cannot
    prove stays reported as unsupported.
    """

    def __init__(self) -> None:
        self._paint_cache: Dict[int, bool] = {}

    # -- public API -------------------------------------------------------
    def plan(self, roots: Sequence[Dict[str, Any]]) -> BlendHoistPlan:
        candidates: List[Tuple[Dict[str, Any], List[Dict[str, Any]], str]] = []
        for root in roots:
            self._collect(root, [], candidates)

        plan = BlendHoistPlan()
        safe: List[Tuple[Dict[str, Any], Dict[str, Any], BlendHoistDecision]] = []
        for node, ancestors, blend_mode in candidates:
            target, decision = self._decide(node, ancestors, blend_mode)
            if target is None:
                plan.record(node, decision)
            else:
                safe.append((node, target, decision))

        # Two soft-light sources sharing one target would need two blend passes,
        # which a single CSS declaration cannot express: refuse both.
        per_target: Dict[int, int] = {}
        for _node, target, _decision in safe:
            per_target[id(target)] = per_target.get(id(target), 0) + 1

        for node, target, decision in safe:
            if per_target[id(target)] > 1:
                plan.record(
                    node,
                    BlendHoistDecision(
                        blend_mode=decision.blend_mode,
                        strategy=BLEND_STRATEGY_UNSUPPORTED,
                        safe_hoist=False,
                        reason="multiple-soft-light-sources-target-group",
                        source_node_name=decision.source_node_name,
                        target_group_name=decision.target_group_name,
                        source_opacity=decision.source_opacity,
                        target_opacity=decision.target_opacity,
                    ),
                )
                continue
            plan.record(node, decision)
            plan.add_target(target, decision.blend_mode)
        return plan

    # -- traversal --------------------------------------------------------
    def _collect(
        self,
        node: Dict[str, Any],
        ancestors: List[Dict[str, Any]],
        out: List[Tuple[Dict[str, Any], List[Dict[str, Any]], str]],
    ) -> None:
        if not isinstance(node, dict) or AgcRenderer._is_hidden(node):
            return
        if node.get("type") == "clipPath":
            return  # a definition, never painted: it cannot host a blend
        blend_mode = extract_blend_mode(node)
        if blend_mode is not None:
            out.append((node, list(ancestors), blend_mode))
        if node.get("type") == "syncRef":
            return  # resolved at render time; treated as an opaque leaf here
        child_ancestors = ancestors + [node]
        for child in child_nodes_of(node):
            self._collect(child, child_ancestors, out)

    # -- decision ---------------------------------------------------------
    def _decide(
        self,
        node: Dict[str, Any],
        ancestors: List[Dict[str, Any]],
        blend_mode: str,
    ) -> Tuple[Optional[Dict[str, Any]], BlendHoistDecision]:
        source_name = node.get("name") if isinstance(node.get("name"), str) else None
        source_opacity = node_opacity(node)

        def refuse(reason: str, target: Optional[Dict[str, Any]] = None):
            target_name = (
                target.get("name")
                if isinstance(target, dict) and isinstance(target.get("name"), str)
                else None
            )
            return None, BlendHoistDecision(
                blend_mode=blend_mode,
                strategy=BLEND_STRATEGY_UNSUPPORTED,
                safe_hoist=False,
                reason=reason,
                source_node_name=source_name,
                target_group_name=target_name,
                source_opacity=source_opacity,
                target_opacity=explicit_group_opacity(target) if target else None,
            )

        if blend_mode != CALIBRATED_BLEND_MODE:
            return refuse("blend-mode-not-calibrated")
        if not self._paints(node):
            return refuse("source-node-paints-nothing")

        target: Optional[Dict[str, Any]] = None
        target_index = -1
        for index in range(len(ancestors) - 1, -1, -1):
            if explicit_group_opacity(ancestors[index]) is not None:
                target = ancestors[index]
                target_index = index
                break
        if target is None:
            return refuse("no-opacity-group-ancestor")

        chain = ancestors[target_index:] + [node]
        if not self._is_single_content_chain(chain):
            return refuse("ancestor-chain-not-single-content-branch", target)

        return target, BlendHoistDecision(
            blend_mode=blend_mode,
            strategy=BLEND_STRATEGY_SAFE_OPACITY_GROUP,
            safe_hoist=True,
            reason="single-content-chain-to-nearest-opacity-group",
            source_node_name=source_name,
            target_group_name=(
                target.get("name") if isinstance(target.get("name"), str) else None
            ),
            source_opacity=source_opacity,
            target_opacity=explicit_group_opacity(target),
        )

    def _is_single_content_chain(self, chain: Sequence[Dict[str, Any]]) -> bool:
        """Every container on the chain must have exactly one painted branch.

        This is the safety proof: if each group from the opacity group down to
        the blended node paints through a single visible branch, then blending
        the group is indistinguishable from blending that branch, and no
        unrelated sibling content can be affected.
        """
        for parent, expected_child in zip(chain, chain[1:]):
            painted = [
                child for child in child_nodes_of(parent) if self._paints(child)
            ]
            if len(painted) != 1 or painted[0] is not expected_child:
                return False
        return True

    def _paints(self, node: Dict[str, Any]) -> bool:
        """Conservatively decide whether a node contributes visible paint."""
        cached = self._paint_cache.get(id(node))
        if cached is not None:
            return cached
        result = self._compute_paints(node)
        self._paint_cache[id(node)] = result
        return result

    def _compute_paints(self, node: Dict[str, Any]) -> bool:
        if not isinstance(node, dict) or AgcRenderer._is_hidden(node):
            return False
        node_type = node.get("type") or AgcRenderer._infer_node_type(node)
        if node_type == "clipPath":
            return False
        if node_type in ("group", "artboard"):
            return any(self._paints(child) for child in child_nodes_of(node))
        if node_type == "shape":
            return isinstance(node.get("shape"), dict)
        if node_type == "text":
            return isinstance(node.get("text"), dict)
        # syncRef and anything unrecognised may paint: assume it does, so an
        # ambiguous branch blocks hoisting rather than silently permitting it.
        return True


class AgcRenderer:
    """Walks AGC nodes and emits SVG markup."""

    def __init__(
        self,
        document: SvgDocument,
        resources: AgcResourceIndex,
        loader: ResourceLoader,
        fonts: FontEmbedder,
        report: ExportReport,
        options: RenderOptions,
        blend_plan: Optional[BlendHoistPlan] = None,
    ) -> None:
        self.doc = document
        self.resources = resources
        self.loader = loader
        self.fonts = fonts
        self.report = report
        self.options = options
        self.blend_plan = blend_plan if blend_plan is not None else BlendHoistPlan()
        self._sync_ref_stack: List[str] = []

    # -- entry point ------------------------------------------------------
    def render_nodes(self, nodes: Sequence[Dict[str, Any]], depth: int) -> List[str]:
        out: List[str] = []
        for node in nodes:
            if isinstance(node, dict):
                out.extend(self.render_node(node, depth))
        return out

    def render_node(self, node: Dict[str, Any], depth: int) -> List[str]:
        node_type = str(node.get("type") or self._infer_node_type(node) or "unknown")
        self.report.count_node_type(node_type)

        if self._is_hidden(node):
            self.report.invisible_node_count += 1
            return []

        # A clipPath node is a *definition*, never ordinary painted content.
        if node_type == "clipPath":
            self._register_clip_path_node(node)
            return []

        style = node.get("style") if isinstance(node.get("style"), dict) else {}
        self._report_blend_mode(node)

        if node_type == "syncRef":
            return self._render_sync_ref(node, depth)

        wrapper_attrs = self._wrapper_attributes(node, style)
        inner_depth = depth + (1 if wrapper_attrs else 0)

        if node_type in ("group", "artboard"):
            self.report.count_handled(node_type)
            body = self.render_nodes(child_nodes_of(node), inner_depth)
        elif node_type == "shape":
            body = self._render_shape_node(node, style, inner_depth)
        elif node_type == "text":
            body = self._render_text_node(node, style, inner_depth)
        else:
            children = child_nodes_of(node)
            if children:
                self.report.count_unsupported(
                    f"container:{node_type}",
                    f"Unknown container node type {node_type!r} was rendered as a "
                    "plain group; its own semantics were not applied.",
                )
                body = self.render_nodes(children, inner_depth)
            else:
                self.report.count_unsupported(
                    f"node:{node_type}",
                    f"Node type {node_type!r} is not supported by iteration I1 and "
                    "was skipped.",
                )
                return []

        if not body:
            return []
        if not wrapper_attrs:
            return body
        pad = "  " * depth
        return [f"{pad}<g {attrs_to_string(wrapper_attrs)}>"] + body + [f"{pad}</g>"]

    # -- node helpers -----------------------------------------------------
    @staticmethod
    def _infer_node_type(node: Dict[str, Any]) -> Optional[str]:
        for key in ("artboard", "group", "shape", "text", "syncRef", "clipPath"):
            if isinstance(node.get(key), dict):
                return key
        return None

    @staticmethod
    def _is_hidden(node: Dict[str, Any]) -> bool:
        if node.get("visible") is False:
            return True
        ux = (node.get("meta") or {}).get("ux") or {}
        return isinstance(ux, dict) and ux.get("visible") is False

    def _report_blend_mode(self, node: Dict[str, Any]) -> None:
        """Report a node's XD blend mode and what was done about it.

        Only the calibrated ``soft-light`` hoist (see :class:`BlendHoistPlanner`)
        produces CSS. Everything else - other modes, and any soft-light whose
        safe target could not be proven - stays an explicitly reported gap.
        """
        blend_mode = extract_blend_mode(node)
        if blend_mode is None:
            return
        self.report.count_blend_mode(blend_mode)

        decision = self.blend_plan.decision_for(node)
        if decision is None:
            decision = BlendHoistDecision(
                blend_mode=blend_mode,
                strategy=BLEND_STRATEGY_UNSUPPORTED,
                safe_hoist=False,
                reason="node-outside-analysed-render-tree",
                source_node_name=(
                    node.get("name") if isinstance(node.get("name"), str) else None
                ),
                source_opacity=node_opacity(node),
            )

        self.report.count_blend_application(decision.application_key)
        self.report.note_blend_application(decision.to_dict())

        if decision.safe_hoist:
            return

        if blend_mode == CALIBRATED_BLEND_MODE:
            self.report.count_unsupported(
                f"style:blendMode:{blend_mode}",
                f"XD blend mode {blend_mode!r} was left unsupported because a safe "
                f"hoist target could not be proven ({decision.reason}). No CSS "
                "mix-blend-mode was emitted: the calibrated approximation is only "
                "applied to a single-content-chain opacity group ancestor.",
            )
            return

        self.report.count_unsupported(
            f"style:blendMode:{blend_mode}",
            f"XD blend mode {blend_mode!r} is not reproduced. No CSS mix-blend-mode "
            "approximation was applied, because only 'soft-light' has been "
            "calibrated against the authentic XD preview. This node is composited "
            "normally.",
        )

    def _wrapper_attributes(
        self, node: Dict[str, Any], style: Dict[str, Any]
    ) -> "OrderedDict[str, Any]":
        attrs: "OrderedDict[str, Any]" = OrderedDict()
        name = node.get("name")
        if isinstance(name, str) and name:
            attrs["data-xd-name"] = name
        transform = self._transform_attribute(node)
        if transform:
            attrs["transform"] = transform
        opacity = style.get("opacity")
        if opacity is not None and to_float(opacity, 1.0) != 1.0:
            attrs["opacity"] = fmt_num(opacity, 1.0)
        clip_id = self._resolve_clip_path(node, style)
        if clip_id:
            attrs["clip-path"] = f"url(#{clip_id})"
        filter_id = self._build_filter(style)
        if filter_id:
            attrs["filter"] = f"url(#{filter_id})"
        # The calibrated soft-light hoist lands here, on the opacity group's own
        # wrapper. Existing opacity values are left exactly as XD declared them.
        hoisted_blend = self.blend_plan.blend_for_target(node)
        if hoisted_blend:
            attrs["style"] = f"mix-blend-mode:{hoisted_blend}"
        if len(attrs) == 1 and "data-xd-name" in attrs:
            # A name alone is not worth an extra group.
            return OrderedDict()
        return attrs

    @staticmethod
    def _transform_attribute(node: Dict[str, Any]) -> Optional[str]:
        transform = node.get("transform")
        if not isinstance(transform, dict):
            return None
        a = to_float(transform.get("a"), 1.0)
        b = to_float(transform.get("b"), 0.0)
        c = to_float(transform.get("c"), 0.0)
        d = to_float(transform.get("d"), 1.0)
        tx = to_float(transform.get("tx"), 0.0)
        ty = to_float(transform.get("ty"), 0.0)
        if (a, b, c, d, tx, ty) == (1.0, 0.0, 0.0, 1.0, 0.0, 0.0):
            return None
        return "matrix(" + " ".join(fmt_num(v) for v in (a, b, c, d, tx, ty)) + ")"

    # -- syncRef ----------------------------------------------------------
    @staticmethod
    def _first_string(sources: Sequence[Any], keys: Sequence[str]) -> Optional[str]:
        for source in sources:
            if not isinstance(source, dict):
                continue
            for key in keys:
                value = source.get(key)
                if isinstance(value, str) and value:
                    return value
        return None

    def _sync_ref_identity(
        self, node: Dict[str, Any], payload: Dict[str, Any]
    ) -> Tuple[Optional[str], Optional[str], str]:
        """Return ``(instance_guid, lookup_key, selector)`` for a syncRef node.

        XD carries two distinct identities on a syncRef, and conflating them was
        the defect this repairs:

        ``guid``
            identifies *this instance* of the reference.
        ``syncSourceGuid``
            identifies the *shared source definition* in the AGC symbol index.

        Only ``syncSourceGuid`` can index the shared definition, so it wins
        whenever present. The older ``ref``/``guid``/``symbolId``/``componentId``
        scan is kept purely as a fallback for nodes that declare no
        ``syncSourceGuid``.
        """
        ux = (node.get("meta") or {}).get("ux") or {}
        sources = (payload, node, ux if isinstance(ux, dict) else {})

        instance_guid = self._first_string(sources, ("guid",))
        source_guid = self._first_string(sources, ("syncSourceGuid",))
        if source_guid is not None:
            return instance_guid, source_guid, "syncSourceGuid"

        fallback = self._first_string(
            sources, ("ref", "guid", "symbolId", "componentId")
        )
        return instance_guid, fallback, "legacy-fallback"

    def _render_sync_ref(self, node: Dict[str, Any], depth: int) -> List[str]:
        payload = node.get("syncRef") if isinstance(node.get("syncRef"), dict) else {}
        instance_guid, lookup_key, selector = self._sync_ref_identity(node, payload)

        # Recursion is keyed on the identity actually used for resolution, so a
        # source that references itself is caught even though every instance guid
        # along the way is distinct.
        recursive = lookup_key is not None and lookup_key in self._sync_ref_stack
        symbol = (
            None
            if (recursive or lookup_key is None)
            else self.resources.symbol(lookup_key)
        )

        if symbol is None:
            self.report.unresolved_sync_refs += 1
            self.report.count_unsupported("syncRef:unresolved")
            reason = (
                "recursive reference"
                if recursive
                else "no matching definition in the artboard or shared AGC resources"
            )
            self.report.warn(
                f"syncRef instance {instance_guid!r} could not be resolved: attempted "
                f"source guid {lookup_key!r} via {selector} ({reason}). Only the "
                "referenced content was skipped."
            )
            return []

        self.report.resolved_sync_refs += 1
        self.report.count_handled("syncRef")
        self._sync_ref_stack.append(lookup_key)
        try:
            # The instance keeps its own placement; the resolved source node is
            # rendered underneath it exactly as indexed, carrying whatever
            # transform and style it already has. The blend mode is stripped from
            # the proxy because the syncRef node has already reported it; leaving
            # it would double-count.
            source_style = (
                node.get("style") if isinstance(node.get("style"), dict) else {}
            )
            proxy: Dict[str, Any] = {
                "type": "group",
                "name": node.get("name"),
                "transform": node.get("transform") or payload.get("transform"),
                "style": {
                    key: value
                    for key, value in source_style.items()
                    if key != "blendMode"
                },
                "group": {"children": [symbol]},
            }
            return self.render_node(proxy, depth)
        finally:
            self._sync_ref_stack.pop()

    # -- clip paths -------------------------------------------------------
    def _register_clip_path_node(self, node: Dict[str, Any]) -> Optional[str]:
        key = node.get("id") if isinstance(node.get("id"), str) else None
        if key:
            cached = self.doc.named_clip(key)
            if cached:
                return cached
        clip_id = self._emit_clip_path(child_nodes_of(node))
        if clip_id and key:
            self.doc.register_named_clip(key, clip_id)
        return clip_id

    def _resolve_clip_path(
        self, node: Dict[str, Any], style: Dict[str, Any]
    ) -> Optional[str]:
        candidate = style.get("clipPath")
        if candidate is None:
            ux = (node.get("meta") or {}).get("ux") or {}
            if isinstance(ux, dict):
                candidate = ux.get("clipPathResources") or ux.get("clipPath")

        if isinstance(candidate, str):
            cached = self.doc.named_clip(candidate)
            if cached:
                return cached
            resolved = self.resources.clip_path(candidate)
            if resolved is None:
                self.report.count_unsupported(
                    "clipPath:unresolved",
                    f"clipPath reference {candidate!r} was not found in AGC resources; "
                    "the node was rendered unclipped.",
                )
                return None
            clip_id = self._emit_clip_path(self._clip_children_of(resolved))
            if clip_id:
                self.doc.register_named_clip(candidate, clip_id)
            return clip_id

        if isinstance(candidate, dict):
            ref = candidate.get("ref")
            if isinstance(ref, str):
                cached = self.doc.named_clip(ref)
                if cached:
                    return cached
                resolved = self.resources.clip_path(ref)
                if isinstance(resolved, dict):
                    candidate = resolved
                else:
                    self.report.count_unsupported(
                        "clipPath:unresolved",
                        f"clipPath ref {ref!r} was not found in AGC resources; the "
                        "node was rendered unclipped.",
                    )
                    return None
            clip_id = self._emit_clip_path(self._clip_children_of(candidate))
            if clip_id and isinstance(ref, str):
                self.doc.register_named_clip(ref, clip_id)
            return clip_id
        return None

    @staticmethod
    def _clip_children_of(candidate: Any) -> List[Dict[str, Any]]:
        if isinstance(candidate, list):
            return [c for c in candidate if isinstance(c, dict)]
        if not isinstance(candidate, dict):
            return []
        children = child_nodes_of(candidate)
        if children:
            return children
        return [candidate] if candidate.get("type") else []

    def _emit_clip_path(self, children: Sequence[Dict[str, Any]]) -> Optional[str]:
        geometry: List[str] = []
        for child in children:
            geometry.extend(self._clip_geometry(child))
        if not geometry:
            return None
        clip_id = self.doc.new_id("clip")
        self.doc.add_def(
            f'<clipPath id="{clip_id}" clipPathUnits="userSpaceOnUse">'
            + "".join(geometry)
            + "</clipPath>"
        )
        self.report.clip_path_count += 1
        self.report.count_handled("clipPath")
        return clip_id

    def _clip_geometry(self, node: Dict[str, Any]) -> List[str]:
        """Emit *geometry only* - clip children are never painted."""
        if not isinstance(node, dict):
            return []
        shape = node.get("shape") if isinstance(node.get("shape"), dict) else None
        if shape is None and node.get("type") in (
            "rect",
            "circle",
            "ellipse",
            "line",
            "path",
            "polygon",
            "compound",
        ):
            shape = node
        out: List[str] = []
        if shape is not None:
            geometry = self._shape_geometry(shape)
            if geometry is not None:
                attrs = OrderedDict(geometry.attrs)
                transform = self._transform_attribute(node)
                if transform:
                    attrs["transform"] = transform
                out.append(f"<{geometry.tag} {attrs_to_string(attrs)}/>")
        for child in child_nodes_of(node):
            out.extend(self._clip_geometry(child))
        return out

    # -- filters ----------------------------------------------------------
    def _build_filter(self, style: Dict[str, Any]) -> Optional[str]:
        filters = style.get("filters")
        if not isinstance(filters, list) or not filters:
            return None
        primitives: List[str] = []
        for entry in filters:
            if not isinstance(entry, dict):
                continue
            entry_type = str(entry.get("type") or "")
            if entry_type == "dropShadow":
                if entry.get("visible") is False:
                    self.report.count_handled("filter:dropShadow:hidden")
                    continue
                primitives.extend(self._drop_shadow_primitives(entry))
            elif entry_type in ("uxdesign#blur", "blur"):
                primitives.extend(self._blur_primitives(entry))
            else:
                self.report.count_unsupported(
                    f"filter:{entry_type or 'unknown'}",
                    f"Filter type {entry_type!r} is not implemented in iteration I1 "
                    "and was not applied.",
                )
        if not primitives:
            return None
        filter_id = self.doc.new_id("filter")
        self.doc.add_def(
            f'<filter id="{filter_id}" x="-50%" y="-50%" width="200%" height="200%" '
            'filterUnits="objectBoundingBox" color-interpolation-filters="sRGB">'
            + "".join(primitives)
            + "</filter>"
        )
        return filter_id

    def _drop_shadow_primitives(self, entry: Dict[str, Any]) -> List[str]:
        params = entry.get("params") if isinstance(entry.get("params"), dict) else {}
        shadows = params.get("dropShadows")
        if not isinstance(shadows, list):
            shadows = [params] if params else []
        out: List[str] = []
        for shadow in shadows:
            if not isinstance(shadow, dict):
                continue
            css_color, color_alpha = color_to_css(shadow.get("color"))
            alpha = clamp01(
                to_float(shadow.get("a", shadow.get("alpha")), color_alpha)
            )
            attrs = OrderedDict(
                [
                    ("dx", fmt_num(shadow.get("dx"), 0.0)),
                    ("dy", fmt_num(shadow.get("dy"), 0.0)),
                    (
                        "stdDeviation",
                        fmt_num(
                            to_float(shadow.get("r"), 0.0)
                            * SHADOW_RADIUS_TO_STD_DEVIATION
                        ),
                    ),
                    ("flood-color", css_color or "#000000"),
                    ("flood-opacity", fmt_num(alpha, 1.0)),
                ]
            )
            out.append(f"<feDropShadow {attrs_to_string(attrs)}/>")
            self.report.visible_drop_shadow_count += 1
            self.report.count_handled("filter:dropShadow")
            self.report.note_limitation(
                "XD drop shadow radius r is mapped to feDropShadow stdDeviation = "
                f"r * {SHADOW_RADIUS_TO_STD_DEVIATION}."
            )
        return out

    def _blur_primitives(self, entry: Dict[str, Any]) -> List[str]:
        # An invisible XD blur must NOT be applied.
        if entry.get("visible") is False:
            self.report.hidden_blur_count += 1
            self.report.count_handled("filter:uxdesign#blur:hidden")
            return []
        params = entry.get("params") if isinstance(entry.get("params"), dict) else {}
        if params.get("backgroundEffect") is True:
            self.report.unsupported_background_blur_count += 1
            self.report.count_unsupported(
                "filter:uxdesign#blur:background",
                "uxdesign#blur with backgroundEffect=true (backdrop blur) has no "
                "reliable standalone SVG equivalent; it is reported as unsupported "
                "rather than silently approximated.",
            )
            return []
        amount = to_float(params.get("blurAmount"), 0.0)
        std_deviation = amount * BLUR_AMOUNT_TO_STD_DEVIATION
        if std_deviation <= 0:
            self.report.count_handled("filter:uxdesign#blur:zero")
            return []
        self.report.visible_blur_count += 1
        self.report.count_handled("filter:uxdesign#blur")
        self.report.note_limitation(
            "uxdesign#blur is mapped to feGaussianBlur with stdDeviation = "
            f"blurAmount * {BLUR_AMOUNT_TO_STD_DEVIATION}; this is a deterministic "
            "approximation of XD's blur kernel, not an exact match."
        )
        return [f'<feGaussianBlur stdDeviation="{fmt_num(std_deviation)}"/>']

    # -- shapes -----------------------------------------------------------
    def _render_shape_node(
        self, node: Dict[str, Any], style: Dict[str, Any], depth: int
    ) -> List[str]:
        shape = node.get("shape")
        if not isinstance(shape, dict):
            self.report.count_unsupported(
                "shape:missing", "A shape node carried no 'shape' payload."
            )
            return []
        shape_type = str(shape.get("type") or "")

        if shape_type == "compound":
            return self._render_compound(node, shape, style, depth)

        geometry = self._shape_geometry(shape)
        if geometry is None:
            self.report.count_unsupported(
                f"shape:{shape_type or 'unknown'}",
                f"Shape geometry {shape_type!r} is not supported in iteration I1.",
            )
            return []

        self.report.count_handled(f"shape:{shape_type}")
        return self._render_painted_geometry(geometry, style, depth)

    def _render_compound(
        self,
        node: Dict[str, Any],
        shape: Dict[str, Any],
        style: Dict[str, Any],
        depth: int,
    ) -> List[str]:
        operation = str(shape.get("operation") or "unknown")
        path_data = shape.get("path")
        pad = "  " * depth
        if isinstance(path_data, str) and path_data.strip():
            # XD pre-flattens the boolean result into a single path: exact.
            self.report.count_handled(f"shape:compound:{operation}")
            geometry = ShapeGeometry(tag="path", attrs=OrderedDict([("d", path_data)]))
            return self._render_painted_geometry(
                geometry, style, depth, OrderedDict([("fill-rule", "evenodd")])
            )

        # No pre-flattened path: we cannot evaluate the boolean op ourselves.
        self.report.count_unsupported(
            f"shape:compound:{operation}",
            f"Compound boolean operation {operation!r} had no pre-flattened path; "
            "child geometry was preserved as a plain group and the boolean result is "
            "NOT accurate.",
        )
        children = child_nodes_of(shape) or child_nodes_of(node)
        body = self.render_nodes(children, depth + 1)
        if not body:
            return []
        return (
            [f'{pad}<g data-xd-unsupported-compound="{xml_escape(operation, True)}">']
            + body
            + [f"{pad}</g>"]
        )

    def _shape_geometry(self, shape: Dict[str, Any]) -> Optional[ShapeGeometry]:
        shape_type = str(shape.get("type") or "")
        if shape_type == "rect":
            x = to_float(shape.get("x"))
            y = to_float(shape.get("y"))
            width = to_float(shape.get("width"))
            height = to_float(shape.get("height"))
            attrs = OrderedDict(
                [
                    ("x", fmt_num(x)),
                    ("y", fmt_num(y)),
                    ("width", fmt_num(width)),
                    ("height", fmt_num(height)),
                ]
            )
            radius = shape.get("r")
            if isinstance(radius, list) and radius:
                values = [to_float(v) for v in radius]
                if any(values):
                    if len(set(values)) > 1:
                        if len(values) == 4:
                            # Exactly four radii in the proven AGC corner order:
                            # rendered exactly, as a path, not approximated.
                            return self._non_uniform_rect_geometry(
                                x, y, width, height, values
                            )
                        self.report.count_unsupported(
                            "rect:non-uniform-corner-radius",
                            "Non-uniform rectangle corner radii were approximated with "
                            "a single uniform SVG rx/ry.",
                        )
                    attrs["rx"] = fmt_num(values[0])
                    attrs["ry"] = fmt_num(values[0])
            elif radius is not None and to_float(radius) > 0:
                attrs["rx"] = fmt_num(radius)
                attrs["ry"] = fmt_num(radius)
            return ShapeGeometry("rect", attrs, (x, y), (width, height), True)

        if shape_type == "circle":
            cx = to_float(shape.get("cx"))
            cy = to_float(shape.get("cy"))
            r = to_float(shape.get("r"))
            attrs = OrderedDict(
                [("cx", fmt_num(cx)), ("cy", fmt_num(cy)), ("r", fmt_num(r))]
            )
            return ShapeGeometry(
                "circle", attrs, (cx - r, cy - r), (r * 2, r * 2), True
            )

        if shape_type == "ellipse":
            cx = to_float(shape.get("cx"))
            cy = to_float(shape.get("cy"))
            rx = to_float(shape.get("rx"))
            ry = to_float(shape.get("ry"))
            attrs = OrderedDict(
                [
                    ("cx", fmt_num(cx)),
                    ("cy", fmt_num(cy)),
                    ("rx", fmt_num(rx)),
                    ("ry", fmt_num(ry)),
                ]
            )
            return ShapeGeometry(
                "ellipse", attrs, (cx - rx, cy - ry), (rx * 2, ry * 2), True
            )

        if shape_type == "line":
            x1 = to_float(shape.get("x1"))
            y1 = to_float(shape.get("y1"))
            x2 = to_float(shape.get("x2"))
            y2 = to_float(shape.get("y2"))
            attrs = OrderedDict(
                [
                    ("x1", fmt_num(x1)),
                    ("y1", fmt_num(y1)),
                    ("x2", fmt_num(x2)),
                    ("y2", fmt_num(y2)),
                ]
            )
            return ShapeGeometry(
                "line",
                attrs,
                (min(x1, x2), min(y1, y2)),
                (abs(x2 - x1), abs(y2 - y1)),
            )

        if shape_type == "path":
            path_data = shape.get("path") or shape.get("d")
            if not isinstance(path_data, str):
                return None
            return ShapeGeometry("path", OrderedDict([("d", path_data)]))

        if shape_type == "polygon":
            points = shape.get("points")
            if isinstance(points, list) and points:
                rendered = " ".join(
                    f"{fmt_num(p.get('x'))},{fmt_num(p.get('y'))}"
                    for p in points
                    if isinstance(p, dict)
                )
                return ShapeGeometry("polygon", OrderedDict([("points", rendered)]))
            width = to_float(shape.get("width"))
            height = to_float(shape.get("height"))
            if width and height:
                self.report.count_unsupported(
                    "polygon:no-points",
                    "A polygon without explicit points was approximated by its "
                    "bounding rectangle.",
                )
                return ShapeGeometry(
                    "rect",
                    OrderedDict(
                        [
                            ("x", "0"),
                            ("y", "0"),
                            ("width", fmt_num(width)),
                            ("height", fmt_num(height)),
                        ]
                    ),
                    (0.0, 0.0),
                    (width, height),
                    True,
                )
        return None

    def _non_uniform_rect_geometry(
        self,
        x: float,
        y: float,
        width: float,
        height: float,
        values: Sequence[float],
    ) -> ShapeGeometry:
        """Exact geometry for a rectangle with four distinct corner radii.

        ``values`` is the raw AGC list in the proven ``(tl, tr, br, bl)`` order.
        The radii pass through the deterministic proportional-overlap policy and
        are then emitted as one closed path. The result is an ordinary
        ``ShapeGeometry``, so fill, stroke, inside-stroke clipping, opacity,
        filters, transforms, blend and outer clips all compose through the
        existing painted-geometry pipeline with no special-casing. Declared
        bounds stay reliable, so image fills keep laying out against the box.
        """
        radii, factor = scale_corner_radii(width, height, values)
        if factor < 1.0:
            self.report.count_handled(RECT_RADIUS_OVERLAP_SCALED_KEY)
            self.report.note_limitation(
                "Rectangle corner radii that overflow a side are reduced by one "
                "common proportional factor (min of w/(tl+tr), h/(tr+br), "
                "w/(bl+br), h/(tl+bl)) applied to all four corners. This is the "
                "renderer's deterministic overlap policy, validated against the "
                "current corpus; it is not a claim of parity with Adobe's "
                "undocumented internal Scenegraph capping algorithm."
            )
        self.report.count_handled(RECT_NON_UNIFORM_RADIUS_KEY)
        path_data = rounded_rect_path_data(x, y, width, height, radii)
        return ShapeGeometry(
            "path",
            OrderedDict([("d", path_data)]),
            (x, y),
            (width, height),
            True,
        )

    # -- paint ------------------------------------------------------------
    # -- inside-stroke emulation -------------------------------------------
    @staticmethod
    def _is_inside_solid_stroke(stroke: Any) -> bool:
        if not isinstance(stroke, dict):
            return False
        if str(stroke.get("type") or "") != "solid":
            return False
        align = stroke.get("align")
        return isinstance(align, str) and align.strip().lower() == "inside"

    @staticmethod
    def _is_closed_geometry(geometry: ShapeGeometry) -> bool:
        """Can this geometry safely act as its own interior clip region?

        Only shapes whose closure is provable from the emitted geometry qualify.
        A path must end in an explicit closepath; anything else (an open path, a
        line, an unrecognised tag) stays ineligible so the honest centred-stroke
        fallback applies instead.
        """
        if geometry.tag in INSIDE_STROKE_CLOSED_TAGS:
            return True
        if geometry.tag == "path":
            path_data = geometry.attrs.get("d")
            if isinstance(path_data, str):
                stripped = path_data.strip()
                return bool(stripped) and stripped[-1] in ("Z", "z")
        return False

    def _emit_inside_stroke_clip(
        self, geometry: ShapeGeometry, base_attrs: "OrderedDict[str, Any]"
    ) -> str:
        """Define the shape's own interior as a deterministic clip region."""
        clip_attrs = OrderedDict(base_attrs)
        fill_rule = clip_attrs.pop("fill-rule", None)
        if fill_rule is not None:
            # Mirror even-odd semantics so the clip covers the same interior.
            clip_attrs["clip-rule"] = fill_rule
        clip_id = self.doc.new_id("inside-stroke")
        self.doc.add_def(
            f'<clipPath id="{clip_id}" clipPathUnits="userSpaceOnUse">'
            f"<{geometry.tag} {attrs_to_string(clip_attrs)}/>"
            "</clipPath>"
        )
        return clip_id

    def _render_painted_geometry(
        self,
        geometry: ShapeGeometry,
        style: Dict[str, Any],
        depth: int,
        extra_attrs: "Optional[OrderedDict[str, Any]]" = None,
    ) -> List[str]:
        """Emit one XD shape, emulating inside-stroke alignment when eligible.

        SVG has no inside-stroke alignment. For a closed shape the exporter
        renders the fill once at the original geometry, then a stroke-only copy
        of the *same* geometry at double the XD stroke width, clipped to that
        geometry's interior - leaving exactly the inward half, i.e. the width XD
        asked for. Both elements sit inside the node's single existing wrapper,
        so the node transform, opacity, filter, blend and outer clip still apply
        exactly once to the composite.
        """
        pad = "  " * depth
        base: "OrderedDict[str, Any]" = OrderedDict(geometry.attrs)
        if extra_attrs:
            base.update(extra_attrs)

        stroke = style.get("stroke")
        emulate = self._is_inside_solid_stroke(stroke) and self._is_closed_geometry(
            geometry
        )

        if not emulate:
            # Byte-identical to the pre-I3-R2-I3 single-element path.
            attrs = OrderedDict(base)
            attrs.update(self._paint_attributes(style, geometry))
            return [f"{pad}<{geometry.tag} {attrs_to_string(attrs)}/>"]

        # Each paint helper runs exactly once, so pattern/gradient defs and their
        # report counters are not duplicated across the two elements.
        fill_attrs = self._fill_attributes(style.get("fill"), geometry)
        stroke_attrs = self._stroke_attributes(stroke, inside_emulated=True)
        clip_id = self._emit_inside_stroke_clip(geometry, base)

        fill_element = OrderedDict(base)
        fill_element.update(fill_attrs)

        stroke_element = OrderedDict(base)
        stroke_element["fill"] = "none"
        stroke_element.update(stroke_attrs)
        stroke_element["clip-path"] = f"url(#{clip_id})"
        stroke_element["data-xd-stroke-align"] = "inside"

        return [
            f"{pad}<{geometry.tag} {attrs_to_string(fill_element)}/>",
            f"{pad}<{geometry.tag} {attrs_to_string(stroke_element)}/>",
        ]

    def _paint_attributes(
        self, style: Dict[str, Any], geometry: ShapeGeometry
    ) -> "OrderedDict[str, Any]":
        attrs: "OrderedDict[str, Any]" = OrderedDict()
        attrs.update(self._fill_attributes(style.get("fill"), geometry))
        attrs.update(self._stroke_attributes(style.get("stroke")))
        return attrs

    def _fill_attributes(
        self, fill: Any, geometry: ShapeGeometry
    ) -> "OrderedDict[str, Any]":
        attrs: "OrderedDict[str, Any]" = OrderedDict()
        if not isinstance(fill, dict):
            attrs["fill"] = "none"
            return attrs

        fill_type = str(fill.get("type") or "")
        if fill_type in ("none", ""):
            attrs["fill"] = "none"
            return attrs

        if fill_type == "solid":
            css_color, alpha = color_to_css(fill.get("color"))
            attrs["fill"] = css_color or "#000000"
            if alpha != 1.0:
                attrs["fill-opacity"] = fmt_num(alpha, 1.0)
            self.report.count_handled("fill:solid")
            return attrs

        if fill_type == "pattern":
            pattern_id = self._build_pattern(fill, geometry)
            attrs["fill"] = f"url(#{pattern_id})" if pattern_id else "none"
            return attrs

        if fill_type == "gradient":
            gradient_id = self._build_gradient(fill)
            attrs["fill"] = f"url(#{gradient_id})" if gradient_id else "none"
            return attrs

        self.report.count_unsupported(
            f"fill:{fill_type}",
            f"Fill type {fill_type!r} is not supported in iteration I1; the shape was "
            "left unfilled.",
        )
        attrs["fill"] = "none"
        return attrs

    def _build_pattern(
        self, fill: Dict[str, Any], geometry: ShapeGeometry
    ) -> Optional[str]:
        self.report.pattern_fill_count += 1
        # style.fill.pattern may itself be a {"type":"pattern","pattern":{...}}
        # wrapper; normalize_pattern_payload descends to the real payload.
        pattern = normalize_pattern_payload(fill)
        if not isinstance(pattern, dict) or pattern is fill:
            self.report.unresolved_pattern_fill_count += 1
            self.report.count_unsupported(
                "fill:pattern:no-payload",
                "A pattern fill carried no resolvable inner pattern payload.",
            )
            return None

        uid = pattern_resource_uid(pattern)
        if not uid:
            self.report.unresolved_pattern_fill_count += 1
            self.report.count_unsupported(
                "fill:pattern:no-uid",
                "A pattern fill had no pattern.meta.ux.uid, so no image resource could "
                "be resolved.",
            )
            return None

        data_uri = self.loader.data_uri_for(uid)
        if not data_uri:
            self.report.unresolved_pattern_fill_count += 1
            self.report.count_unsupported("fill:pattern:missing-resource")
            return None

        ux = (pattern.get("meta") or {}).get("ux") or {}
        if not isinstance(ux, dict):
            ux = {}
        # The natural bitmap size is diagnostic metadata only. It must never
        # become the cover tile size: that was the I1 defect this repairs.
        natural_width = to_float(pattern.get("width"), 0.0)
        natural_height = to_float(pattern.get("height"), 0.0)
        offset_x = to_float(ux.get("offsetX", pattern.get("offsetX")), 0.0)
        offset_y = to_float(ux.get("offsetY", pattern.get("offsetY")), 0.0)

        mode, behavior_key = classify_scale_behavior(
            ux.get("scaleBehavior", pattern.get("scaleBehavior"))
        )
        self.report.count_scale_behavior(behavior_key)
        if mode == "unknown":
            self.report.count_unsupported(
                f"fill:pattern:scaleBehavior:{behavior_key}",
                f"Unknown XD image-fill scaleBehavior {behavior_key!r}; cover "
                "semantics were used as a documented deterministic fallback. The "
                "true behaviour was not guessed silently.",
            )
            mode = "cover"

        layout = self._image_fill_layout(
            geometry, mode, natural_width, natural_height, offset_x, offset_y
        )
        tile_x, tile_y, tile_width, tile_height, preserve, bounds_source = layout

        pattern_id = self.doc.new_id("pattern")
        # Pattern content coordinates are relative to the tile origin, so the
        # image sits at the tile's own (0, 0) while the tile itself is placed at
        # the shape's local paint bounds. Placing both at the bounds origin would
        # apply the offset twice.
        image_attrs = OrderedDict(
            [
                ("x", "0"),
                ("y", "0"),
                ("width", fmt_num(tile_width)),
                ("height", fmt_num(tile_height)),
                ("preserveAspectRatio", preserve),
                ("href", data_uri),
            ]
        )
        pattern_attrs = OrderedDict(
            [
                ("id", pattern_id),
                ("patternUnits", "userSpaceOnUse"),
                ("x", fmt_num(tile_x)),
                ("y", fmt_num(tile_y)),
                ("width", fmt_num(tile_width)),
                ("height", fmt_num(tile_height)),
            ]
        )
        self.doc.add_def(
            f"<pattern {attrs_to_string(pattern_attrs)}>"
            f"<image {attrs_to_string(image_attrs)}/>"
            "</pattern>"
        )
        self.report.note_pattern_fill(
            {
                "pattern_id": pattern_id,
                "uid": uid,
                "scale_behavior": behavior_key,
                "mode": mode,
                "natural_width": natural_width,
                "natural_height": natural_height,
                "offset_x": offset_x,
                "offset_y": offset_y,
                "bounds_source": bounds_source,
                "target_bounds": {
                    "x": tile_x,
                    "y": tile_y,
                    "width": tile_width,
                    "height": tile_height,
                },
                "preserve_aspect_ratio": preserve,
            }
        )
        self.report.resolved_pattern_fill_count += 1
        self.report.count_handled("fill:pattern")
        return pattern_id

    def _image_fill_layout(
        self,
        geometry: ShapeGeometry,
        mode: str,
        natural_width: float,
        natural_height: float,
        offset_x: float,
        offset_y: float,
    ) -> Tuple[float, float, float, float, str, str]:
        """Lay an image fill out against the painted shape's local bounds.

        Returns ``(tile_x, tile_y, tile_width, tile_height, preserveAspectRatio,
        bounds_source)``. XD image fills cover the *shape*, so the tile is the
        shape's bounds - not the natural bitmap box - and it is emitted once
        rather than tiled across a bitmap-sized coordinate space.

        Priority, highest first:

        1. reliable stored bounds (``rect``/``circle``/``ellipse``, and the
           generated non-uniform rounded rectangle) - unchanged;
        2. a ``path`` whose ``d`` is inside the strictly supported closed
           absolute ``M``/``L``/``C``/``Z`` subset, whose exact local bounds are
           derived by :func:`strict_absolute_mlc_z_bounds`;
        3. the pre-existing natural-bitmap / no-size fallbacks, verbatim.
        """
        origin_x, origin_y = geometry.origin
        box_width, box_height = geometry.size
        tile_x = origin_x + offset_x
        tile_y = origin_y + offset_y

        def fit_preserve() -> str:
            return (
                STRETCH_PRESERVE_ASPECT_RATIO
                if mode == "stretch"
                else COVER_PRESERVE_ASPECT_RATIO
            )

        if geometry.bounds_reliable and box_width > 0 and box_height > 0:
            return (
                tile_x,
                tile_y,
                box_width,
                box_height,
                fit_preserve(),
                "shape-bounds",
            )

        if geometry.tag == "path":
            derived = strict_absolute_mlc_z_bounds(geometry.attrs.get("d"))
            if derived is not None:
                derived_x, derived_y, derived_width, derived_height = derived
                if derived_width > 0 and derived_height > 0:
                    # Real geometry, exactly solved - so this shape gets proper
                    # cover/stretch semantics instead of the bitmap fallback.
                    self.report.count_handled(PATTERN_DERIVED_PATH_BOUNDS_KEY)
                    return (
                        derived_x + offset_x,
                        derived_y + offset_y,
                        derived_width,
                        derived_height,
                        fit_preserve(),
                        "derived-path-bounds",
                    )

        if natural_width > 0 and natural_height > 0:
            # No trustworthy shape bounds (e.g. a path fill): keep the pre-repair
            # behaviour rather than inventing a bounding-box parser, and say so.
            self.report.count_unsupported(
                "fill:pattern:no-shape-bounds",
                "An image fill was applied to geometry with no reliable local "
                "bounds; the natural bitmap box was used as the pattern tile, so "
                "cover semantics are NOT applied to this shape.",
            )
            return (
                tile_x,
                tile_y,
                natural_width,
                natural_height,
                STRETCH_PRESERVE_ASPECT_RATIO,
                "natural-bitmap-fallback",
            )

        self.report.count_unsupported(
            "fill:pattern:no-size",
            "A pattern fill declared no width/height and its shape exposed no "
            "reliable bounds; a unit tile with 'slice' aspect behaviour was used.",
        )
        return (
            tile_x,
            tile_y,
            box_width or 1.0,
            box_height or 1.0,
            COVER_PRESERVE_ASPECT_RATIO,
            "unavailable",
        )

    def _build_gradient(self, fill: Dict[str, Any]) -> Optional[str]:
        gradient = fill.get("gradient")
        if isinstance(gradient, dict) and isinstance(gradient.get("ref"), str):
            resolved = self.resources.gradient(gradient["ref"])
            if resolved is None:
                self.report.count_unsupported(
                    "fill:gradient:unresolved",
                    f"Gradient reference {gradient['ref']!r} was not found in AGC "
                    "resources.",
                )
                return None
            merged = dict(resolved)
            merged.update({k: v for k, v in gradient.items() if k != "ref"})
            gradient = merged
        if not isinstance(gradient, dict):
            self.report.count_unsupported(
                "fill:gradient:no-payload", "A gradient fill carried no payload."
            )
            return None

        stops = gradient.get("stops")
        stop_markup: List[str] = []
        if isinstance(stops, list):
            for stop in stops:
                if not isinstance(stop, dict):
                    continue
                css_color, color_alpha = color_to_css(stop.get("color"))
                alpha = clamp01(to_float(stop.get("a", stop.get("alpha")), color_alpha))
                stop_markup.append(
                    "<stop "
                    f'offset="{fmt_num(stop.get("offset"), 0.0)}" '
                    f'stop-color="{css_color or "#000000"}" '
                    f'stop-opacity="{fmt_num(alpha, 1.0)}"/>'
                )
        if not stop_markup:
            self.report.count_unsupported(
                "fill:gradient:no-stops", "A gradient fill declared no usable stops."
            )
            return None

        gradient_id = self.doc.new_id("gradient")
        gradient_type = str(gradient.get("type") or "linear")
        body = "".join(stop_markup)
        if gradient_type.startswith("radial"):
            attrs = OrderedDict(
                [
                    ("id", gradient_id),
                    ("cx", fmt_num(fill.get("cx", gradient.get("cx", 0.5)), 0.5)),
                    ("cy", fmt_num(fill.get("cy", gradient.get("cy", 0.5)), 0.5)),
                    ("r", fmt_num(fill.get("r", gradient.get("r", 0.5)), 0.5)),
                ]
            )
            self.doc.add_def(
                f"<radialGradient {attrs_to_string(attrs)}>{body}</radialGradient>"
            )
        else:
            attrs = OrderedDict(
                [
                    ("id", gradient_id),
                    ("x1", fmt_num(fill.get("x1", gradient.get("x1", 0)), 0.0)),
                    ("y1", fmt_num(fill.get("y1", gradient.get("y1", 0)), 0.0)),
                    ("x2", fmt_num(fill.get("x2", gradient.get("x2", 1)), 1.0)),
                    ("y2", fmt_num(fill.get("y2", gradient.get("y2", 0)), 0.0)),
                ]
            )
            self.doc.add_def(
                f"<linearGradient {attrs_to_string(attrs)}>{body}</linearGradient>"
            )
        self.report.gradient_fill_count += 1
        self.report.count_handled(f"fill:gradient:{gradient_type}")
        return gradient_id

    def _stroke_attributes(
        self, stroke: Any, inside_emulated: bool = False
    ) -> "OrderedDict[str, Any]":
        attrs: "OrderedDict[str, Any]" = OrderedDict()
        if not isinstance(stroke, dict):
            return attrs
        stroke_type = str(stroke.get("type") or "")
        if stroke_type in ("none", ""):
            return attrs
        if stroke_type != "solid":
            self.report.count_unsupported(
                f"stroke:{stroke_type}",
                f"Stroke type {stroke_type!r} is not supported in iteration I1.",
            )
            return attrs

        css_color, alpha = color_to_css(stroke.get("color"))
        attrs["stroke"] = css_color or "#000000"
        if alpha != 1.0:
            attrs["stroke-opacity"] = fmt_num(alpha, 1.0)
        width = stroke.get("width")
        if inside_emulated:
            # Double ONLY the width: the clip discards the outward half, so the
            # visible result is the original XD inside width. Dash lengths, dash
            # offset and opacity are deliberately left untouched.
            original = to_float(width, 1.0) if width is not None else 1.0
            attrs["stroke-width"] = fmt_num(original * INSIDE_STROKE_WIDTH_MULTIPLIER)
        elif width is not None:
            attrs["stroke-width"] = fmt_num(width, 1.0)
        cap = stroke.get("cap")
        if isinstance(cap, str) and cap:
            attrs["stroke-linecap"] = cap
        join = stroke.get("join")
        if isinstance(join, str) and join:
            attrs["stroke-linejoin"] = join
        miter = stroke.get("miterLimit")
        if miter is not None:
            attrs["stroke-miterlimit"] = fmt_num(miter, 4.0)
        dash = stroke.get("dash")
        if isinstance(dash, list) and dash:
            attrs["stroke-dasharray"] = " ".join(fmt_num(v) for v in dash)
        dash_offset = stroke.get("dashOffset")
        if dash_offset is not None:
            attrs["stroke-dashoffset"] = fmt_num(dash_offset, 0.0)

        align = stroke.get("align")
        if isinstance(align, str) and align not in ("", "center"):
            if inside_emulated:
                self.report.count_handled(f"stroke-align:{align}")
            else:
                self.report.count_unsupported(
                    f"stroke-align:{align}",
                    f"Stroke alignment {align!r} could not be emulated on this "
                    "geometry (it is not provably closed), so the stroke was "
                    "rendered centred on the path.",
                )
        self.report.count_handled("stroke:solid")
        return attrs

    # -- text -------------------------------------------------------------
    def _render_text_node(
        self, node: Dict[str, Any], style: Dict[str, Any], depth: int
    ) -> List[str]:
        text_payload = node.get("text")
        if not isinstance(text_payload, dict):
            self.report.count_unsupported(
                "text:missing", "A text node carried no 'text' payload."
            )
            return []
        raw_text = text_payload.get("rawText")
        if not isinstance(raw_text, str):
            raw_text = ""
        self.report.text_node_count += 1
        self.report.count_handled("text")

        pad = "  " * depth
        out: List[str] = []
        paragraphs = text_payload.get("paragraphs")

        if not isinstance(paragraphs, list) or not paragraphs:
            content = self._text_content(raw_text)
            if content.strip():
                out.append(self._text_element(pad, 0.0, 0.0, content, style, {}, {}))
            return out

        for paragraph in paragraphs:
            if not isinstance(paragraph, dict):
                continue
            paragraph_style = (
                paragraph.get("style")
                if isinstance(paragraph.get("style"), dict)
                else {}
            )
            for line in paragraph.get("lines", []) or []:
                segments = line if isinstance(line, list) else [line]
                for segment in segments:
                    if not isinstance(segment, dict):
                        continue
                    segment_style = (
                        segment.get("style")
                        if isinstance(segment.get("style"), dict)
                        else {}
                    )
                    start = segment.get("from")
                    end = segment.get("to")
                    if isinstance(start, int) and isinstance(end, int):
                        chunk = raw_text[start:end]
                    else:
                        chunk = raw_text
                    content = self._text_content(chunk)
                    if not content.strip():
                        continue
                    out.append(
                        self._text_element(
                            pad,
                            to_float(segment.get("x"), 0.0),
                            to_float(segment.get("y"), 0.0),
                            content,
                            style,
                            paragraph_style,
                            segment_style,
                        )
                    )
        return out

    def _text_content(self, chunk: str) -> str:
        """Normalize legacy brand text without touching IDs or node names."""
        if not self.options.normalize_brand:
            return chunk

        literal_count = chunk.count(BRAND_SOURCE_TOKEN)
        if literal_count:
            self.report.brand_replacement_count += literal_count
            chunk = chunk.replace(BRAND_SOURCE_TOKEN, BRAND_TARGET_TOKEN)

        # In several authentic XD artboards the visual brand mark is a vector
        # sibling and the remaining legacy word is stored as the exact text
        # chunk ``ictove``. Exact equality is deliberate: prose containing that
        # substring is not a brand node and must stay byte-for-byte unchanged.
        if chunk == BRAND_SEGMENTED_SOURCE_TOKEN:
            self.report.brand_replacement_count += 1
            chunk = BRAND_TARGET_TOKEN

        return chunk

    def _text_element(
        self,
        pad: str,
        x: float,
        y: float,
        content: str,
        node_style: Dict[str, Any],
        paragraph_style: Dict[str, Any],
        segment_style: Dict[str, Any],
    ) -> str:
        font = self._merge_font(node_style, paragraph_style, segment_style)
        family = str(font.get("postscriptName") or font.get("family") or "Tajawal")
        base_family = str(font.get("family") or family)
        self.report.note_font_request(base_family)
        if not self.fonts.is_embedded_family(base_family):
            if base_family not in self.report.non_embedded_fonts:
                self.report.non_embedded_fonts.append(base_family)
                self.report.warn(
                    f"Font family {base_family!r} is not embedded; rendering depends "
                    "on the fonts installed for the headless browser. Nothing was "
                    "downloaded or bundled."
                )

        fill_source = (
            segment_style.get("fill")
            or paragraph_style.get("fill")
            or node_style.get("fill")
        )
        css_color, alpha = color_to_css(
            fill_source.get("color") if isinstance(fill_source, dict) else None
        )

        text_attributes = (
            segment_style.get("textAttributes")
            or paragraph_style.get("textAttributes")
            or node_style.get("textAttributes")
            or {}
        )
        if not isinstance(text_attributes, dict):
            text_attributes = {}
        align = str(text_attributes.get("paragraphAlign") or "left").lower()
        anchor = {"left": "start", "center": "middle", "right": "end"}.get(align)
        if anchor is None:
            anchor = "start"
            if align not in ("", "justify"):
                self.report.count_unsupported(
                    f"text-align:{align}",
                    f"Text alignment {align!r} was approximated with "
                    "text-anchor=start.",
                )

        font_families = [f"'{family}'"]
        if base_family and base_family != family:
            font_families.append(f"'{base_family}'")
        if self.fonts.is_embedded_family(base_family):
            font_families.append("'Tajawal'")
        font_families.append("sans-serif")

        attrs = OrderedDict(
            [
                ("x", fmt_num(x)),
                ("y", fmt_num(y)),
                ("font-family", ", ".join(font_families)),
                ("font-size", fmt_num(font.get("size"), 16.0)),
                ("font-weight", str(font_weight_for_style_name(font.get("style")))),
                ("fill", css_color or "#000000"),
                ("text-anchor", anchor),
                ("xml:space", "preserve"),
            ]
        )
        if alpha != 1.0:
            attrs["fill-opacity"] = fmt_num(alpha, 1.0)
        if "italic" in str(font.get("style") or "").lower():
            attrs["font-style"] = "italic"
        letter_spacing = text_attributes.get("letterSpacing")
        if letter_spacing:
            # XD stores letter spacing in 1/1000 em.
            attrs["letter-spacing"] = fmt_num(
                to_float(letter_spacing) * to_float(font.get("size"), 16.0) / 1000.0
            )
        # Arabic runs are emitted verbatim; bidi ordering is the browser's job.
        return f"{pad}<text {attrs_to_string(attrs)}>{xml_escape(content)}</text>"

    @staticmethod
    def _merge_font(*styles: Dict[str, Any]) -> Dict[str, Any]:
        merged: Dict[str, Any] = {}
        for style in styles:
            font = style.get("font") if isinstance(style, dict) else None
            if isinstance(font, dict):
                merged.update(font)
        return merged


# ---------------------------------------------------------------------------
# SVG assembly.
# ---------------------------------------------------------------------------


class SvgExporter:
    """Turns one artboard's AGC document into a self-contained SVG string."""

    def __init__(
        self,
        package: XdPackage,
        artboard: ManifestArtboard,
        report: ExportReport,
        fonts: FontEmbedder,
        options: RenderOptions,
    ) -> None:
        self.package = package
        self.artboard = artboard
        self.report = report
        self.fonts = fonts
        self.options = options

    def build(self) -> str:
        agc = self.package.read_artboard_agc(self.artboard)
        shared = self.package.read_shared_agc()
        if shared is None:
            self.report.warn(
                "No shared AGC (resources/graphics/graphicContent.agc) was found; "
                "syncRef nodes can only resolve against this artboard."
            )

        resources = AgcResourceIndex(agc, shared)
        loader = ResourceLoader(self.package, self.report)
        document = SvgDocument()
        root_children = self._artboard_children(agc)
        # The calibrated soft-light hoist targets an *ancestor* group, which the
        # renderer emits before it reaches the blended node, so the decision has
        # to be made in a pre-pass over the whole artboard tree.
        blend_plan = BlendHoistPlanner().plan(root_children)
        renderer = AgcRenderer(
            document,
            resources,
            loader,
            self.fonts,
            self.report,
            self.options,
            blend_plan,
        )

        artboard_entry = self._artboard_entry(agc)
        origin_x, origin_y, origin_source = self._viewbox_origin(artboard_entry)
        width = self.artboard.width or to_float(
            (artboard_entry or {}).get("width"), 0.0
        )
        height = self.artboard.height or to_float(
            (artboard_entry or {}).get("height"), 0.0
        )
        if width <= 0 or height <= 0:
            raise XdExportError(
                f"Artboard {self.artboard.name!r} has a non-positive canonical size "
                f"({width}x{height})."
            )

        self.report.svg_width = width
        self.report.svg_height = height
        self.report.viewbox_origin_source = origin_source
        view_box = (
            f"{fmt_num(origin_x)} {fmt_num(origin_y)} "
            f"{fmt_num(width)} {fmt_num(height)}"
        )
        self.report.viewbox = view_box

        body = renderer.render_nodes(root_children, 3)
        background = self._background_markup(
            artboard_entry, origin_x, origin_y, width, height
        )

        clip_id = document.new_id("artboard")
        document.add_def(
            f'<clipPath id="{clip_id}" clipPathUnits="userSpaceOnUse">'
            f'<rect x="{fmt_num(origin_x)}" y="{fmt_num(origin_y)}" '
            f'width="{fmt_num(width)}" height="{fmt_num(height)}"/>'
            "</clipPath>"
        )

        font_css = self.fonts.css()
        lines: List[str] = ['<?xml version="1.0" encoding="UTF-8"?>']
        lines.append(
            '<svg xmlns="http://www.w3.org/2000/svg" '
            'xmlns:xlink="http://www.w3.org/1999/xlink" version="1.1" '
            f'width="{fmt_num(width)}" height="{fmt_num(height)}" '
            f'viewBox="{view_box}" preserveAspectRatio="xMidYMid meet" '
            'style="overflow:hidden">'
        )
        lines.append(
            f"  <!-- Generated by Merzox xd_reference_exporter ({EXPORTER_ITERATION}). "
            f"Artboard: {xml_escape(self.artboard.name)} -->"
        )
        lines.append("  <defs>")
        if font_css:
            lines.append(f'    <style type="text/css"><![CDATA[{font_css}]]></style>')
        defs_markup = document.defs_markup("    ")
        if defs_markup:
            lines.append(defs_markup)
        lines.append("  </defs>")
        lines.append(f'  <g clip-path="url(#{clip_id})">')
        if background:
            lines.append(f"    {background}")
        lines.extend(body)
        lines.append("  </g>")
        lines.append("</svg>")
        return "\n".join(lines) + "\n"

    # -- AGC structure helpers -------------------------------------------
    def _artboard_entry(self, agc: Dict[str, Any]) -> Optional[Dict[str, Any]]:
        artboards = agc.get("artboards")
        if not isinstance(artboards, dict):
            return None
        leaf = self.artboard.path.rsplit("/", 1)[-1]
        keys: List[Any] = [leaf, self.artboard.manifest_id]
        if isinstance(self.artboard.manifest_id, str):
            keys.append(f"artboard-{self.artboard.manifest_id}")
        for key in keys:
            if isinstance(key, str) and isinstance(artboards.get(key), dict):
                return artboards[key]
        for value in artboards.values():
            if isinstance(value, dict):
                return value
        return None

    def _artboard_children(self, agc: Dict[str, Any]) -> List[Dict[str, Any]]:
        children = agc.get("children")
        if not isinstance(children, list):
            self.report.warn("AGC root has no 'children' array; nothing was rendered.")
            return []
        collected: List[Dict[str, Any]] = []
        for child in children:
            if not isinstance(child, dict):
                continue
            if child.get("type") == "artboard" or isinstance(
                child.get("artboard"), dict
            ):
                collected.extend(child_nodes_of(child))
            else:
                collected.append(child)
        return collected

    def _viewbox_origin(
        self, artboard_entry: Optional[Dict[str, Any]]
    ) -> Tuple[float, float, str]:
        """Pick the coordinate-space origin the AGC children actually live in.

        The AGC ``artboards`` entry declares the origin of the space the child
        transforms are expressed in. Preferring it avoids subtracting the
        document offset twice when those transforms are already global.
        """
        if isinstance(artboard_entry, dict) and (
            "x" in artboard_entry or "y" in artboard_entry
        ):
            agc_x = to_float(artboard_entry.get("x"), 0.0)
            agc_y = to_float(artboard_entry.get("y"), 0.0)
            if (agc_x, agc_y) != (self.artboard.x, self.artboard.y):
                self.report.warn(
                    f"AGC artboard origin ({fmt_num(agc_x)}, {fmt_num(agc_y)}) differs "
                    f"from the manifest bounds origin ({fmt_num(self.artboard.x)}, "
                    f"{fmt_num(self.artboard.y)}). The AGC origin was used for the "
                    "viewBox because child transforms are expressed in that space."
                )
            return agc_x, agc_y, "agc_artboard_entry"
        return self.artboard.x, self.artboard.y, "manifest_bounds"

    def _background_markup(
        self,
        artboard_entry: Optional[Dict[str, Any]],
        x: float,
        y: float,
        width: float,
        height: float,
    ) -> Optional[str]:
        if not isinstance(artboard_entry, dict):
            return None
        style = artboard_entry.get("style")
        fill = style.get("fill") if isinstance(style, dict) else None
        if not isinstance(fill, dict) or str(fill.get("type")) != "solid":
            return None
        css_color, alpha = color_to_css(fill.get("color"))
        if not css_color:
            return None
        attrs = OrderedDict(
            [
                ("data-xd-role", "artboard-background"),
                ("x", fmt_num(x)),
                ("y", fmt_num(y)),
                ("width", fmt_num(width)),
                ("height", fmt_num(height)),
                ("fill", css_color),
            ]
        )
        if alpha != 1.0:
            attrs["fill-opacity"] = fmt_num(alpha, 1.0)
        return f"<rect {attrs_to_string(attrs)}/>"


# ---------------------------------------------------------------------------
# Browser discovery + PNG rendering.
# ---------------------------------------------------------------------------


class BrowserLocator:
    """Finds an installed Chromium-family browser: Edge first, then Chrome."""

    RELATIVE_CANDIDATES = (
        ("Microsoft Edge", r"Microsoft\Edge\Application\msedge.exe"),
        ("Google Chrome", r"Google\Chrome\Application\chrome.exe"),
    )
    ENV_ROOTS = ("ProgramFiles", "ProgramFiles(x86)", "LOCALAPPDATA")
    POSIX_CANDIDATES = (
        "/usr/bin/microsoft-edge",
        "/usr/bin/google-chrome",
        "/usr/bin/chromium",
        "/usr/bin/chromium-browser",
        "/Applications/Microsoft Edge.app/Contents/MacOS/Microsoft Edge",
        "/Applications/Google Chrome.app/Contents/MacOS/Google Chrome",
    )
    PATH_CANDIDATES = ("msedge", "google-chrome", "chrome", "chromium")

    @classmethod
    def candidates(cls) -> List[Path]:
        found: List[Path] = []
        override = os.environ.get("MERZOX_XD_BROWSER")
        if override:
            found.append(Path(override))
        # Edge is preferred, so every Edge root is enumerated before Chrome.
        for _label, relative in cls.RELATIVE_CANDIDATES:
            for env_name in cls.ENV_ROOTS:
                root = os.environ.get(env_name)
                if root:
                    found.append(Path(root) / relative)
        found.extend(Path(p) for p in cls.POSIX_CANDIDATES)
        deduped: List[Path] = []
        for path in found:
            if path not in deduped:
                deduped.append(path)
        return deduped

    @classmethod
    def find(cls, explicit: Optional[str] = None) -> Path:
        if explicit:
            path = Path(explicit)
            if not path.is_file():
                raise XdExportError(f"Explicit browser path does not exist: {path}")
            return path
        for candidate in cls.candidates():
            try:
                if candidate.is_file():
                    return candidate
            except OSError:  # pragma: no cover - unusual path permissions
                continue
        for name in cls.PATH_CANDIDATES:
            resolved = shutil.which(name)
            if resolved:
                return Path(resolved)
        raise XdExportError(
            "No Microsoft Edge or Google Chrome installation was found. Searched "
            "ProgramFiles, ProgramFiles(x86), LOCALAPPDATA and PATH. Set the "
            "MERZOX_XD_BROWSER environment variable or pass --browser."
        )


class PngRenderer:
    """Screenshots the generated SVG with headless Edge/Chrome."""

    def __init__(self, browser: Path, report: ExportReport, timeout: int = 120) -> None:
        self.browser = browser
        self.report = report
        self.timeout = timeout

    def render(
        self, svg_path: Path, png_path: Path, width: float, height: float
    ) -> None:
        svg_path = svg_path.resolve()
        png_path = png_path.resolve()
        png_path.parent.mkdir(parents=True, exist_ok=True)
        if png_path.exists():
            png_path.unlink()

        profile_dir = tempfile.mkdtemp(prefix="merzox-xd-profile-")
        command = [
            str(self.browser),
            "--headless=new",
            "--disable-gpu",
            "--hide-scrollbars",
            "--no-first-run",
            "--disable-extensions",
            "--force-device-scale-factor=1",
            f"--user-data-dir={profile_dir}",
            f"--window-size={int(round(width))},{int(round(height))}",
            f"--screenshot={png_path}",
            svg_path.as_uri(),
        ]
        try:
            completed = subprocess.run(
                command,
                stdout=subprocess.PIPE,
                stderr=subprocess.PIPE,
                timeout=self.timeout,
                check=False,
            )
            self.report.browser_return_code = completed.returncode
            if completed.returncode != 0:
                stderr = completed.stderr.decode("utf-8", errors="replace").strip()
                raise XdExportError(
                    f"Browser exited with code {completed.returncode}.\n{stderr[:2000]}"
                )
            if not png_path.is_file() or png_path.stat().st_size == 0:
                raise XdExportError(
                    f"Browser reported success but produced no PNG at {png_path}."
                )
        except subprocess.TimeoutExpired as exc:
            self.report.browser_return_code = -1
            raise XdExportError(
                f"Browser timed out after {self.timeout}s while rendering {svg_path}."
            ) from exc
        finally:
            shutil.rmtree(profile_dir, ignore_errors=True)


# ---------------------------------------------------------------------------
# Orchestration.
# ---------------------------------------------------------------------------


@dataclass
class ExportResult:
    svg: str
    report: Dict[str, Any]
    artboard: ManifestArtboard


def default_font_path() -> Path:
    """``<repo>/assets/fonts/Tajawal-Regular.ttf`` relative to this script."""
    return Path(__file__).resolve().parents[2] / DEFAULT_FONT_RELATIVE_PATH


# -- artboard selection ------------------------------------------------------


def resolve_selector(
    artboard_name: Optional[str] = None,
    artboard_id: Optional[str] = None,
    artboard_path: Optional[str] = None,
) -> str:
    """Validate that exactly one artboard selector was supplied."""
    active = [
        label
        for label, value in (
            ("artboard_name", artboard_name),
            ("artboard_id", artboard_id),
            ("artboard_path", artboard_path),
        )
        if value is not None
    ]
    if not active:
        raise XdExportError(
            "No artboard selector given. Supply exactly one of artboard_name, "
            "artboard_id or artboard_path."
        )
    if len(active) > 1:
        raise XdExportError(
            "Exactly one artboard selector may be used, but "
            f"{len(active)} were given: {', '.join(active)}."
        )
    return active[0]


def select_artboard(
    package: XdPackage,
    artboard_name: Optional[str] = None,
    artboard_id: Optional[str] = None,
    artboard_path: Optional[str] = None,
) -> ManifestArtboard:
    """Resolve one artboard from exactly one selector.

    The manifest id is the canonical machine selector: it is unique across all
    artboards. The artwork path is a stable secondary selector. The human name is
    convenient but may be shared by several artboards, in which case the lookup
    deliberately fails closed rather than guessing.
    """
    selector = resolve_selector(artboard_name, artboard_id, artboard_path)
    if selector == "artboard_id":
        return package.find_artboard_by_manifest_id(str(artboard_id))
    if selector == "artboard_path":
        return package.find_artboard_by_path(str(artboard_path))
    return package.find_artboard_by_exact_name(str(artboard_name))


# -- deterministic batch output naming ---------------------------------------


def slugify_artboard_name(name: Any) -> str:
    """Deterministic, Unicode-preserving slug of a canonical artboard name.

    Arabic (and any other) letters and digits survive verbatim; punctuation and
    whitespace collapse to single hyphens; leading/trailing hyphens are trimmed.
    A name with nothing slug-able falls back to ``artboard``.
    """
    out: List[str] = []
    for char in str(name if name is not None else ""):
        if char.isalnum():
            out.append(char)
        elif out and out[-1] != "-":
            out.append("-")
    slug = "".join(out).strip("-")
    return slug or ARTBOARD_SLUG_FALLBACK


def artboard_output_stem(index: int, artboard: ManifestArtboard) -> str:
    """``NNN--<slug>--<first8-manifest-id>`` for a 1-based manifest index.

    The index alone already guarantees uniqueness across a manifest; the slug and
    id fragment make the filename identifiable when names collide (the real
    package has 112 artboards but only 105 distinct names).
    """
    identifier = artboard.manifest_id if isinstance(artboard.manifest_id, str) else ""
    fragment = identifier.strip().lower()[:ARTBOARD_STEM_ID_LENGTH] or "noid"
    return f"{index:03d}--{slugify_artboard_name(artboard.name)}--{fragment}"


def prepare_batch_output_dir(output_dir: "os.PathLike[str] | str") -> Path:
    """Fail closed rather than mixing a new corpus into existing output."""
    path = Path(output_dir)
    if path.exists():
        if not path.is_dir():
            raise XdExportError(
                f"--output-dir {path} exists but is not a directory."
            )
        existing = sorted(entry.name for entry in path.iterdir())
        if existing:
            preview = ", ".join(existing[:5])
            more = f" (+{len(existing) - 5} more)" if len(existing) > 5 else ""
            raise XdExportError(
                f"--output-dir {path} is not empty ({len(existing)} entries: "
                f"{preview}{more}). Refusing to mix a new batch with existing files; "
                "point at a new directory or clear that one yourself."
            )
        return path
    path.mkdir(parents=True)
    return path


def export_artboard(
    xd_path: "os.PathLike[str] | str",
    artboard_name: Optional[str] = None,
    output_svg: "os.PathLike[str] | str | None" = None,
    output_png: "os.PathLike[str] | str | None" = None,
    report_json: "os.PathLike[str] | str | None" = None,
    normalize_brand: bool = False,
    font_path: "os.PathLike[str] | str | None" = None,
    browser_path: Optional[str] = None,
    render_png: bool = True,
    *,
    artboard_id: Optional[str] = None,
    artboard_path: Optional[str] = None,
) -> ExportResult:
    """Export one artboard to SVG (+ optional PNG) and return the report.

    Exactly one selector must be supplied: ``artboard_name`` (positional, kept
    for backwards compatibility), ``artboard_id`` or ``artboard_path``. The
    report always carries all three canonical identity fields regardless of
    which selector was used.
    """
    resolve_selector(artboard_name, artboard_id, artboard_path)

    report = ExportReport()
    report.source_xd = str(Path(xd_path).resolve())
    report.brand_normalization_enabled = bool(normalize_brand)
    report.note_limitation(
        "This is an engineering reference exporter, not Adobe XD. No pixel-perfect "
        f"fidelity is claimed for {EXPORTER_ITERATION}; only the Splash artboard "
        "has been calibrated against the authentic XD preview so far."
    )

    resolved_font = Path(font_path) if font_path else default_font_path()
    fonts = FontEmbedder(resolved_font, report)
    options = RenderOptions(normalize_brand=bool(normalize_brand))

    with XdPackage(xd_path) as package:
        artboard = select_artboard(
            package,
            artboard_name=artboard_name,
            artboard_id=artboard_id,
            artboard_path=artboard_path,
        )
        report.selected_artboard_name = artboard.name
        report.selected_artboard_path = artboard.path
        report.selected_artboard_id = artboard.manifest_id
        report.artboard_bounds = artboard.bounds_dict()

        svg = SvgExporter(package, artboard, report, fonts, options).build()

    if output_svg is not None:
        svg_path = Path(output_svg)
        if str(svg_path.parent) not in ("", "."):
            svg_path.parent.mkdir(parents=True, exist_ok=True)
        svg_path.write_text(svg, encoding="utf-8")
        report.output_svg = str(svg_path.resolve())

        if render_png and output_png is not None:
            browser = BrowserLocator.find(browser_path)
            report.browser_path = str(browser)
            PngRenderer(browser, report).render(
                svg_path, Path(output_png), report.svg_width, report.svg_height
            )
            report.output_png = str(Path(output_png).resolve())
    elif render_png and output_png is not None:
        raise XdExportError("--output-png requires --output-svg.")

    report_dict = report.to_dict()
    if report_json is not None:
        report_path = Path(report_json)
        if str(report_path.parent) not in ("", "."):
            report_path.parent.mkdir(parents=True, exist_ok=True)
        report_path.write_text(
            json.dumps(report_dict, indent=2, ensure_ascii=False) + "\n",
            encoding="utf-8",
        )

    return ExportResult(svg=svg, report=report_dict, artboard=artboard)


def export_all_artboards(
    xd_path: "os.PathLike[str] | str",
    output_dir: "os.PathLike[str] | str",
    normalize_brand: bool = False,
    font_path: "os.PathLike[str] | str | None" = None,
    browser_path: Optional[str] = None,
    render_png: bool = True,
    progress: Optional[Any] = None,
) -> Dict[str, Any]:
    """Export EVERY canonical artboard in manifest order into ``output_dir``.

    Iteration is over ``XdPackage.artboards()`` verbatim - entries are never
    deduplicated by human name, so artboards sharing a name are all exported.
    Each artboard is selected by its unique artwork path, so a duplicate name can
    never make one shadow another.

    Returns the batch summary dict (also written as ``batch-report.json``). A
    single artboard failing does not abort the run: it is recorded as failed and
    the remaining artboards are still attempted.
    """
    destination = prepare_batch_output_dir(output_dir)

    with XdPackage(xd_path) as package:
        artboards = package.artboards()

    entries: List[Dict[str, Any]] = []
    success_count = 0
    failure_count = 0

    for index, artboard in enumerate(artboards, start=1):
        stem = artboard_output_stem(index, artboard)
        svg_path = destination / f"{stem}.svg"
        png_path = destination / f"{stem}.png" if render_png else None
        report_path = destination / f"{stem}.report.json"

        entry: Dict[str, Any] = OrderedDict(
            [
                ("index", index),
                ("name", artboard.name),
                ("manifest_id", artboard.manifest_id),
                ("artboard_path", artboard.path),
                ("output_stem", stem),
                ("output_svg", None),
                ("output_png", None),
                ("report_json", None),
                ("status", BATCH_STATUS_FAILED),
                ("error", None),
                ("artboard_bounds", None),
                ("svg_width", None),
                ("svg_height", None),
                ("unsupported_node_counts", None),
                ("warning_count", None),
                ("pattern_fill_count", None),
                ("resolved_pattern_fill_count", None),
                ("brand_replacement_count", None),
                ("blend_mode_application_counts", None),
            ]
        )

        try:
            result = export_artboard(
                xd_path,
                artboard_path=artboard.path,
                output_svg=svg_path,
                output_png=png_path,
                report_json=report_path,
                normalize_brand=normalize_brand,
                font_path=font_path,
                browser_path=browser_path,
                render_png=render_png,
            )
        except Exception as exc:  # noqa: BLE001 - a batch must stay honest
            failure_count += 1
            entry["error"] = f"{type(exc).__name__}: {exc}"
        else:
            success_count += 1
            report = result.report
            # "success" describes artifact generation only. Unsupported renderer
            # features are honest report data, not an export failure.
            entry["status"] = BATCH_STATUS_SUCCESS
            entry["artboard_bounds"] = report["artboard_bounds"]
            entry["svg_width"] = report["svg_width"]
            entry["svg_height"] = report["svg_height"]
            entry["unsupported_node_counts"] = report["unsupported_node_counts"]
            entry["warning_count"] = len(report["warnings"])
            entry["pattern_fill_count"] = report["pattern_fill_count"]
            entry["resolved_pattern_fill_count"] = report["resolved_pattern_fill_count"]
            entry["brand_replacement_count"] = report["brand_replacement_count"]
            entry["blend_mode_application_counts"] = report[
                "blend_mode_application_counts"
            ]

        # Artifact paths are recorded relative to --output-dir so the summary is
        # reproducible across machines, and only when the file really exists.
        for key, path in (
            ("output_svg", svg_path),
            ("output_png", png_path),
            ("report_json", report_path),
        ):
            if path is not None and path.is_file():
                entry[key] = path.name

        entries.append(entry)
        if progress is not None:
            progress(entry)

    summary: Dict[str, Any] = OrderedDict(
        [
            ("schema", BATCH_REPORT_SCHEMA),
            ("iteration", EXPORTER_ITERATION),
            ("source_xd", str(Path(xd_path).resolve())),
            ("output_dir", str(destination.resolve())),
            ("normalize_merzox_brand", bool(normalize_brand)),
            ("skip_png", not render_png),
            ("artboard_count", len(artboards)),
            ("success_count", success_count),
            ("failure_count", failure_count),
            ("entries", entries),
        ]
    )
    (destination / BATCH_REPORT_FILENAME).write_text(
        json.dumps(summary, indent=2, ensure_ascii=False) + "\n", encoding="utf-8"
    )
    return summary


def build_arg_parser() -> argparse.ArgumentParser:
    parser = argparse.ArgumentParser(
        prog="xd_reference_exporter.py",
        description=(
            "Export one Adobe XD artboard to a self-contained SVG and a headless "
            f"browser PNG (Merzox UI golden reference, {EXPORTER_ITERATION})."
        ),
    )
    parser.add_argument("--xd", required=True, help="Path to the .xd package.")
    parser.add_argument(
        "--artboard-name",
        help=(
            "Exact canonical artboard name from the XD manifest. Convenient, but "
            "names may be shared by several artboards; ambiguous names fail closed."
        ),
    )
    parser.add_argument(
        "--artboard-id",
        help="Canonical manifest id (unique per artboard). The stable selector.",
    )
    parser.add_argument(
        "--artboard-path",
        help="Canonical artwork path, e.g. 'artwork/artboard-<uuid>'.",
    )
    parser.add_argument("--output-svg", help="Path of the SVG to write.")
    parser.add_argument("--output-png", help="Path of the PNG to write.")
    parser.add_argument("--report-json", help="Path of the JSON report to write.")
    parser.add_argument(
        "--all-artboards",
        action="store_true",
        help="Export every artboard in manifest order into --output-dir.",
    )
    parser.add_argument(
        "--output-dir",
        help="Destination directory for --all-artboards. Must be empty or absent.",
    )
    parser.add_argument(
        "--normalize-merzox-brand",
        action="store_true",
        help=(
            "Replace legacy rendered brand text with 'Merzox', including the "
            "literal 'Bictov' and the exact segmented logo tail 'ictove'. "
            "The XD package, node IDs and node names are never modified."
        ),
    )
    parser.add_argument("--font", help="Override the Tajawal TTF embedded in the SVG.")
    parser.add_argument("--browser", help="Explicit Edge/Chrome executable path.")
    parser.add_argument(
        "--list-artboards",
        action="store_true",
        help=(
            "Print name, manifest id, path and bounds for every artboard in "
            "manifest order, then exit."
        ),
    )
    parser.add_argument(
        "--skip-png",
        action="store_true",
        help="Generate the SVG and report without invoking a browser.",
    )
    return parser


def _validate_cli_modes(args: argparse.Namespace) -> None:
    """Reject ambiguous flag combinations instead of guessing intent."""
    selectors = [
        name
        for name, value in (
            ("--artboard-name", args.artboard_name),
            ("--artboard-id", args.artboard_id),
            ("--artboard-path", args.artboard_path),
        )
        if value is not None
    ]

    if args.all_artboards:
        if selectors:
            raise XdExportError(
                "--all-artboards exports every artboard and cannot be combined with "
                f"a single-artboard selector ({', '.join(selectors)})."
            )
        if not args.output_dir:
            raise XdExportError("--all-artboards requires --output-dir.")
        per_file = [
            name
            for name, value in (
                ("--output-svg", args.output_svg),
                ("--output-png", args.output_png),
                ("--report-json", args.report_json),
            )
            if value is not None
        ]
        if per_file:
            raise XdExportError(
                "--all-artboards writes deterministic filenames into --output-dir and "
                f"cannot be combined with {', '.join(per_file)}."
            )
        return

    if args.output_dir:
        raise XdExportError("--output-dir is only valid with --all-artboards.")

    if args.list_artboards:
        return

    if len(selectors) > 1:
        raise XdExportError(
            f"Exactly one artboard selector may be used; got {', '.join(selectors)}."
        )
    if not selectors:
        raise XdExportError(
            "No artboard selector given. Supply exactly one of --artboard-name, "
            "--artboard-id or --artboard-path (or use --list-artboards / "
            "--all-artboards)."
        )
    if not args.output_svg:
        raise XdExportError("--output-svg is required unless --list-artboards.")


def force_utf8_streams() -> None:
    """Emit CLI output as UTF-8 regardless of the host ANSI code page.

    Artboard names are Arabic. On Windows, ``sys.stdout``/``sys.stderr`` default
    to the console/ANSI code page (cp1256 here), so a diagnostic naming an
    artboard was written as cp1256 bytes. Anything decoding that stream as UTF-8
    saw invalid bytes and dropped them, turning ``'الرسائل'`` into ``''`` - the
    name was never actually lost, only mis-encoded on the way out.
    """
    for stream in (sys.stdout, sys.stderr):
        reconfigure = getattr(stream, "reconfigure", None)
        if reconfigure is None:
            continue  # e.g. a StringIO capture in tests: nothing to reconfigure
        try:
            reconfigure(encoding="utf-8", errors="backslashreplace")
        except (ValueError, OSError):  # pragma: no cover - exotic stream
            pass


def main(argv: Optional[Sequence[str]] = None) -> int:
    force_utf8_streams()
    args = build_arg_parser().parse_args(argv)

    try:
        _validate_cli_modes(args)

        if args.list_artboards:
            with XdPackage(args.xd) as package:
                for artboard in package.artboards():
                    print(
                        f"{artboard.name}\t{artboard.manifest_id}\t{artboard.path}\t"
                        f"{fmt_num(artboard.width)}x{fmt_num(artboard.height)}"
                    )
            return 0

        if args.all_artboards:
            summary = export_all_artboards(
                xd_path=args.xd,
                output_dir=args.output_dir,
                normalize_brand=args.normalize_merzox_brand,
                font_path=args.font,
                browser_path=args.browser,
                render_png=not args.skip_png,
                progress=lambda entry: print(
                    f"[{entry['index']:03d}] {entry['status']:>7}  "
                    f"{entry['output_stem']}"
                ),
            )
            print(f"artboards     : {summary['artboard_count']}")
            print(f"succeeded     : {summary['success_count']}")
            print(f"failed        : {summary['failure_count']}")
            print(f"output dir    : {summary['output_dir']}")
            print(f"batch report  : {BATCH_REPORT_FILENAME}")
            if summary["failure_count"]:
                for entry in summary["entries"]:
                    if entry["status"] != BATCH_STATUS_SUCCESS:
                        print(
                            f"  FAILED {entry['output_stem']}: {entry['error']}",
                            file=sys.stderr,
                        )
                return 1
            return 0

        result = export_artboard(
            xd_path=args.xd,
            artboard_name=args.artboard_name,
            artboard_id=args.artboard_id,
            artboard_path=args.artboard_path,
            output_svg=args.output_svg,
            output_png=args.output_png,
            report_json=args.report_json,
            normalize_brand=args.normalize_merzox_brand,
            font_path=args.font,
            browser_path=args.browser,
            render_png=not args.skip_png,
        )
    except XdExportError as exc:
        print(f"error: {exc}", file=sys.stderr)
        return 2

    report = result.report
    print(f"artboard      : {report['selected_artboard_name']}")
    print(f"manifest id   : {report['selected_artboard_id']}")
    print(f"artboard path : {report['selected_artboard_path']}")
    print(f"bounds        : {report['artboard_bounds']}")
    print(f"viewBox       : {report['viewbox']} ({report['viewbox_origin_source']})")
    print(f"svg           : {report['output_svg']}")
    print(f"png           : {report['output_png']}")
    print(
        f"browser       : {report['browser_path']} "
        f"(rc={report['browser_return_code']})"
    )
    print(f"text nodes    : {report['text_node_count']}")
    print(
        "pattern fills : "
        f"{report['resolved_pattern_fill_count']}/{report['pattern_fill_count']} "
        "resolved"
    )
    print(f"brand replaced: {report['brand_replacement_count']}")
    print(f"unsupported   : {report['unsupported_node_counts']}")
    print(f"warnings      : {len(report['warnings'])}")
    return 0


if __name__ == "__main__":  # pragma: no cover
    raise SystemExit(main())

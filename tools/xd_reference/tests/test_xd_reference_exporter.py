#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""Unit tests for the Merzox XD reference exporter (MERZOX-UI-GOLDEN-I3-R2-I1).

These tests never touch the real ``design.xd``. Every fixture is a minimal
``.xd`` ZIP package generated into a temporary directory, so the suite is
hermetic and does not require Adobe XD, a browser, or Pillow.
"""

from __future__ import annotations

import base64
import contextlib
import io
import json
from collections import OrderedDict
import subprocess
import sys
import tempfile
import unittest
import zipfile
from pathlib import Path
from typing import Any, Dict, List, Optional

MODULE_DIR = Path(__file__).resolve().parents[1]
if str(MODULE_DIR) not in sys.path:
    sys.path.insert(0, str(MODULE_DIR))

import xd_reference_exporter as xdref  # noqa: E402  (path set up above)


ARTBOARD_NAME = "سبلاش – 1"
OTHER_ARTBOARD_NAME = "سبلاش – 10"
ARTBOARD_WIDTH = 375
ARTBOARD_HEIGHT = 812

#: Smallest valid 1x1 PNG, used as a stand-in image resource blob.
TINY_PNG = base64.b64decode(
    "iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAYAAAAfFcSJAAAADUlEQVR42mP8z8BQDwAE"
    "hQGAhKmMIQAAAABJRU5ErkJggg=="
)

WHITE_FILL = {
    "type": "solid",
    "color": {"mode": "RGB", "value": {"r": 255, "g": 255, "b": 255}},
}


# ---------------------------------------------------------------------------
# Fixture helpers.
# ---------------------------------------------------------------------------


def solid_fill(r: int, g: int, b: int, alpha: float = 1.0) -> Dict[str, Any]:
    return {
        "type": "solid",
        "color": {"mode": "RGB", "value": {"r": r, "g": g, "b": b}, "alpha": alpha},
    }


def rect_node(
    x: float = 0,
    y: float = 0,
    width: float = 100,
    height: float = 100,
    style: Optional[Dict[str, Any]] = None,
    transform: Optional[Dict[str, Any]] = None,
    name: Optional[str] = None,
    node_id: str = "rect-1",
) -> Dict[str, Any]:
    node: Dict[str, Any] = {
        "type": "shape",
        "id": node_id,
        "shape": {"type": "rect", "x": x, "y": y, "width": width, "height": height},
        "style": style if style is not None else {"fill": solid_fill(18, 52, 86)},
    }
    if transform is not None:
        node["transform"] = transform
    if name is not None:
        node["name"] = name
    return node


def path_node(d: str = "M0 0 L10 10 Z", node_id: str = "path-1") -> Dict[str, Any]:
    return {
        "type": "shape",
        "id": node_id,
        "shape": {"type": "path", "path": d},
        "style": {"fill": solid_fill(255, 0, 0)},
    }


def text_node(
    raw_text: str = "Bictov app",
    name: Optional[str] = None,
    family: str = "Tajawal",
    postscript: str = "Tajawal-Bold",
    node_id: str = "text-1",
) -> Dict[str, Any]:
    node: Dict[str, Any] = {
        "type": "text",
        "id": node_id,
        "transform": {"a": 1, "b": 0, "c": 0, "d": 1, "tx": 20, "ty": 40},
        "style": {
            "font": {
                "family": family,
                "style": "Bold",
                "size": 24,
                "postscriptName": postscript,
            },
            "fill": solid_fill(0, 0, 0),
            "textAttributes": {"paragraphAlign": "center"},
        },
        "text": {
            "rawText": raw_text,
            "paragraphs": [
                {"lines": [[{"from": 0, "to": len(raw_text), "x": 0, "y": 0}]]}
            ],
        },
    }
    if name is not None:
        node["name"] = name
    return node


def build_xd(
    directory: Path,
    children: List[Dict[str, Any]],
    *,
    filename: str = "fixture.xd",
    agc_resources: Optional[Dict[str, Any]] = None,
    artboard_style: Optional[Dict[str, Any]] = None,
    blobs: Optional[Dict[str, bytes]] = None,
    shared_agc: Optional[Dict[str, Any]] = None,
    bounds: Any = (0, 0, ARTBOARD_WIDTH, ARTBOARD_HEIGHT),
) -> Path:
    """Write a minimal but structurally faithful ``.xd`` ZIP fixture."""
    x, y, width, height = bounds
    manifest = {
        "id": "root",
        "name": "manifest",
        "path": "/",
        "children": [
            {
                "path": "artwork",
                "children": [
                    {
                        "type": "artboard",
                        "id": "ab1",
                        "name": ARTBOARD_NAME,
                        "path": "artboard-ab1",
                        "uxdesign#bounds": {
                            "x": x,
                            "y": y,
                            "width": width,
                            "height": height,
                        },
                    },
                    {
                        "type": "artboard",
                        "id": "ab2",
                        "name": OTHER_ARTBOARD_NAME,
                        "path": "artboard-ab2",
                        "uxdesign#bounds": {
                            "x": 500,
                            "y": 0,
                            "width": 100,
                            "height": 200,
                        },
                    },
                ],
            },
            {"path": "resources", "children": []},
        ],
    }

    agc = {
        "version": "3.0.0",
        "artboards": {
            "artboard-ab1": {
                "x": x,
                "y": y,
                "width": width,
                "height": height,
                "style": artboard_style
                if artboard_style is not None
                else {"fill": WHITE_FILL},
            }
        },
        "resources": agc_resources if agc_resources is not None else {},
        "children": [
            {
                "type": "artboard",
                "id": "ab1",
                "artboard": {"ref": "artboard-ab1", "children": children},
            }
        ],
    }

    other_agc = {
        "version": "3.0.0",
        "artboards": {"artboard-ab2": {"x": 500, "y": 0, "width": 100, "height": 200}},
        "resources": {},
        "children": [
            {"type": "artboard", "id": "ab2", "artboard": {"children": []}}
        ],
    }

    xd_path = directory / filename
    with zipfile.ZipFile(xd_path, "w", zipfile.ZIP_DEFLATED) as archive:
        archive.writestr("mimetype", "application/vnd.adobe.xd")
        archive.writestr("manifest", json.dumps(manifest, ensure_ascii=False))
        archive.writestr(
            "artwork/artboard-ab1/graphics/graphicContent.agc",
            json.dumps(agc, ensure_ascii=False),
        )
        archive.writestr(
            "artwork/artboard-ab2/graphics/graphicContent.agc",
            json.dumps(other_agc, ensure_ascii=False),
        )
        if shared_agc is not None:
            archive.writestr(
                "resources/graphics/graphicContent.agc",
                json.dumps(shared_agc, ensure_ascii=False),
            )
        for name, payload in (blobs or {}).items():
            archive.writestr(name, payload)
    return xd_path


class ExporterTestCase(unittest.TestCase):
    """Shared temp workspace + a synthetic embeddable font."""

    def setUp(self) -> None:
        self._tmp = tempfile.TemporaryDirectory(prefix="merzox-xd-test-")
        self.tmp_path = Path(self._tmp.name)
        # A stand-in font file: FontEmbedder only base64-encodes the bytes, so a
        # real TTF is unnecessary and would make the test depend on repo assets.
        self.font_path = self.tmp_path / "Tajawal-Regular.ttf"
        self.font_path.write_bytes(b"\x00\x01\x00\x00merzox-test-font-payload")
        self.addCleanup(self._tmp.cleanup)

    def export(
        self,
        xd_path: Path,
        artboard_name: str = ARTBOARD_NAME,
        **kwargs: Any,
    ) -> xdref.ExportResult:
        kwargs.setdefault("font_path", self.font_path)
        return xdref.export_artboard(
            xd_path,
            artboard_name,
            output_svg=None,
            render_png=False,
            **kwargs,
        )


# ---------------------------------------------------------------------------
# 1-2: manifest lookup + bounds.
# ---------------------------------------------------------------------------


class TestArtboardLookup(ExporterTestCase):
    def test_exact_artboard_lookup(self) -> None:
        xd_path = build_xd(self.tmp_path, [rect_node()])
        with xdref.XdPackage(xd_path) as package:
            names = [ab.name for ab in package.artboards()]
            self.assertEqual(names, [ARTBOARD_NAME, OTHER_ARTBOARD_NAME])

            artboard = package.find_artboard_by_exact_name(ARTBOARD_NAME)
            self.assertEqual(artboard.name, ARTBOARD_NAME)
            self.assertEqual(artboard.path, "artwork/artboard-ab1")
            self.assertEqual(artboard.manifest_id, "ab1")
            self.assertEqual(
                artboard.agc_path,
                "artwork/artboard-ab1/graphics/graphicContent.agc",
            )

            # Lookup is exact: a prefix of the real name must not match.
            with self.assertRaises(xdref.XdExportError):
                package.find_artboard_by_exact_name("سبلاش")
            with self.assertRaises(xdref.XdExportError):
                package.find_artboard_by_exact_name("Splash - 1")

    def test_manifest_bounds_drive_svg_size(self) -> None:
        xd_path = build_xd(self.tmp_path, [rect_node()])
        result = self.export(xd_path)
        report = result.report

        self.assertEqual(
            report["artboard_bounds"],
            {"x": 0.0, "y": 0.0, "width": 375.0, "height": 812.0},
        )
        self.assertEqual(report["svg_width"], 375.0)
        self.assertEqual(report["svg_height"], 812.0)
        self.assertEqual(report["viewbox"], "0 0 375 812")
        self.assertIn('width="375"', result.svg)
        self.assertIn('height="812"', result.svg)
        self.assertIn('viewBox="0 0 375 812"', result.svg)
        self.assertIn("overflow:hidden", result.svg)

    def test_document_space_bounds_are_not_subtracted_twice(self) -> None:
        """Global child coordinates keep their values; the viewBox moves."""
        xd_path = build_xd(
            self.tmp_path,
            [rect_node(x=1000, y=500, width=10, height=10)],
            bounds=(1000, 500, ARTBOARD_WIDTH, ARTBOARD_HEIGHT),
        )
        result = self.export(xd_path)
        self.assertEqual(result.report["viewbox"], "1000 500 375 812")
        self.assertEqual(
            result.report["viewbox_origin_source"], "agc_artboard_entry"
        )
        self.assertIn('<rect x="1000" y="500" width="10" height="10"', result.svg)


# ---------------------------------------------------------------------------
# 3-5: transforms, geometry, solid fill.
# ---------------------------------------------------------------------------


class TestGeometryRendering(ExporterTestCase):
    def test_matrix_transform_rendering(self) -> None:
        xd_path = build_xd(
            self.tmp_path,
            [
                rect_node(
                    transform={"a": 1, "b": 0, "c": 0, "d": 1, "tx": 20, "ty": 30}
                )
            ],
        )
        result = self.export(xd_path)
        self.assertIn('transform="matrix(1 0 0 1 20 30)"', result.svg)

    def test_identity_transform_is_omitted(self) -> None:
        xd_path = build_xd(
            self.tmp_path,
            [rect_node(transform={"a": 1, "b": 0, "c": 0, "d": 1, "tx": 0, "ty": 0})],
        )
        result = self.export(xd_path)
        self.assertNotIn("matrix(", result.svg)

    def test_rect_and_path_rendering(self) -> None:
        xd_path = build_xd(
            self.tmp_path, [rect_node(x=5, y=6, width=30, height=40), path_node()]
        )
        result = self.export(xd_path)
        self.assertIn('<rect x="5" y="6" width="30" height="40"', result.svg)
        self.assertIn('<path d="M0 0 L10 10 Z"', result.svg)
        self.assertEqual(result.report["handled_node_counts"]["shape:rect"], 1)
        self.assertEqual(result.report["handled_node_counts"]["shape:path"], 1)

    def test_solid_rgb_fill(self) -> None:
        xd_path = build_xd(
            self.tmp_path,
            [rect_node(style={"fill": solid_fill(0x12, 0x34, 0x56)})],
        )
        result = self.export(xd_path)
        self.assertIn('fill="#123456"', result.svg)
        # The artboard background is painted directly from the AGC artboard
        # entry, so only the shape's own fill goes through the fill pipeline.
        self.assertEqual(result.report["handled_node_counts"]["fill:solid"], 1)
        self.assertIn('data-xd-role="artboard-background"', result.svg)

    def test_solid_stroke_attributes(self) -> None:
        xd_path = build_xd(
            self.tmp_path,
            [
                rect_node(
                    style={
                        "fill": {"type": "none"},
                        "stroke": {
                            "type": "solid",
                            "color": {"mode": "RGB", "value": {"r": 0, "g": 0, "b": 0}},
                            "width": 2,
                            "cap": "round",
                            "join": "bevel",
                            "dash": [4, 2],
                            # 'outside' has no emulation and stays unsupported;
                            # 'inside' emulation is covered by its own suite.
                            "align": "outside",
                        },
                    }
                )
            ],
        )
        result = self.export(xd_path)
        self.assertIn('stroke="#000000"', result.svg)
        self.assertIn('stroke-width="2"', result.svg)
        self.assertIn('stroke-linecap="round"', result.svg)
        self.assertIn('stroke-linejoin="bevel"', result.svg)
        self.assertIn('stroke-dasharray="4 2"', result.svg)
        # Outside alignment has no SVG equivalent: reported, not faked.
        self.assertIn(
            "stroke-align:outside", result.report["unsupported_node_counts"]
        )

    def test_opacity_is_applied_to_wrapper(self) -> None:
        xd_path = build_xd(
            self.tmp_path,
            [rect_node(style={"fill": solid_fill(0, 0, 0), "opacity": 0.5})],
        )
        result = self.export(xd_path)
        self.assertIn('opacity="0.5"', result.svg)


# ---------------------------------------------------------------------------
# 6-8: pattern / image fills.
# ---------------------------------------------------------------------------


class TestPatternFills(ExporterTestCase):
    UID = "image-uid-1"

    def _inner_pattern(self) -> Dict[str, Any]:
        return {
            "width": 100,
            "height": 100,
            "meta": {"ux": {"uid": self.UID, "offsetX": -5, "offsetY": -10}},
        }

    def test_pattern_wrapper_normalization(self) -> None:
        inner = self._inner_pattern()

        direct = {"type": "pattern", "pattern": inner}
        wrapped = {"type": "pattern", "pattern": {"type": "pattern", "pattern": inner}}

        self.assertIs(xdref.normalize_pattern_payload(direct), inner)
        self.assertIs(xdref.normalize_pattern_payload(wrapped), inner)
        self.assertIs(xdref.normalize_pattern_payload(inner), inner)

        # The uid never lives on the outer wrapper.
        self.assertIsNone(xdref.pattern_resource_uid(direct))
        self.assertIsNone(xdref.pattern_resource_uid(wrapped))
        self.assertEqual(xdref.pattern_resource_uid(inner), self.UID)

    def test_pattern_uid_resolves_to_resources_entry(self) -> None:
        fill = {"type": "pattern", "pattern": self._inner_pattern()}
        xd_path = build_xd(
            self.tmp_path,
            [rect_node(style={"fill": fill})],
            blobs={f"resources/{self.UID}": TINY_PNG},
        )
        result = self.export(xd_path)
        report = result.report

        self.assertEqual(report["pattern_fill_count"], 1)
        self.assertEqual(report["resolved_pattern_fill_count"], 1)
        self.assertEqual(report["unresolved_pattern_fill_count"], 0)
        self.assertEqual(report["resource_ids_used"], [self.UID])
        self.assertIn('fill="url(#mxg-pattern-1)"', result.svg)
        # offsetX/offsetY are preserved relative to the shape origin.
        self.assertIn(
            '<pattern id="mxg-pattern-1" patternUnits="userSpaceOnUse" '
            'x="-5" y="-10" width="100" height="100">',
            result.svg,
        )

    def test_double_wrapped_pattern_also_resolves(self) -> None:
        fill = {
            "type": "pattern",
            "pattern": {"type": "pattern", "pattern": self._inner_pattern()},
        }
        xd_path = build_xd(
            self.tmp_path,
            [rect_node(style={"fill": fill})],
            blobs={f"resources/{self.UID}": TINY_PNG},
        )
        result = self.export(xd_path)
        self.assertEqual(result.report["resolved_pattern_fill_count"], 1)
        self.assertEqual(result.report["resource_ids_used"], [self.UID])

    def test_image_resource_data_uri_generation(self) -> None:
        fill = {"type": "pattern", "pattern": self._inner_pattern()}
        xd_path = build_xd(
            self.tmp_path,
            [rect_node(style={"fill": fill})],
            blobs={f"resources/{self.UID}": TINY_PNG},
        )
        result = self.export(xd_path)

        expected = "data:image/png;base64," + base64.b64encode(TINY_PNG).decode("ascii")
        self.assertIn(expected, result.svg)
        self.assertEqual(xdref.bytes_to_data_uri(TINY_PNG), expected)
        # I2-R1: an image fill with no declared scaleBehavior uses Adobe's
        # default cover semantics, not the natural-bitmap stretch of I1.
        self.assertIn('preserveAspectRatio="xMidYMid slice"', result.svg)
        self.assertEqual(
            result.report["pattern_scale_behavior_counts"],
            {xdref.SCALE_BEHAVIOR_UNSPECIFIED: 1},
        )

    def test_missing_pattern_resource_is_reported(self) -> None:
        fill = {"type": "pattern", "pattern": self._inner_pattern()}
        xd_path = build_xd(self.tmp_path, [rect_node(style={"fill": fill})])
        result = self.export(xd_path)

        self.assertEqual(result.report["pattern_fill_count"], 1)
        self.assertEqual(result.report["unresolved_pattern_fill_count"], 1)
        self.assertIn(
            "fill:pattern:missing-resource",
            result.report["unsupported_node_counts"],
        )
        self.assertTrue(result.report["warnings"])


# ---------------------------------------------------------------------------
# I2-R1: shape-bound image-fill geometry + scale-behavior reporting.
# ---------------------------------------------------------------------------


class TestImageFillGeometry(ExporterTestCase):
    """Image fills must cover the painted shape, not the natural bitmap box."""

    UID = "98578658e496669a0df69fdd35cc42fe"

    def pattern_fill(
        self,
        scale_behavior: Optional[str] = "fill",
        natural: Any = (1600, 1600),
        offset: Optional[Any] = None,
    ) -> Dict[str, Any]:
        ux: Dict[str, Any] = {"uid": self.UID}
        if scale_behavior is not None:
            ux["scaleBehavior"] = scale_behavior
        if offset is not None:
            ux["offsetX"], ux["offsetY"] = offset
        return {
            "type": "pattern",
            "pattern": {"width": natural[0], "height": natural[1], "meta": {"ux": ux}},
        }

    def build(self, node: Dict[str, Any]) -> xdref.ExportResult:
        xd_path = build_xd(
            self.tmp_path, [node], blobs={f"resources/{self.UID}": TINY_PNG}
        )
        return self.export(xd_path)

    def image_node(
        self,
        scale_behavior: Optional[str] = "fill",
        offset: Optional[Any] = None,
        natural: Any = (1600, 1600),
    ) -> Dict[str, Any]:
        return rect_node(
            x=0,
            y=0,
            width=813,
            height=812,
            style={"fill": self.pattern_fill(scale_behavior, natural, offset)},
            name="Image 4",
        )

    # -- 1/2: rect bounds drive the tile -------------------------------
    def test_rect_pattern_fill_receives_shape_bounds(self) -> None:
        result = self.build(self.image_node())
        self.assertIn(
            '<pattern id="mxg-pattern-1" patternUnits="userSpaceOnUse" '
            'x="0" y="0" width="813" height="812">',
            result.svg,
        )
        self.assertIn(
            '<image x="0" y="0" width="813" height="812" '
            'preserveAspectRatio="xMidYMid slice"',
            result.svg,
        )
        entry = result.report["pattern_fills"][0]
        self.assertEqual(entry["bounds_source"], "shape-bounds")
        self.assertEqual(
            entry["target_bounds"],
            {"x": 0.0, "y": 0.0, "width": 813.0, "height": 812.0},
        )

    def test_offset_rect_bounds_are_used_verbatim(self) -> None:
        node = rect_node(
            x=10, y=20, width=813, height=812, style={"fill": self.pattern_fill()}
        )
        result = self.build(node)
        self.assertIn('x="10" y="20" width="813" height="812">', result.svg)

    # -- 3: case-insensitive cover spellings ---------------------------
    def test_cover_spellings_map_to_slice(self) -> None:
        for spelling in ("fill", "FILL", "cover", "Cover", "SCALE_COVER", "scale_cover"):
            with self.subTest(spelling=spelling):
                result = self.build(self.image_node(scale_behavior=spelling))
                self.assertIn('preserveAspectRatio="xMidYMid slice"', result.svg)
                self.assertIn('width="813" height="812"', result.svg)
                entry = result.report["pattern_fills"][0]
                self.assertEqual(entry["mode"], "cover")
                # The raw XD spelling is reported, not our normalisation.
                self.assertEqual(entry["scale_behavior"], spelling)
                self.assertEqual(
                    result.report["pattern_scale_behavior_counts"], {spelling: 1}
                )
                self.assertNotIn(
                    "fill:pattern:scaleBehavior:" + spelling,
                    result.report["unsupported_node_counts"],
                )

    # -- 4: stretch spellings ------------------------------------------
    def test_stretch_spellings_map_to_none(self) -> None:
        for spelling in ("stretch", "SCALE_STRETCH", "Scale_Stretch"):
            with self.subTest(spelling=spelling):
                result = self.build(self.image_node(scale_behavior=spelling))
                self.assertIn('preserveAspectRatio="none"', result.svg)
                self.assertNotIn('preserveAspectRatio="xMidYMid slice"', result.svg)
                entry = result.report["pattern_fills"][0]
                self.assertEqual(entry["mode"], "stretch")
                # Stretch still uses the shape bounds, only the fit differs.
                self.assertEqual(entry["target_bounds"]["width"], 813.0)

    # -- 5: unknown behavior is reported, not silently guessed ----------
    def test_unknown_scale_behavior_is_reported(self) -> None:
        result = self.build(self.image_node(scale_behavior="warp-drive"))
        report = result.report

        self.assertIn(
            "fill:pattern:scaleBehavior:warp-drive", report["unsupported_node_counts"]
        )
        self.assertEqual(report["pattern_scale_behavior_counts"], {"warp-drive": 1})
        self.assertTrue(
            any("warp-drive" in warning for warning in report["warnings"]),
            report["warnings"],
        )
        # A documented cover fallback is still applied so the render is usable.
        self.assertEqual(report["pattern_fills"][0]["mode"], "cover")

    # -- 6: natural bitmap size must not become the tile ----------------
    def test_natural_bitmap_size_is_not_the_cover_tile(self) -> None:
        result = self.build(self.image_node())
        self.assertNotIn('width="1600"', result.svg)
        self.assertNotIn('height="1600"', result.svg)

        entry = result.report["pattern_fills"][0]
        # Natural dimensions stay available for diagnostics only.
        self.assertEqual(entry["natural_width"], 1600.0)
        self.assertEqual(entry["natural_height"], 1600.0)
        self.assertEqual(entry["target_bounds"]["width"], 813.0)
        self.assertEqual(entry["target_bounds"]["height"], 812.0)

    # -- 7: offsets remain honoured -------------------------------------
    def test_pattern_meta_offsets_are_still_honoured(self) -> None:
        node = rect_node(
            x=10,
            y=20,
            width=813,
            height=812,
            style={"fill": self.pattern_fill(offset=(-5, -10))},
        )
        result = self.build(node)
        self.assertIn(
            'patternUnits="userSpaceOnUse" x="5" y="10" width="813" height="812">',
            result.svg,
        )
        entry = result.report["pattern_fills"][0]
        self.assertEqual(entry["offset_x"], -5.0)
        self.assertEqual(entry["offset_y"], -10.0)

    # -- 8/9: circle + ellipse bounds -----------------------------------
    def test_circle_fill_bounds(self) -> None:
        node = {
            "type": "shape",
            "id": "circle-1",
            "shape": {"type": "circle", "cx": 100, "cy": 50, "r": 25},
            "style": {"fill": self.pattern_fill()},
        }
        result = self.build(node)
        self.assertIn(
            'patternUnits="userSpaceOnUse" x="75" y="25" width="50" height="50">',
            result.svg,
        )
        self.assertIn(
            '<image x="0" y="0" width="50" height="50" '
            'preserveAspectRatio="xMidYMid slice"',
            result.svg,
        )

    def test_ellipse_fill_bounds(self) -> None:
        node = {
            "type": "shape",
            "id": "ellipse-1",
            "shape": {"type": "ellipse", "cx": 100, "cy": 50, "rx": 30, "ry": 10},
            "style": {"fill": self.pattern_fill()},
        }
        result = self.build(node)
        self.assertIn(
            'patternUnits="userSpaceOnUse" x="70" y="40" width="60" height="20">',
            result.svg,
        )
        self.assertEqual(
            result.report["pattern_fills"][0]["target_bounds"],
            {"x": 70.0, "y": 40.0, "width": 60.0, "height": 20.0},
        )

    # -- geometry without reliable bounds --------------------------------
    def test_path_fill_falls_back_and_warns(self) -> None:
        """A path outside the strictly supported subset keeps the old fallback.

        ``H``/``V`` are deliberately not derivable (D7-I1), so this node still
        takes the pre-repair natural-bitmap route and stays reported.
        """
        node = {
            "type": "shape",
            "id": "path-fill",
            "shape": {"type": "path", "path": "M 0 0 H 10 V 10 Z"},
            "style": {"fill": self.pattern_fill()},
        }
        result = self.build(node)
        report = result.report

        self.assertIn(
            "fill:pattern:no-shape-bounds", report["unsupported_node_counts"]
        )
        self.assertEqual(
            report["pattern_fills"][0]["bounds_source"], "natural-bitmap-fallback"
        )
        self.assertTrue(
            any("no reliable local" in warning for warning in report["warnings"]),
            report["warnings"],
        )
        self.assertNotIn(
            xdref.PATTERN_DERIVED_PATH_BOUNDS_KEY, report["handled_node_counts"]
        )

    # -- 14: report surface ---------------------------------------------
    def test_scale_behavior_counts_are_present_and_serializable(self) -> None:
        result = self.build(self.image_node())
        report = result.report

        self.assertIn("pattern_scale_behavior_counts", report)
        self.assertEqual(report["pattern_scale_behavior_counts"], {"fill": 1})
        encoded = json.dumps(report, ensure_ascii=False)
        self.assertEqual(
            json.loads(encoded)["pattern_scale_behavior_counts"], {"fill": 1}
        )
        self.assertEqual(len(json.loads(encoded)["pattern_fills"]), 1)

    def test_classify_scale_behavior_unit(self) -> None:
        self.assertEqual(xdref.classify_scale_behavior("fill"), ("cover", "fill"))
        self.assertEqual(
            xdref.classify_scale_behavior("SCALE_COVER"), ("cover", "SCALE_COVER")
        )
        self.assertEqual(
            xdref.classify_scale_behavior("SCALE_STRETCH"),
            ("stretch", "SCALE_STRETCH"),
        )
        self.assertEqual(
            xdref.classify_scale_behavior(None),
            ("cover", xdref.SCALE_BEHAVIOR_UNSPECIFIED),
        )
        self.assertEqual(xdref.classify_scale_behavior("nope"), ("unknown", "nope"))


# ---------------------------------------------------------------------------
# I2-R1: honest blend-mode reporting (no CSS approximation).
# ---------------------------------------------------------------------------


class TestBlendModeReporting(ExporterTestCase):
    """Blend reporting for nodes with no safe hoist target.

    Every fixture here puts the blended node directly under the artboard, so it
    has no opacity-group ancestor and can never be safely hoisted. These cases
    must still emit no CSS at all - see ``TestSoftLightSafeHoist`` for the
    calibrated structure that does.
    """

    def build_with_blend(self, blend_mode: Any) -> xdref.ExportResult:
        style: Dict[str, Any] = {"fill": solid_fill(0, 0, 0)}
        if blend_mode is not None:
            style["blendMode"] = blend_mode
        xd_path = build_xd(self.tmp_path, [rect_node(style=style)])
        return self.export(xd_path)

    def test_soft_light_is_counted_with_the_exact_key(self) -> None:
        result = self.build_with_blend("soft-light")
        self.assertIn(
            "style:blendMode:soft-light", result.report["unsupported_node_counts"]
        )
        self.assertEqual(
            result.report["unsupported_node_counts"]["style:blendMode:soft-light"], 1
        )
        self.assertEqual(result.report["blend_mode_counts"], {"soft-light": 1})

    def test_soft_light_produces_a_warning(self) -> None:
        result = self.build_with_blend("soft-light")
        matching = [w for w in result.report["warnings"] if "soft-light" in w]
        self.assertTrue(matching, result.report["warnings"])
        self.assertTrue(
            any("mix-blend-mode" in warning for warning in matching), matching
        )

    def test_unsafe_soft_light_is_not_emitted_as_css(self) -> None:
        """R2 only emits CSS under the proven safe-hoist conditions."""
        result = self.build_with_blend("soft-light")
        self.assertNotIn("mix-blend-mode", result.svg)
        self.assertNotIn("soft-light", result.svg)

    def test_neutral_blend_modes_are_not_reported(self) -> None:
        for blend_mode in (None, "normal", "source-over", ""):
            with self.subTest(blend_mode=blend_mode):
                result = self.build_with_blend(blend_mode)
                unsupported = result.report["unsupported_node_counts"]
                self.assertFalse(
                    [key for key in unsupported if key.startswith("style:blendMode:")],
                    unsupported,
                )
                self.assertEqual(result.report["blend_mode_counts"], {})

    def test_blend_mode_on_group_is_reported(self) -> None:
        group = {
            "type": "group",
            "id": "grp-1",
            "style": {"blendMode": "multiply", "opacity": 0.5},
            "group": {"children": [rect_node()]},
        }
        xd_path = build_xd(self.tmp_path, [group])
        result = self.export(xd_path)
        self.assertIn(
            "style:blendMode:multiply", result.report["unsupported_node_counts"]
        )


# ---------------------------------------------------------------------------
# I2-R2: calibrated soft-light safe hoisting to an opacity group.
# ---------------------------------------------------------------------------


SPLASH_IMAGE_UID = "98578658e496669a0df69fdd35cc42fe"


def splash_image_4(
    blend_mode: Optional[str] = "soft-light", name: str = "Image 4"
) -> Dict[str, Any]:
    """The measured Splash image-fill node: 813x812, opacity 0.12, soft-light."""
    style: Dict[str, Any] = {
        "opacity": 0.12,
        "fill": {
            "type": "pattern",
            "pattern": {
                "width": 1600,
                "height": 1600,
                "meta": {"ux": {"scaleBehavior": "fill", "uid": SPLASH_IMAGE_UID}},
            },
        },
    }
    if blend_mode is not None:
        style["blendMode"] = blend_mode
    return rect_node(
        x=0, y=0, width=813, height=812, name=name, style=style, node_id="image-4"
    )


def group_node(
    name: str,
    children: List[Dict[str, Any]],
    opacity: Optional[float] = None,
    node_id: str = "grp",
    blend_mode: Optional[str] = None,
) -> Dict[str, Any]:
    style: Dict[str, Any] = {}
    if opacity is not None:
        style["opacity"] = opacity
    if blend_mode is not None:
        style["blendMode"] = blend_mode
    return {
        "type": "group",
        "id": node_id,
        "name": name,
        "style": style,
        "group": {"children": children},
    }


class TestSoftLightSafeHoist(ExporterTestCase):
    """The I2-D3 calibrated structure: soft-light on the Repeat Grid group."""

    def build_tree(self, roots: List[Dict[str, Any]]) -> xdref.ExportResult:
        xd_path = build_xd(
            self.tmp_path, roots, blobs={f"resources/{SPLASH_IMAGE_UID}": TINY_PNG}
        )
        return self.export(xd_path)

    def splash_tree(self, image: Optional[Dict[str, Any]] = None) -> Dict[str, Any]:
        """Repeat Grid 60 (0.5) > intermediate group > Image 4 (0.12, soft-light)."""
        return group_node(
            "Repeat Grid 60",
            [
                group_node(
                    "Group 1",
                    [image if image is not None else splash_image_4()],
                    node_id="intermediate",
                )
            ],
            opacity=0.5,
            node_id="repeat-grid-60",
        )

    # -- 1/2/3/4/5/6: the SVG contract ----------------------------------
    def test_splash_evidence_tree_hoists_soft_light_to_repeat_grid(self) -> None:
        result = self.build_tree([self.splash_tree()])

        # 6: the target opacity group carries the blend, and only it.
        self.assertIn(
            '<g data-xd-name="Repeat Grid 60" opacity="0.5" '
            'style="mix-blend-mode:soft-light">',
            result.svg,
        )
        self.assertEqual(result.svg.count("mix-blend-mode"), 1)

        # 2/3: both original opacities survive untouched - nothing multiplied,
        # nothing flattened, nothing removed.
        self.assertIn('opacity="0.5"', result.svg)
        self.assertIn('<g data-xd-name="Image 4" opacity="0.12">', result.svg)

        # 4: the source wrapper must not carry the blend.
        image_wrapper = [
            line for line in result.svg.splitlines() if 'data-xd-name="Image 4"' in line
        ]
        self.assertEqual(len(image_wrapper), 1)
        self.assertNotIn("mix-blend-mode", image_wrapper[0])

        # 5: neither may the painted rect.
        painted = [line for line in result.svg.splitlines() if "<rect" in line]
        self.assertTrue(painted)
        for line in painted:
            self.assertNotIn("mix-blend-mode", line)

    def test_r1_cover_geometry_is_unchanged_by_the_hoist(self) -> None:
        result = self.build_tree([self.splash_tree()])
        self.assertIn(
            '<pattern id="mxg-pattern-1" patternUnits="userSpaceOnUse" '
            'x="0" y="0" width="813" height="812">',
            result.svg,
        )
        self.assertIn(
            '<image x="0" y="0" width="813" height="812" '
            'preserveAspectRatio="xMidYMid slice"',
            result.svg,
        )
        self.assertNotIn('width="1600"', result.svg)
        self.assertNotIn('height="1600"', result.svg)
        self.assertEqual(result.report["pattern_scale_behavior_counts"], {"fill": 1})
        self.assertEqual(result.report["resolved_pattern_fill_count"], 1)

    # -- 7/8/9: reporting -----------------------------------------------
    def test_handled_soft_light_is_not_reported_unsupported(self) -> None:
        report = self.build_tree([self.splash_tree()]).report
        self.assertNotIn("style:blendMode:soft-light", report["unsupported_node_counts"])
        # The mode is still counted as encountered.
        self.assertEqual(report["blend_mode_counts"], {"soft-light": 1})

    def test_blend_mode_application_counts(self) -> None:
        report = self.build_tree([self.splash_tree()]).report
        self.assertEqual(
            report["blend_mode_application_counts"],
            {"soft-light:safe-opacity-group": 1},
        )

    def test_blend_mode_applications_names_source_and_target(self) -> None:
        report = self.build_tree([self.splash_tree()]).report
        self.assertEqual(len(report["blend_mode_applications"]), 1)
        entry = report["blend_mode_applications"][0]

        self.assertEqual(entry["blend_mode"], "soft-light")
        self.assertEqual(entry["strategy"], "safe-opacity-group")
        self.assertTrue(entry["safe_hoist"])
        self.assertEqual(entry["source_node_name"], "Image 4")
        self.assertEqual(entry["target_group_name"], "Repeat Grid 60")
        self.assertEqual(entry["source_opacity"], 0.12)
        self.assertEqual(entry["target_opacity"], 0.5)
        self.assertTrue(entry["reason"])

    # -- 16: the report stays serializable -------------------------------
    def test_report_with_blend_applications_is_serializable(self) -> None:
        report = self.build_tree([self.splash_tree()]).report
        decoded = json.loads(json.dumps(report, ensure_ascii=False))
        self.assertEqual(
            decoded["blend_mode_application_counts"],
            {"soft-light:safe-opacity-group": 1},
        )
        self.assertEqual(
            decoded["blend_mode_applications"][0]["target_group_name"],
            "Repeat Grid 60",
        )

    # -- 10/11/12: refusals ----------------------------------------------
    def assertRefused(self, result: xdref.ExportResult, reason: str) -> None:
        report = result.report
        self.assertNotIn("mix-blend-mode", result.svg)
        self.assertIn("style:blendMode:soft-light", report["unsupported_node_counts"])
        self.assertEqual(
            report["blend_mode_application_counts"], {"soft-light:unsupported": 1}
        )
        entry = report["blend_mode_applications"][0]
        self.assertFalse(entry["safe_hoist"])
        self.assertEqual(entry["reason"], reason)
        self.assertTrue(
            any("safe hoist target could not be proven" in w for w in report["warnings"]),
            report["warnings"],
        )

    def test_soft_light_without_opacity_group_ancestor_stays_unsupported(self) -> None:
        result = self.build_tree([splash_image_4()])
        self.assertRefused(result, "no-opacity-group-ancestor")

    def test_opacity_group_with_full_opacity_is_not_a_target(self) -> None:
        tree = group_node(
            "Repeat Grid 60",
            [group_node("Group 1", [splash_image_4()], node_id="intermediate")],
            opacity=1.0,
            node_id="repeat-grid-60",
        )
        self.assertRefused(self.build_tree([tree]), "no-opacity-group-ancestor")

    def test_painted_sibling_inside_the_opacity_group_blocks_hoisting(self) -> None:
        tree = group_node(
            "Repeat Grid 60",
            [
                group_node("Group 1", [splash_image_4()], node_id="intermediate"),
                rect_node(name="Unrelated", node_id="sibling"),
            ],
            opacity=0.5,
            node_id="repeat-grid-60",
        )
        self.assertRefused(
            self.build_tree([tree]), "ancestor-chain-not-single-content-branch"
        )

    def test_ambiguous_multi_branch_chain_blocks_hoisting(self) -> None:
        tree = group_node(
            "Repeat Grid 60",
            [
                group_node(
                    "Group 1",
                    [splash_image_4(), rect_node(name="Also me", node_id="sibling")],
                    node_id="intermediate",
                )
            ],
            opacity=0.5,
            node_id="repeat-grid-60",
        )
        self.assertRefused(
            self.build_tree([tree]), "ancestor-chain-not-single-content-branch"
        )

    def test_two_soft_light_sources_sharing_a_target_block_each_other(self) -> None:
        inner = group_node(
            "Group 1",
            [splash_image_4()],
            node_id="intermediate",
            blend_mode="soft-light",
        )
        tree = group_node(
            "Repeat Grid 60", [inner], opacity=0.5, node_id="repeat-grid-60"
        )
        result = self.build_tree([tree])
        report = result.report

        self.assertNotIn("mix-blend-mode", result.svg)
        self.assertEqual(
            report["unsupported_node_counts"]["style:blendMode:soft-light"], 2
        )
        self.assertEqual(
            report["blend_mode_application_counts"], {"soft-light:unsupported": 2}
        )
        for entry in report["blend_mode_applications"]:
            self.assertEqual(entry["reason"], "multiple-soft-light-sources-target-group")

    def test_hidden_sibling_does_not_block_hoisting(self) -> None:
        hidden = rect_node(name="Hidden", node_id="hidden-sibling")
        hidden["visible"] = False
        tree = group_node(
            "Repeat Grid 60",
            [
                group_node("Group 1", [splash_image_4()], node_id="intermediate"),
                hidden,
            ],
            opacity=0.5,
            node_id="repeat-grid-60",
        )
        result = self.build_tree([tree])
        self.assertIn('style="mix-blend-mode:soft-light"', result.svg)
        self.assertEqual(
            result.report["blend_mode_application_counts"],
            {"soft-light:safe-opacity-group": 1},
        )

    # -- 14: the calibration is not generalised --------------------------
    def test_multiply_is_not_hoisted_even_in_the_calibrated_shape(self) -> None:
        tree = group_node(
            "Repeat Grid 60",
            [
                group_node(
                    "Group 1",
                    [splash_image_4(blend_mode="multiply")],
                    node_id="intermediate",
                )
            ],
            opacity=0.5,
            node_id="repeat-grid-60",
        )
        result = self.build_tree([tree])
        report = result.report

        self.assertNotIn("mix-blend-mode", result.svg)
        self.assertIn("style:blendMode:multiply", report["unsupported_node_counts"])
        self.assertEqual(
            report["blend_mode_application_counts"], {"multiply:unsupported": 1}
        )
        self.assertEqual(
            report["blend_mode_applications"][0]["reason"], "blend-mode-not-calibrated"
        )


# ---------------------------------------------------------------------------
# 9-11: filters.
# ---------------------------------------------------------------------------


class TestFilters(ExporterTestCase):
    def test_hidden_blur_is_not_applied(self) -> None:
        style = {
            "fill": solid_fill(0, 0, 0),
            "filters": [
                {
                    "type": "uxdesign#blur",
                    "visible": False,
                    "params": {"blurAmount": 20, "backgroundEffect": False},
                }
            ],
        }
        xd_path = build_xd(self.tmp_path, [rect_node(style=style)])
        result = self.export(xd_path)

        self.assertNotIn("feGaussianBlur", result.svg)
        self.assertNotIn("<filter", result.svg)
        self.assertEqual(result.report["hidden_blur_count"], 1)
        self.assertEqual(result.report["visible_blur_count"], 0)

    def test_visible_blur_generates_svg_filter(self) -> None:
        style = {
            "fill": solid_fill(0, 0, 0),
            "filters": [
                {
                    "type": "uxdesign#blur",
                    "visible": True,
                    "params": {"blurAmount": 10, "backgroundEffect": False},
                }
            ],
        }
        xd_path = build_xd(self.tmp_path, [rect_node(style=style)])
        result = self.export(xd_path)

        expected = 10 * xdref.BLUR_AMOUNT_TO_STD_DEVIATION
        self.assertIn(f'<feGaussianBlur stdDeviation="{xdref.fmt_num(expected)}"/>', result.svg)
        self.assertIn('filter="url(#mxg-filter-1)"', result.svg)
        self.assertEqual(result.report["visible_blur_count"], 1)
        self.assertEqual(result.report["hidden_blur_count"], 0)
        self.assertEqual(
            result.report["approximation_mapping"]["blur_amount_to_std_deviation"],
            xdref.BLUR_AMOUNT_TO_STD_DEVIATION,
        )

    def test_drop_shadow_generates_svg_filter(self) -> None:
        style = {
            "fill": solid_fill(0, 0, 0),
            "filters": [
                {
                    "type": "dropShadow",
                    "visible": True,
                    "params": {
                        "dropShadows": [
                            {
                                "dx": 0,
                                "dy": 4,
                                "r": 8,
                                "a": 0.25,
                                "color": {
                                    "mode": "RGB",
                                    "value": {"r": 0, "g": 0, "b": 0},
                                },
                            }
                        ]
                    },
                }
            ],
        }
        xd_path = build_xd(self.tmp_path, [rect_node(style=style)])
        result = self.export(xd_path)

        self.assertIn('<feDropShadow dx="0" dy="4" stdDeviation="4"', result.svg)
        self.assertIn('flood-color="#000000"', result.svg)
        self.assertIn('flood-opacity="0.25"', result.svg)
        self.assertEqual(result.report["visible_drop_shadow_count"], 1)


# ---------------------------------------------------------------------------
# 12: clip paths.
# ---------------------------------------------------------------------------


class TestClipPaths(ExporterTestCase):
    def test_clip_path_produces_defs_and_is_not_painted(self) -> None:
        clip_geometry = {
            "type": "shape",
            "id": "clip-rect",
            "shape": {"type": "rect", "x": 0, "y": 0, "width": 10, "height": 10},
            # A clip child carries a fill in AGC; it must never be painted.
            "style": {"fill": solid_fill(0, 0xFF, 0)},
        }
        standalone_clip = {
            "type": "clipPath",
            "id": "inline-clip",
            "clipPath": {
                "children": [
                    {
                        "type": "shape",
                        "id": "clip-circle",
                        "shape": {"type": "circle", "cx": 5, "cy": 5, "r": 5},
                        "style": {"fill": solid_fill(0, 0, 0xFF)},
                    }
                ]
            },
        }
        clipped_group = {
            "type": "group",
            "id": "grp-1",
            "style": {"clipPath": {"ref": "cp1"}},
            "group": {"children": [rect_node(style={"fill": solid_fill(0xFF, 0, 0)})]},
        }

        xd_path = build_xd(
            self.tmp_path,
            [standalone_clip, clipped_group],
            agc_resources={
                "clipPaths": {
                    "cp1": {"type": "clipPath", "clipPath": {"children": [clip_geometry]}}
                }
            },
        )
        result = self.export(xd_path)

        self.assertEqual(result.report["clip_path_count"], 2)
        self.assertIn('<clipPath id="mxg-clip-1"', result.svg)
        self.assertIn('<clipPath id="mxg-clip-2"', result.svg)
        self.assertIn('clip-path="url(#mxg-clip-2)"', result.svg)

        # The clipping geometry keeps no paint attributes and is not emitted as
        # ordinary visible content.
        self.assertNotIn("#00ff00", result.svg)
        self.assertNotIn("#0000ff", result.svg)
        self.assertIn('fill="#ff0000"', result.svg)  # the clipped content still paints
        self.assertIn('<circle cx="5" cy="5" r="5"/>', result.svg)

    def test_unresolved_clip_reference_does_not_crash(self) -> None:
        clipped_group = {
            "type": "group",
            "id": "grp-1",
            "style": {"clipPath": {"ref": "missing-clip"}},
            "group": {"children": [rect_node()]},
        }
        xd_path = build_xd(self.tmp_path, [clipped_group])
        result = self.export(xd_path)

        self.assertEqual(result.report["clip_path_count"], 0)
        self.assertIn("clipPath:unresolved", result.report["unsupported_node_counts"])
        self.assertIn("<rect", result.svg)


# ---------------------------------------------------------------------------
# 13-15: Bictov / Merzox brand handling.
# ---------------------------------------------------------------------------


class TestBrandNormalization(ExporterTestCase):
    def test_raw_mode_preserves_bictov(self) -> None:
        xd_path = build_xd(self.tmp_path, [text_node("Bictov app")])
        result = self.export(xd_path)

        self.assertIn(">Bictov app</text>", result.svg)
        self.assertNotIn("Merzox app", result.svg)
        self.assertFalse(result.report["brand_normalization_enabled"])
        self.assertEqual(result.report["brand_replacement_count"], 0)
        self.assertEqual(result.report["text_node_count"], 1)

    def test_normalized_mode_replaces_bictov_with_merzox(self) -> None:
        xd_path = build_xd(self.tmp_path, [text_node("Bictov app")])
        result = self.export(xd_path, normalize_brand=True)

        self.assertIn(">Merzox app</text>", result.svg)
        self.assertNotIn(">Bictov app</text>", result.svg)
        self.assertTrue(result.report["brand_normalization_enabled"])

    def test_normalized_mode_replaces_the_all_caps_wordmark(self) -> None:
        # The `من نحن` artboard sets the wordmark in full caps ("تطبيق BICTOV").
        # That form went straight through before, so a reference exported for
        # app parity still showed the old brand.
        xd_path = build_xd(self.tmp_path, [text_node("BICTOV app")])
        result = self.export(xd_path, normalize_brand=True)

        self.assertIn(">MERZOX app</text>", result.svg)
        self.assertNotIn("BICTOV app", result.svg)
        self.assertEqual(result.report["brand_replacement_count"], 1)

    def test_all_caps_wordmark_keeps_its_case(self) -> None:
        # Replacing the WORD is what the flag promises; restyling all-caps
        # typography to title case would be an edit it never claimed.
        xd_path = build_xd(self.tmp_path, [text_node("BICTOV")])
        result = self.export(xd_path, normalize_brand=True)

        self.assertIn(">MERZOX</text>", result.svg)
        self.assertNotIn(">Merzox</text>", result.svg)

    def test_all_caps_wordmark_requires_normalized_mode(self) -> None:
        xd_path = build_xd(self.tmp_path, [text_node("BICTOV app")])
        result = self.export(xd_path)

        self.assertIn(">BICTOV app</text>", result.svg)
        self.assertEqual(result.report["brand_replacement_count"], 0)

    def test_both_brand_cases_in_one_chunk_are_both_replaced(self) -> None:
        xd_path = build_xd(self.tmp_path, [text_node("Bictov and BICTOV")])
        result = self.export(xd_path, normalize_brand=True)

        self.assertIn(">Merzox and MERZOX</text>", result.svg)
        self.assertEqual(result.report["brand_replacement_count"], 2)

    def test_normalized_report_counts_replacements(self) -> None:
        xd_path = build_xd(self.tmp_path, [text_node("Bictov and Bictov")])
        result = self.export(xd_path, normalize_brand=True)
        self.assertEqual(result.report["brand_replacement_count"], 2)

    def test_normalized_mode_replaces_exact_segmented_logo_tail(self) -> None:
        xd_path = build_xd(self.tmp_path, [text_node("ictove")])
        result = self.export(xd_path, normalize_brand=True)

        self.assertIn(">Merzox</text>", result.svg)
        self.assertNotIn(">ictove</text>", result.svg)
        self.assertEqual(result.report["brand_replacement_count"], 1)

    def test_segmented_logo_tail_requires_normalized_mode(self) -> None:
        xd_path = build_xd(self.tmp_path, [text_node("ictove")])
        result = self.export(xd_path)

        self.assertIn(">ictove</text>", result.svg)
        self.assertNotIn(">Merzox</text>", result.svg)
        self.assertEqual(result.report["brand_replacement_count"], 0)

    def test_segmented_logo_tail_match_is_exact_not_substring(self) -> None:
        content = "prefix ictove suffix"
        xd_path = build_xd(self.tmp_path, [text_node(content)])
        result = self.export(xd_path, normalize_brand=True)

        self.assertIn(f">{content}</text>", result.svg)
        self.assertNotIn(">Merzox</text>", result.svg)
        self.assertEqual(result.report["brand_replacement_count"], 0)

    def test_normalization_does_not_touch_ids_or_names(self) -> None:
        """Only rendered text is normalised - never JSON identifiers or names."""
        xd_path = build_xd(
            self.tmp_path, [text_node("Bictov app", name="Bictov Logo")]
        )
        result = self.export(xd_path, normalize_brand=True)

        self.assertIn('data-xd-name="Bictov Logo"', result.svg)
        self.assertIn(">Merzox app</text>", result.svg)
        self.assertEqual(result.report["brand_replacement_count"], 1)

    def test_arabic_text_is_emitted_verbatim(self) -> None:
        arabic = "مرحبا بك"
        xd_path = build_xd(self.tmp_path, [text_node(arabic)])
        result = self.export(xd_path)
        self.assertIn(f">{arabic}</text>", result.svg)


# ---------------------------------------------------------------------------
# 16: font embedding.
# ---------------------------------------------------------------------------


class TestFontEmbedding(ExporterTestCase):
    def test_embedded_tajawal_font_face_exists(self) -> None:
        xd_path = build_xd(self.tmp_path, [text_node()])
        result = self.export(xd_path)
        expected_uri = "data:font/ttf;base64," + base64.b64encode(
            self.font_path.read_bytes()
        ).decode("ascii")

        self.assertIn("@font-face", result.svg)
        self.assertIn(expected_uri, result.svg)
        for alias in xdref.TAJAWAL_ALIASES:
            self.assertIn(f"font-family:'{alias}'", result.svg)

        report = result.report
        self.assertEqual(report["embedded_fonts"], list(xdref.TAJAWAL_ALIASES))
        self.assertTrue(report["synthetic_tajawal_weight_limitation"])
        self.assertEqual(report["non_embedded_fonts"], [])
        self.assertIn("Tajawal", report["fonts_requested"])
        self.assertTrue(
            any("weight synthesis" in item for item in report["limitations"]),
            report["limitations"],
        )

    def test_non_tajawal_font_is_recorded_but_not_embedded(self) -> None:
        xd_path = build_xd(
            self.tmp_path,
            [text_node(family="Concept", postscript="Concept-Medium")],
        )
        result = self.export(xd_path)
        report = result.report

        self.assertIn("Concept", report["fonts_requested"])
        self.assertIn("Concept", report["non_embedded_fonts"])
        self.assertNotIn("Concept", report["embedded_fonts"])
        # Quotes inside the font-family attribute are XML-escaped.
        self.assertIn("&apos;Concept-Medium&apos;", result.svg)
        self.assertTrue(
            any("not embedded" in warning for warning in report["warnings"]),
            report["warnings"],
        )

    def test_default_font_path_points_at_repo_asset(self) -> None:
        expected = (
            Path(xdref.__file__).resolve().parents[2]
            / "assets"
            / "fonts"
            / "Tajawal-Regular.ttf"
        )
        self.assertEqual(xdref.default_font_path(), expected)


# ---------------------------------------------------------------------------
# 17: unsupported features are recorded, never silently discarded.
# ---------------------------------------------------------------------------


class TestBackgroundBlur(ExporterTestCase):
    """XD backdrop blur, rendered as a CSS backdrop-filter.

    SVG filters cannot read what is behind an element - `BackgroundImage` was
    specified and never implemented - so the effect is emitted as a
    foreignObject carrying `backdrop-filter`, which the exporter's own
    headless Chromium does implement.
    """

    @staticmethod
    def _style(**params):
        merged = {"blurAmount": 20, "backgroundEffect": True}
        merged.update(params)
        return {
            "fill": solid_fill(255, 255, 255),
            "filters": [
                {"type": "uxdesign#blur", "visible": True, "params": merged}
            ],
        }

    def test_backdrop_blur_is_emitted_as_a_css_filter(self) -> None:
        xd_path = build_xd(self.tmp_path, [rect_node(style=self._style())])
        result = self.export(xd_path)

        self.assertIn("foreignObject", result.svg)
        self.assertIn("backdrop-filter:blur(10px)", result.svg)
        # Both spellings, so the SVG survives a renderer that only has the
        # prefixed property.
        self.assertIn("-webkit-backdrop-filter:blur(10px)", result.svg)

    def test_backdrop_blur_is_not_a_gaussian_object_blur(self) -> None:
        xd_path = build_xd(self.tmp_path, [rect_node(style=self._style())])
        result = self.export(xd_path)

        # Blurring the shape itself would be the wrong effect entirely.
        self.assertNotIn("feGaussianBlur", result.svg)
        self.assertEqual(result.report["visible_blur_count"], 0)

    def test_backdrop_blur_counts_as_handled_not_unsupported(self) -> None:
        xd_path = build_xd(self.tmp_path, [rect_node(style=self._style())])
        report = self.export(xd_path).report

        self.assertEqual(report["background_blur_count"], 1)
        self.assertEqual(report["unsupported_background_blur_count"], 0)
        self.assertEqual(report["unsupported_node_counts"], {})
        self.assertIn(
            "filter:uxdesign#blur:background", report["handled_node_counts"]
        )

    def test_the_parameter_mapping_is_declared_in_the_report(self) -> None:
        xd_path = build_xd(self.tmp_path, [rect_node(style=self._style())])
        report = self.export(xd_path).report

        # A real effect with an approximate mapping must say so.
        self.assertTrue(
            any(
                "backdrop-filter" in note
                for note in report["limitations"]
            ),
            report["limitations"],
        )

    def test_brightness_is_read_as_a_percentage_adjustment(self) -> None:
        xd_path = build_xd(
            self.tmp_path, [rect_node(style=self._style(brightnessAmount=15))]
        )
        result = self.export(xd_path)

        self.assertIn("brightness(1.15)", result.svg)

    def test_no_brightness_change_emits_no_brightness_function(self) -> None:
        xd_path = build_xd(
            self.tmp_path, [rect_node(style=self._style(brightnessAmount=0))]
        )
        result = self.export(xd_path)

        self.assertNotIn("brightness(", result.svg)

    def test_a_transparent_fill_still_paints_the_backdrop(self) -> None:
        xd_path = build_xd(
            self.tmp_path, [rect_node(style=self._style(fillOpacity=0))]
        )
        result = self.export(xd_path)

        # fillOpacity 0 hides the shape's own white fill; the blurred backdrop
        # behind it is the whole point and must survive.
        self.assertIn("foreignObject", result.svg)
        self.assertIn('fill-opacity="0"', result.svg)

    def test_a_partial_fill_opacity_scales_the_shape_fill(self) -> None:
        xd_path = build_xd(
            self.tmp_path, [rect_node(style=self._style(fillOpacity=0.1))]
        )
        result = self.export(xd_path)

        self.assertIn('fill-opacity="0.1"', result.svg)

    def test_a_hidden_backdrop_blur_is_not_applied(self) -> None:
        style = self._style()
        style["filters"][0]["visible"] = False
        xd_path = build_xd(self.tmp_path, [rect_node(style=style)])
        result = self.export(xd_path)

        self.assertNotIn("foreignObject", result.svg)
        self.assertEqual(result.report["background_blur_count"], 0)
        self.assertEqual(result.report["hidden_blur_count"], 1)

    def test_an_empty_backdrop_blur_is_not_applied(self) -> None:
        xd_path = build_xd(
            self.tmp_path,
            [rect_node(style=self._style(blurAmount=0, brightnessAmount=0))],
        )
        result = self.export(xd_path)

        # Nothing to blur and nothing to brighten is not an effect.
        self.assertNotIn("foreignObject", result.svg)
        self.assertEqual(result.report["background_blur_count"], 0)

    def test_a_rounded_rectangle_keeps_its_corners(self) -> None:
        node = rect_node(style=self._style())
        node["shape"]["r"] = [5, 5, 5, 5]
        xd_path = build_xd(self.tmp_path, [node])
        result = self.export(xd_path)

        self.assertIn("border-radius:5px", result.svg)

    def test_a_non_rectangular_backdrop_blur_still_fails_closed(self) -> None:
        node = {
            "type": "shape",
            "id": "ellipse-1",
            "shape": {"type": "ellipse", "cx": 10, "cy": 10, "rx": 10, "ry": 5},
            "style": self._style(),
        }
        xd_path = build_xd(self.tmp_path, [node])
        report = self.export(xd_path).report

        # A CSS box cannot be clipped to an arbitrary XD outline, so this one
        # is refused rather than drawn as a rectangle that is not there.
        self.assertEqual(report["unsupported_background_blur_count"], 1)
        self.assertIn(
            "filter:uxdesign#blur:background:shape",
            report["unsupported_node_counts"],
        )

    def test_a_backdrop_blur_on_a_group_still_fails_closed(self) -> None:
        group = {
            "type": "group",
            "id": "group-1",
            "style": self._style(),
            "group": {"children": [rect_node()]},
        }
        xd_path = build_xd(self.tmp_path, [group])
        report = self.export(xd_path).report

        self.assertEqual(report["unsupported_background_blur_count"], 1)
        self.assertIn(
            "filter:uxdesign#blur:background:group",
            report["unsupported_node_counts"],
        )


class TestUnsupportedFeatureReporting(ExporterTestCase):
    def test_compound_without_flattened_path_is_reported(self) -> None:
        compound = {
            "type": "shape",
            "id": "compound-1",
            "shape": {
                "type": "compound",
                "operation": "subtract",
                "children": [
                    rect_node(node_id="c-rect"),
                    {
                        "type": "shape",
                        "id": "c-circle",
                        "shape": {"type": "circle", "cx": 10, "cy": 10, "r": 5},
                        "style": {"fill": solid_fill(0, 0, 0)},
                    },
                ],
            },
        }
        xd_path = build_xd(self.tmp_path, [compound])
        result = self.export(xd_path)
        report = result.report

        self.assertIn(
            "shape:compound:subtract", report["unsupported_node_counts"]
        )
        self.assertIn('data-xd-unsupported-compound="subtract"', result.svg)
        # Child geometry is preserved rather than dropped.
        self.assertIn("<rect", result.svg)
        self.assertIn("<circle", result.svg)
        self.assertTrue(
            any("NOT accurate" in warning for warning in report["warnings"]),
            report["warnings"],
        )

    def test_compound_with_flattened_path_is_exact(self) -> None:
        compound = {
            "type": "shape",
            "id": "compound-1",
            "shape": {
                "type": "compound",
                "operation": "subtract",
                "path": "M0 0 H10 V10 H0 Z",
                "children": [],
            },
            "style": {"fill": solid_fill(1, 2, 3)},
        }
        xd_path = build_xd(self.tmp_path, [compound])
        result = self.export(xd_path)

        self.assertIn('<path d="M0 0 H10 V10 H0 Z" fill-rule="evenodd"', result.svg)
        self.assertNotIn(
            "shape:compound:subtract", result.report["unsupported_node_counts"]
        )

    def test_unknown_node_type_is_counted(self) -> None:
        xd_path = build_xd(self.tmp_path, [{"type": "hologram", "id": "x1"}])
        result = self.export(xd_path)

        self.assertEqual(result.report["node_type_counts"]["hologram"], 1)
        self.assertIn("node:hologram", result.report["unsupported_node_counts"])

    def test_unresolved_sync_ref_is_counted_without_crashing(self) -> None:
        xd_path = build_xd(
            self.tmp_path,
            [{"type": "syncRef", "id": "s1", "syncRef": {"ref": "missing-symbol"}}],
        )
        result = self.export(xd_path)

        self.assertEqual(result.report["unresolved_sync_refs"], 1)
        self.assertIn("syncRef:unresolved", result.report["unsupported_node_counts"])
        self.assertTrue(
            any("syncRef" in warning for warning in result.report["warnings"]),
            result.report["warnings"],
        )

    def test_resolved_sync_ref_renders_shared_symbol(self) -> None:
        shared = {
            "version": "3.0.0",
            "artboards": {},
            "resources": {
                "meta": {
                    "ux": {
                        "symbols": [
                            {
                                "type": "group",
                                "id": "sym-1",
                                "meta": {"ux": {"symbolId": "sym-1"}},
                                "group": {
                                    "children": [
                                        rect_node(
                                            style={"fill": solid_fill(0, 0xAA, 0)},
                                            node_id="sym-rect",
                                        )
                                    ]
                                },
                            }
                        ]
                    }
                }
            },
            "children": [],
        }
        xd_path = build_xd(
            self.tmp_path,
            [{"type": "syncRef", "id": "s1", "syncRef": {"ref": "sym-1"}}],
            shared_agc=shared,
        )
        result = self.export(xd_path)

        self.assertEqual(result.report["resolved_sync_refs"], 1)
        self.assertEqual(result.report["unresolved_sync_refs"], 0)
        self.assertIn('fill="#00aa00"', result.svg)

    def test_hidden_node_is_skipped_and_counted(self) -> None:
        hidden = rect_node(style={"fill": solid_fill(0xFF, 0, 0)})
        hidden["visible"] = False
        xd_path = build_xd(self.tmp_path, [hidden])
        result = self.export(xd_path)

        self.assertEqual(result.report["invisible_node_count"], 1)
        self.assertNotIn("#ff0000", result.svg)


# ---------------------------------------------------------------------------
# Gradients.
# ---------------------------------------------------------------------------


class TestGradients(ExporterTestCase):
    def test_referenced_linear_gradient_is_emitted(self) -> None:
        fill = {
            "type": "gradient",
            "gradient": {"ref": "grad-1"},
            "x1": 0,
            "y1": 0,
            "x2": 1,
            "y2": 1,
        }
        xd_path = build_xd(
            self.tmp_path,
            [rect_node(style={"fill": fill})],
            agc_resources={
                "gradients": {
                    "grad-1": {
                        "type": "linear",
                        "stops": [
                            {
                                "offset": 0,
                                "color": {
                                    "mode": "RGB",
                                    "value": {"r": 255, "g": 0, "b": 0},
                                },
                            },
                            {
                                "offset": 1,
                                "color": {
                                    "mode": "RGB",
                                    "value": {"r": 0, "g": 0, "b": 255},
                                },
                                "a": 0.5,
                            },
                        ],
                    }
                }
            },
        )
        result = self.export(xd_path)

        self.assertIn('<linearGradient id="mxg-gradient-1"', result.svg)
        self.assertIn('stop-color="#ff0000"', result.svg)
        self.assertIn('stop-opacity="0.5"', result.svg)
        self.assertIn('fill="url(#mxg-gradient-1)"', result.svg)
        self.assertEqual(result.report["gradient_fill_count"], 1)


# ---------------------------------------------------------------------------
# 18: report serialisability + CLI surface.
# ---------------------------------------------------------------------------


class TestReport(ExporterTestCase):
    REQUIRED_KEYS = (
        "source_xd",
        "selected_artboard_name",
        "selected_artboard_path",
        "selected_artboard_id",
        "artboard_bounds",
        "svg_width",
        "svg_height",
        "browser_path",
        "browser_return_code",
        "node_type_counts",
        "handled_node_counts",
        "unsupported_node_counts",
        "unresolved_sync_refs",
        "pattern_fill_count",
        "resolved_pattern_fill_count",
        "unresolved_pattern_fill_count",
        "resource_ids_used",
        "text_node_count",
        "fonts_requested",
        "embedded_fonts",
        "non_embedded_fonts",
        "synthetic_tajawal_weight_limitation",
        "visible_drop_shadow_count",
        "visible_blur_count",
        "hidden_blur_count",
        "unsupported_background_blur_count",
        "clip_path_count",
        "brand_normalization_enabled",
        "brand_replacement_count",
        "warnings",
    )

    def test_report_contains_required_keys_and_is_serializable(self) -> None:
        xd_path = build_xd(self.tmp_path, [rect_node(), text_node()])
        result = self.export(xd_path)
        report = result.report

        for key in self.REQUIRED_KEYS:
            self.assertIn(key, report)

        encoded = json.dumps(report, ensure_ascii=False, indent=2)
        self.assertEqual(json.loads(encoded)["selected_artboard_name"], ARTBOARD_NAME)
        self.assertEqual(
            json.loads(encoded)["selected_artboard_path"], "artwork/artboard-ab1"
        )
        # No browser was invoked in tests.
        self.assertIsNone(report["browser_path"])
        self.assertIsNone(report["browser_return_code"])

    def test_report_iteration_is_current(self) -> None:
        """Guards against a stale iteration stamp (the I2-R3 audit blocker)."""
        xd_path = build_xd(self.tmp_path, [rect_node()])
        report = self.export(xd_path).report

        self.assertEqual(report["iteration"], "MERZOX-UI-GOLDEN-I3-R2-D7-I1")
        self.assertEqual(report["iteration"], xdref.EXPORTER_ITERATION)
        self.assertNotEqual(report["iteration"], "MERZOX-UI-GOLDEN-I1")

        # The schema version is independent of the calibration iteration and
        # must NOT be bumped just because the iteration moved.
        self.assertEqual(report["schema"], "merzox.xd_reference_exporter/1")
        self.assertEqual(report["schema"], xdref.REPORT_SCHEMA)

        # Still serializable, and the stamp survives a JSON round-trip.
        decoded = json.loads(json.dumps(report, ensure_ascii=False))
        self.assertEqual(decoded["iteration"], "MERZOX-UI-GOLDEN-I3-R2-D7-I1")
        self.assertEqual(decoded["schema"], "merzox.xd_reference_exporter/1")

    def test_written_report_file_carries_current_iteration(self) -> None:
        xd_path = build_xd(self.tmp_path, [rect_node()])
        svg_out = self.tmp_path / "stamped" / "artboard.svg"
        report_out = self.tmp_path / "stamped" / "artboard.report.json"

        xdref.export_artboard(
            xd_path,
            ARTBOARD_NAME,
            output_svg=svg_out,
            report_json=report_out,
            font_path=self.font_path,
            render_png=False,
        )
        loaded = json.loads(report_out.read_text(encoding="utf-8"))
        self.assertEqual(loaded["iteration"], "MERZOX-UI-GOLDEN-I3-R2-D7-I1")
        # The generated SVG must not advertise a stale iteration either.
        svg = svg_out.read_text(encoding="utf-8")
        self.assertIn("MERZOX-UI-GOLDEN-I3-R2-D7-I1", svg)
        self.assertNotIn("MERZOX-UI-GOLDEN-I1", svg)

    def test_report_json_is_written_to_disk(self) -> None:
        xd_path = build_xd(self.tmp_path, [rect_node()])
        svg_out = self.tmp_path / "out" / "artboard.svg"
        report_out = self.tmp_path / "out" / "artboard.report.json"

        xdref.export_artboard(
            xd_path,
            ARTBOARD_NAME,
            output_svg=svg_out,
            report_json=report_out,
            font_path=self.font_path,
            render_png=False,
        )
        self.assertTrue(svg_out.is_file())
        self.assertTrue(report_out.is_file())
        loaded = json.loads(report_out.read_text(encoding="utf-8"))
        self.assertEqual(loaded["selected_artboard_name"], ARTBOARD_NAME)
        self.assertEqual(loaded["svg_width"], 375.0)

    def test_cli_parser_accepts_the_documented_invocation(self) -> None:
        parser = xdref.build_arg_parser()
        args = parser.parse_args(
            [
                "--xd",
                "design.xd",
                "--artboard-name",
                ARTBOARD_NAME,
                "--output-svg",
                "out.svg",
                "--output-png",
                "out.png",
                "--report-json",
                "out.json",
                "--normalize-merzox-brand",
            ]
        )
        self.assertEqual(args.xd, "design.xd")
        self.assertEqual(args.artboard_name, ARTBOARD_NAME)
        self.assertEqual(args.output_svg, "out.svg")
        self.assertEqual(args.output_png, "out.png")
        self.assertEqual(args.report_json, "out.json")
        self.assertTrue(args.normalize_merzox_brand)

    def test_browser_candidate_order_prefers_edge(self) -> None:
        candidates = [str(path).lower() for path in xdref.BrowserLocator.candidates()]
        edge = [i for i, path in enumerate(candidates) if "msedge" in path]
        chrome = [i for i, path in enumerate(candidates) if "chrome.exe" in path]
        if edge and chrome:
            self.assertLess(min(edge), min(chrome))


# ---------------------------------------------------------------------------
# I3-I1: stable identity selectors + deterministic all-artboard batch export.
# ---------------------------------------------------------------------------


#: (name, manifest_id, artwork uuid). Mirrors the real package, where the
#: manifest id and the artwork-path uuid are different values, and where a few
#: human names are shared by several artboards.
MULTI_SPECS = [
    ("سبلاش – 1", "1ff58a48-0e8d-49eb-be2f-4b7a24adcf9c", "29c52d7e-0f4c-439b-87cc-5d4a5cd8f229"),
    ("من نحن", "2aa11111-0000-4000-8000-000000000001", "b0000001-0000-4000-8000-000000000001"),
    ("اعدادات المتجر", "3bb22222-0000-4000-8000-000000000002", "b0000002-0000-4000-8000-000000000002"),
    ("اعدادات المتجر", "4cc33333-0000-4000-8000-000000000003", "b0000003-0000-4000-8000-000000000003"),
    ("الرسائل", "5dd44444-0000-4000-8000-000000000004", "b0000004-0000-4000-8000-000000000004"),
    ("الرسائل", "6ee55555-0000-4000-8000-000000000005", "b0000005-0000-4000-8000-000000000005"),
    ("معاينة", "7ff66666-0000-4000-8000-000000000006", "b0000006-0000-4000-8000-000000000006"),
    ("معاينة", "80077777-0000-4000-8000-000000000007", "b0000007-0000-4000-8000-000000000007"),
]

SPLASH_MANIFEST_ID = MULTI_SPECS[0][1]
SPLASH_ARTWORK_PATH = f"artwork/artboard-{MULTI_SPECS[0][2]}"


def build_multi_artboard_xd(
    directory: Path,
    specs: Any = None,
    filename: str = "multi.xd",
    broken_indices: Any = (),
    extra_nodes: Any = (),
) -> Path:
    """Build a multi-artboard .xd fixture in the given manifest order.

    Indices listed in ``broken_indices`` (0-based) get a manifest entry but no
    ``graphicContent.agc``, so exporting them fails while their neighbours do not.
    """
    specs = list(specs if specs is not None else MULTI_SPECS)
    artwork_children = []
    payloads: Dict[str, str] = {}

    for position, (name, manifest_id, artwork_uuid) in enumerate(specs):
        path_leaf = f"artboard-{artwork_uuid}"
        artwork_children.append(
            {
                "type": "artboard",
                "id": manifest_id,
                "name": name,
                "path": path_leaf,
                "uxdesign#bounds": {
                    "x": 0,
                    "y": 0,
                    "width": ARTBOARD_WIDTH,
                    "height": ARTBOARD_HEIGHT,
                },
            }
        )
        if position in tuple(broken_indices):
            continue
        agc = {
            "version": "3.0.0",
            "artboards": {
                path_leaf: {
                    "x": 0,
                    "y": 0,
                    "width": ARTBOARD_WIDTH,
                    "height": ARTBOARD_HEIGHT,
                    "style": {"fill": WHITE_FILL},
                }
            },
            "resources": {},
            "children": [
                {
                    "type": "artboard",
                    "id": manifest_id,
                    "artboard": {
                        "ref": path_leaf,
                        "children": [
                            rect_node(name=name, node_id=f"rect-{position}"),
                            text_node("Bictov app", node_id=f"text-{position}"),
                            *list(extra_nodes),
                        ],
                    },
                }
            ],
        }
        payloads[f"artwork/{path_leaf}/graphics/graphicContent.agc"] = json.dumps(
            agc, ensure_ascii=False
        )

    manifest = {
        "id": "root",
        "name": "manifest",
        "path": "/",
        "children": [
            {"path": "artwork", "children": artwork_children},
            {"path": "resources", "children": []},
        ],
    }

    xd_path = directory / filename
    with zipfile.ZipFile(xd_path, "w", zipfile.ZIP_DEFLATED) as archive:
        archive.writestr("mimetype", "application/vnd.adobe.xd")
        archive.writestr("manifest", json.dumps(manifest, ensure_ascii=False))
        for name, payload in payloads.items():
            archive.writestr(name, payload)
    return xd_path


class TestStableArtboardSelectors(ExporterTestCase):
    """Manifest id is canonical; path is stable; name may be ambiguous."""

    def setUp(self) -> None:
        super().setUp()
        self.xd_path = build_multi_artboard_xd(self.tmp_path)

    # -- 1/2: manifest id --------------------------------------------------
    def test_manifest_id_lookup_succeeds(self) -> None:
        with xdref.XdPackage(self.xd_path) as package:
            artboard = package.find_artboard_by_manifest_id(SPLASH_MANIFEST_ID)
        self.assertEqual(artboard.name, "سبلاش – 1")
        self.assertEqual(artboard.path, SPLASH_ARTWORK_PATH)
        self.assertEqual(artboard.manifest_id, SPLASH_MANIFEST_ID)

    def test_unknown_manifest_id_fails(self) -> None:
        with xdref.XdPackage(self.xd_path) as package:
            with self.assertRaises(xdref.XdExportError):
                package.find_artboard_by_manifest_id("no-such-id")
            with self.assertRaises(xdref.XdExportError):
                package.find_artboard_by_manifest_id("")

    # -- 3/4/5: path -------------------------------------------------------
    def test_path_lookup_succeeds(self) -> None:
        with xdref.XdPackage(self.xd_path) as package:
            artboard = package.find_artboard_by_path(SPLASH_ARTWORK_PATH)
        self.assertEqual(artboard.manifest_id, SPLASH_MANIFEST_ID)

    def test_unknown_path_fails(self) -> None:
        with xdref.XdPackage(self.xd_path) as package:
            with self.assertRaises(xdref.XdExportError):
                package.find_artboard_by_path("artwork/artboard-nope")

    def test_trailing_slash_is_normalised(self) -> None:
        with xdref.XdPackage(self.xd_path) as package:
            artboard = package.find_artboard_by_path(SPLASH_ARTWORK_PATH + "/")
        self.assertEqual(artboard.manifest_id, SPLASH_MANIFEST_ID)

    def test_agc_file_path_is_rejected(self) -> None:
        with xdref.XdPackage(self.xd_path) as package:
            with self.assertRaises(xdref.XdExportError) as ctx:
                package.find_artboard_by_path(
                    SPLASH_ARTWORK_PATH + "/graphics/graphicContent.agc"
                )
        self.assertIn("AGC file path", str(ctx.exception))

    # -- 6: duplicate names stay fail-closed -------------------------------
    def test_duplicate_name_lookup_remains_ambiguous(self) -> None:
        with xdref.XdPackage(self.xd_path) as package:
            for duplicated in ("اعدادات المتجر", "الرسائل", "معاينة"):
                with self.subTest(name=duplicated):
                    with self.assertRaises(xdref.XdExportError) as ctx:
                        package.find_artboard_by_exact_name(duplicated)
                    self.assertIn("ambiguous", str(ctx.exception))
            # ...but each of them is still reachable by its unique id.
            for name, manifest_id, _uuid in MULTI_SPECS:
                self.assertEqual(
                    package.find_artboard_by_manifest_id(manifest_id).name, name
                )

    # -- 7/8/9: the Python API --------------------------------------------
    def test_positional_name_api_still_works(self) -> None:
        result = xdref.export_artboard(
            self.xd_path,
            "سبلاش – 1",
            output_svg=None,
            render_png=False,
            font_path=self.font_path,
        )
        self.assertEqual(result.report["selected_artboard_name"], "سبلاش – 1")

    def test_artboard_id_api_selection(self) -> None:
        result = xdref.export_artboard(
            self.xd_path,
            artboard_id=SPLASH_MANIFEST_ID,
            render_png=False,
            font_path=self.font_path,
        )
        report = result.report
        # All three identity fields are present whichever selector was used.
        self.assertEqual(report["selected_artboard_name"], "سبلاش – 1")
        self.assertEqual(report["selected_artboard_id"], SPLASH_MANIFEST_ID)
        self.assertEqual(report["selected_artboard_path"], SPLASH_ARTWORK_PATH)

    def test_artboard_path_api_selection(self) -> None:
        result = xdref.export_artboard(
            self.xd_path,
            artboard_path=SPLASH_ARTWORK_PATH,
            render_png=False,
            font_path=self.font_path,
        )
        report = result.report
        self.assertEqual(report["selected_artboard_name"], "سبلاش – 1")
        self.assertEqual(report["selected_artboard_id"], SPLASH_MANIFEST_ID)
        self.assertEqual(report["selected_artboard_path"], SPLASH_ARTWORK_PATH)

    def test_duplicate_name_artboards_are_individually_selectable(self) -> None:
        first, second = MULTI_SPECS[4], MULTI_SPECS[5]
        self.assertEqual(first[0], second[0])
        for name, manifest_id, artwork_uuid in (first, second):
            result = xdref.export_artboard(
                self.xd_path,
                artboard_id=manifest_id,
                render_png=False,
                font_path=self.font_path,
            )
            self.assertEqual(result.report["selected_artboard_name"], name)
            self.assertEqual(
                result.report["selected_artboard_path"],
                f"artwork/artboard-{artwork_uuid}",
            )

    # -- 10/11: selector arity --------------------------------------------
    def test_zero_selectors_rejected(self) -> None:
        with self.assertRaises(xdref.XdExportError) as ctx:
            xdref.export_artboard(self.xd_path, render_png=False)
        self.assertIn("exactly one", str(ctx.exception).lower())

    def test_multiple_selectors_rejected(self) -> None:
        combos = (
            {"artboard_name": "سبلاش – 1", "artboard_id": SPLASH_MANIFEST_ID},
            {"artboard_name": "سبلاش – 1", "artboard_path": SPLASH_ARTWORK_PATH},
            {"artboard_id": SPLASH_MANIFEST_ID, "artboard_path": SPLASH_ARTWORK_PATH},
        )
        for combo in combos:
            with self.subTest(combo=sorted(combo)):
                with self.assertRaises(xdref.XdExportError) as ctx:
                    xdref.export_artboard(self.xd_path, render_png=False, **combo)
                self.assertIn("exactly one", str(ctx.exception).lower())

    # -- K: rendering invariance across selectors --------------------------
    def test_all_selectors_render_identical_svg(self) -> None:
        by_name = xdref.export_artboard(
            self.xd_path,
            "سبلاش – 1",
            render_png=False,
            font_path=self.font_path,
        ).svg
        by_id = xdref.export_artboard(
            self.xd_path,
            artboard_id=SPLASH_MANIFEST_ID,
            render_png=False,
            font_path=self.font_path,
        ).svg
        by_path = xdref.export_artboard(
            self.xd_path,
            artboard_path=SPLASH_ARTWORK_PATH,
            render_png=False,
            font_path=self.font_path,
        ).svg
        self.assertEqual(by_name, by_id)
        self.assertEqual(by_name, by_path)


class TestArtboardOutputNaming(ExporterTestCase):
    def test_slugify_preserves_arabic_and_collapses_punctuation(self) -> None:
        self.assertEqual(xdref.slugify_artboard_name("سبلاش – 1"), "سبلاش-1")
        self.assertEqual(xdref.slugify_artboard_name("  من  نحن  "), "من-نحن")
        self.assertEqual(xdref.slugify_artboard_name("a/b\\c:d"), "a-b-c-d")
        self.assertEqual(xdref.slugify_artboard_name("--- ---"), "artboard")
        self.assertEqual(xdref.slugify_artboard_name(""), "artboard")
        self.assertEqual(xdref.slugify_artboard_name(None), "artboard")

    def test_output_stem_matches_the_documented_format(self) -> None:
        artboard = xdref.ManifestArtboard(
            name="سبلاش – 1",
            manifest_id=SPLASH_MANIFEST_ID,
            path=SPLASH_ARTWORK_PATH,
            x=0,
            y=0,
            width=375,
            height=812,
        )
        self.assertEqual(
            xdref.artboard_output_stem(17, artboard), "017--سبلاش-1--1ff58a48"
        )

    def test_output_stem_survives_a_missing_manifest_id(self) -> None:
        artboard = xdref.ManifestArtboard(
            name="x", manifest_id=None, path="artwork/artboard-x", x=0, y=0,
            width=1, height=1,
        )
        self.assertEqual(xdref.artboard_output_stem(3, artboard), "003--x--noid")


class TestBatchExport(ExporterTestCase):
    def setUp(self) -> None:
        super().setUp()
        self.xd_path = build_multi_artboard_xd(self.tmp_path)
        self.out_dir = self.tmp_path / "corpus"

    def run_batch(self, **kwargs: Any) -> Dict[str, Any]:
        kwargs.setdefault("font_path", self.font_path)
        kwargs.setdefault("render_png", False)
        return xdref.export_all_artboards(
            self.xd_path, kwargs.pop("output_dir", self.out_dir), **kwargs
        )

    # -- 19/20/21/23: every artboard, deterministic, unique ----------------
    def test_batch_exports_every_artboard_including_duplicate_names(self) -> None:
        summary = self.run_batch()
        self.assertEqual(summary["artboard_count"], len(MULTI_SPECS))
        self.assertEqual(summary["success_count"], len(MULTI_SPECS))
        self.assertEqual(summary["failure_count"], 0)
        self.assertEqual(len(summary["entries"]), len(MULTI_SPECS))

        # Duplicate human names must not collapse: 8 entries, 5 distinct names.
        names = [entry["name"] for entry in summary["entries"]]
        self.assertEqual(len(names), 8)
        self.assertEqual(len(set(names)), 5)

    def test_batch_output_stems_are_unique(self) -> None:
        summary = self.run_batch()
        stems = [entry["output_stem"] for entry in summary["entries"]]
        self.assertEqual(len(stems), len(set(stems)))
        svg_files = sorted(p.name for p in self.out_dir.glob("*.svg"))
        self.assertEqual(len(svg_files), len(MULTI_SPECS))

    def test_batch_preserves_deterministic_manifest_order(self) -> None:
        summary = self.run_batch()
        self.assertEqual(
            [entry["index"] for entry in summary["entries"]],
            list(range(1, len(MULTI_SPECS) + 1)),
        )
        self.assertEqual(
            [entry["manifest_id"] for entry in summary["entries"]],
            [spec[1] for spec in MULTI_SPECS],
        )
        self.assertTrue(summary["entries"][0]["output_stem"].startswith("001--"))
        self.assertEqual(
            summary["entries"][0]["output_stem"], "001--سبلاش-1--1ff58a48"
        )

    # -- 22: skip-png ------------------------------------------------------
    def test_skip_png_creates_no_pngs(self) -> None:
        summary = self.run_batch()
        self.assertTrue(summary["skip_png"])
        self.assertEqual(list(self.out_dir.glob("*.png")), [])
        for entry in summary["entries"]:
            self.assertIsNone(entry["output_png"])
            self.assertTrue(entry["output_svg"].endswith(".svg"))
            self.assertTrue(entry["report_json"].endswith(".report.json"))

    # -- 25: relative, machine-independent artifact paths ------------------
    def test_batch_artifact_paths_are_relative_and_stable(self) -> None:
        summary = self.run_batch()
        for entry in summary["entries"]:
            stem = entry["output_stem"]
            self.assertEqual(entry["output_svg"], f"{stem}.svg")
            self.assertEqual(entry["report_json"], f"{stem}.report.json")
            for key in ("output_svg", "report_json"):
                self.assertNotIn("/", entry[key])
                self.assertNotIn("\\", entry[key])
                self.assertTrue((self.out_dir / entry[key]).is_file())

    # -- 24: serialization -------------------------------------------------
    def test_batch_report_round_trips_as_json(self) -> None:
        summary = self.run_batch()
        report_path = self.out_dir / xdref.BATCH_REPORT_FILENAME
        self.assertTrue(report_path.is_file())

        loaded = json.loads(report_path.read_text(encoding="utf-8"))
        self.assertEqual(loaded["schema"], "merzox.xd_reference_batch/1")
        self.assertEqual(loaded["iteration"], "MERZOX-UI-GOLDEN-I3-R2-D7-I1")
        self.assertEqual(loaded["artboard_count"], len(MULTI_SPECS))
        self.assertEqual(
            json.loads(json.dumps(summary, ensure_ascii=False))["entries"][0]["name"],
            "سبلاش – 1",
        )
        # The batch schema is independent of the single-artboard report schema.
        self.assertNotEqual(loaded["schema"], xdref.REPORT_SCHEMA)

    def test_batch_entries_carry_report_rollups(self) -> None:
        summary = self.run_batch()
        entry = summary["entries"][0]
        for key in (
            "unsupported_node_counts",
            "warning_count",
            "pattern_fill_count",
            "resolved_pattern_fill_count",
            "brand_replacement_count",
            "blend_mode_application_counts",
        ):
            self.assertIn(key, entry)
        self.assertEqual(entry["status"], "success")
        self.assertIsInstance(entry["warning_count"], int)
        self.assertEqual(entry["artboard_bounds"]["width"], 375.0)

    # -- I: normalization applies to every entry ---------------------------
    def test_brand_normalization_applies_to_every_batch_entry(self) -> None:
        raw = self.run_batch()
        self.assertFalse(raw["normalize_merzox_brand"])
        for entry in raw["entries"]:
            self.assertEqual(entry["brand_replacement_count"], 0)

        normalized = xdref.export_all_artboards(
            self.xd_path,
            self.tmp_path / "corpus-normalized",
            normalize_brand=True,
            font_path=self.font_path,
            render_png=False,
        )
        self.assertTrue(normalized["normalize_merzox_brand"])
        for entry in normalized["entries"]:
            self.assertEqual(entry["brand_replacement_count"], 1)
        svg = (
            self.tmp_path / "corpus-normalized" / f"{normalized['entries'][0]['output_stem']}.svg"
        ).read_text(encoding="utf-8")
        self.assertIn(">Merzox app</text>", svg)
        self.assertNotIn(">Bictov app</text>", svg)

    # -- 18/F: output directory safety -------------------------------------
    def test_missing_output_dir_is_created(self) -> None:
        fresh = self.tmp_path / "made" / "here"
        self.run_batch(output_dir=fresh)
        self.assertTrue(fresh.is_dir())

    def test_empty_output_dir_is_accepted(self) -> None:
        empty = self.tmp_path / "empty"
        empty.mkdir()
        summary = self.run_batch(output_dir=empty)
        self.assertEqual(summary["failure_count"], 0)

    def test_non_empty_output_dir_is_rejected(self) -> None:
        occupied = self.tmp_path / "occupied"
        occupied.mkdir()
        stale = occupied / "stale.svg"
        stale.write_text("old corpus", encoding="utf-8")

        with self.assertRaises(xdref.XdExportError) as ctx:
            self.run_batch(output_dir=occupied)
        self.assertIn("not empty", str(ctx.exception))
        # Nothing was deleted or overwritten.
        self.assertEqual(stale.read_text(encoding="utf-8"), "old corpus")
        self.assertEqual(sorted(p.name for p in occupied.iterdir()), ["stale.svg"])

    def test_output_dir_that_is_a_file_is_rejected(self) -> None:
        blocker = self.tmp_path / "not-a-dir"
        blocker.write_text("x", encoding="utf-8")
        with self.assertRaises(xdref.XdExportError):
            self.run_batch(output_dir=blocker)

    # -- 26/H: failure semantics -------------------------------------------
    def test_failed_artboard_is_recorded_and_the_batch_continues(self) -> None:
        broken_xd = build_multi_artboard_xd(
            self.tmp_path, filename="broken.xd", broken_indices=(2,)
        )
        summary = xdref.export_all_artboards(
            broken_xd,
            self.tmp_path / "broken-corpus",
            font_path=self.font_path,
            render_png=False,
        )
        self.assertEqual(summary["artboard_count"], len(MULTI_SPECS))
        self.assertEqual(summary["failure_count"], 1)
        self.assertEqual(summary["success_count"], len(MULTI_SPECS) - 1)

        failed = [e for e in summary["entries"] if e["status"] != "success"]
        self.assertEqual(len(failed), 1)
        self.assertEqual(failed[0]["index"], 3)
        self.assertIn("graphicContent.agc", failed[0]["error"])
        self.assertIsNone(failed[0]["output_svg"])
        # Later artboards were still exported.
        self.assertEqual(summary["entries"][-1]["status"], "success")

    def test_unsupported_features_do_not_count_as_batch_failures(self) -> None:
        summary = self.run_batch()
        self.assertEqual(summary["failure_count"], 0)
        # Renderer limitations are report data, not process failures.
        for entry in summary["entries"]:
            self.assertEqual(entry["status"], "success")
            self.assertIsInstance(entry["unsupported_node_counts"], dict)


class TestBatchAndSelectorCli(ExporterTestCase):
    def setUp(self) -> None:
        super().setUp()
        self.xd_path = build_multi_artboard_xd(self.tmp_path)

    def run_cli(self, argv: Any) -> int:
        buffer = io.StringIO()
        with contextlib.redirect_stdout(buffer), contextlib.redirect_stderr(buffer):
            code = xdref.main([str(part) for part in argv])
        self.last_output = buffer.getvalue()
        return code

    # -- 12/13/14: single-artboard selectors -------------------------------
    def test_cli_accepts_each_single_selector(self) -> None:
        selectors = (
            ("--artboard-name", "سبلاش – 1"),
            ("--artboard-id", SPLASH_MANIFEST_ID),
            ("--artboard-path", SPLASH_ARTWORK_PATH),
        )
        for index, (flag, value) in enumerate(selectors):
            with self.subTest(flag=flag):
                svg_out = self.tmp_path / f"cli-{index}.svg"
                code = self.run_cli(
                    [
                        "--xd", self.xd_path,
                        flag, value,
                        "--output-svg", svg_out,
                        "--font", self.font_path,
                        "--skip-png",
                    ]
                )
                self.assertEqual(code, 0, self.last_output)
                self.assertTrue(svg_out.is_file())

    def test_cli_rejects_zero_and_multiple_selectors(self) -> None:
        base = ["--xd", self.xd_path, "--output-svg", self.tmp_path / "x.svg"]
        self.assertEqual(self.run_cli(base), 2)
        self.assertIn("exactly one", self.last_output.lower())

        self.assertEqual(
            self.run_cli(
                base + ["--artboard-name", "من نحن", "--artboard-id", SPLASH_MANIFEST_ID]
            ),
            2,
        )
        self.assertIn("exactly one", self.last_output.lower())

    def test_cli_list_artboards_exposes_identity(self) -> None:
        code = self.run_cli(["--xd", self.xd_path, "--list-artboards"])
        self.assertEqual(code, 0)
        lines = [line for line in self.last_output.splitlines() if line.strip()]
        self.assertEqual(len(lines), len(MULTI_SPECS))
        name, manifest_id, path, bounds = lines[0].split("\t")
        self.assertEqual(name, "سبلاش – 1")
        self.assertEqual(manifest_id, SPLASH_MANIFEST_ID)
        self.assertEqual(path, SPLASH_ARTWORK_PATH)
        self.assertEqual(bounds, "375x812")

    # -- 15/16/17/J: batch conflicts ---------------------------------------
    def test_all_artboards_rejects_single_selectors(self) -> None:
        for flag, value in (
            ("--artboard-name", "من نحن"),
            ("--artboard-id", SPLASH_MANIFEST_ID),
            ("--artboard-path", SPLASH_ARTWORK_PATH),
        ):
            with self.subTest(flag=flag):
                code = self.run_cli(
                    [
                        "--xd", self.xd_path,
                        "--all-artboards",
                        "--output-dir", self.tmp_path / "never",
                        flag, value,
                    ]
                )
                self.assertEqual(code, 2)
                self.assertIn("cannot be combined", self.last_output)

    def test_all_artboards_requires_output_dir(self) -> None:
        code = self.run_cli(["--xd", self.xd_path, "--all-artboards"])
        self.assertEqual(code, 2)
        self.assertIn("--all-artboards requires --output-dir", self.last_output)

    def test_all_artboards_rejects_single_file_outputs(self) -> None:
        for flag in ("--output-svg", "--output-png", "--report-json"):
            with self.subTest(flag=flag):
                code = self.run_cli(
                    [
                        "--xd", self.xd_path,
                        "--all-artboards",
                        "--output-dir", self.tmp_path / "never",
                        flag, self.tmp_path / "x",
                    ]
                )
                self.assertEqual(code, 2)
                self.assertIn("cannot be combined", self.last_output)

    def test_output_dir_requires_all_artboards(self) -> None:
        code = self.run_cli(
            [
                "--xd", self.xd_path,
                "--artboard-id", SPLASH_MANIFEST_ID,
                "--output-svg", self.tmp_path / "x.svg",
                "--output-dir", self.tmp_path / "nope",
            ]
        )
        self.assertEqual(code, 2)
        self.assertIn("only valid with --all-artboards", self.last_output)

    # -- end-to-end batch through the CLI ----------------------------------
    def test_cli_batch_succeeds_and_writes_the_corpus(self) -> None:
        out_dir = self.tmp_path / "cli-corpus"
        code = self.run_cli(
            [
                "--xd", self.xd_path,
                "--all-artboards",
                "--output-dir", out_dir,
                "--font", self.font_path,
                "--skip-png",
            ]
        )
        self.assertEqual(code, 0, self.last_output)
        self.assertEqual(len(list(out_dir.glob("*.svg"))), len(MULTI_SPECS))
        self.assertEqual(len(list(out_dir.glob("*.report.json"))), len(MULTI_SPECS))
        self.assertTrue((out_dir / xdref.BATCH_REPORT_FILENAME).is_file())

    def test_cli_batch_returns_non_zero_when_an_artboard_fails(self) -> None:
        broken_xd = build_multi_artboard_xd(
            self.tmp_path, filename="cli-broken.xd", broken_indices=(0,)
        )
        out_dir = self.tmp_path / "cli-broken-corpus"
        code = self.run_cli(
            [
                "--xd", broken_xd,
                "--all-artboards",
                "--output-dir", out_dir,
                "--font", self.font_path,
                "--skip-png",
            ]
        )
        self.assertEqual(code, 1)
        summary = json.loads(
            (out_dir / xdref.BATCH_REPORT_FILENAME).read_text(encoding="utf-8")
        )
        self.assertEqual(summary["failure_count"], 1)
        self.assertNotEqual(summary["success_count"], summary["artboard_count"])

    def test_cli_batch_refuses_a_non_empty_output_dir(self) -> None:
        out_dir = self.tmp_path / "dirty"
        out_dir.mkdir()
        (out_dir / "leftover.png").write_bytes(TINY_PNG)
        code = self.run_cli(
            [
                "--xd", self.xd_path,
                "--all-artboards",
                "--output-dir", out_dir,
                "--font", self.font_path,
                "--skip-png",
            ]
        )
        self.assertEqual(code, 2)
        self.assertIn("not empty", self.last_output)
        self.assertEqual(sorted(p.name for p in out_dir.iterdir()), ["leftover.png"])


class TestBatchStatusVocabulary(ExporterTestCase):
    """The external batch contract uses exactly 'success' / 'failed'."""

    def setUp(self) -> None:
        super().setUp()
        self.xd_path = build_multi_artboard_xd(self.tmp_path)

    def batch(self, xd_path: Path, out_name: str) -> Dict[str, Any]:
        return xdref.export_all_artboards(
            xd_path,
            self.tmp_path / out_name,
            font_path=self.font_path,
            render_png=False,
        )

    def test_status_constants(self) -> None:
        self.assertEqual(xdref.BATCH_STATUS_SUCCESS, "success")
        self.assertEqual(xdref.BATCH_STATUS_FAILED, "failed")

    def test_successful_entry_status_is_success(self) -> None:
        summary = self.batch(self.xd_path, "vocab")
        self.assertEqual(summary["failure_count"], 0)
        self.assertEqual(summary["success_count"], len(MULTI_SPECS))
        for entry in summary["entries"]:
            self.assertEqual(entry["status"], "success")

    def test_no_successful_entry_uses_ok(self) -> None:
        out_dir = self.tmp_path / "vocab-ok"
        xdref.export_all_artboards(
            self.xd_path, out_dir, font_path=self.font_path, render_png=False
        )
        raw = (out_dir / xdref.BATCH_REPORT_FILENAME).read_text(encoding="utf-8")
        self.assertIn('"status": "success"', raw)
        self.assertNotIn('"status": "ok"', raw)
        # No compatibility alias carrying both spellings.
        self.assertNotIn('"ok"', raw)

    def test_unsupported_features_still_report_success(self) -> None:
        xd_path = build_multi_artboard_xd(
            self.tmp_path,
            filename="unsupported.xd",
            extra_nodes=[{"type": "hologram", "id": "unsupported-node"}],
        )
        summary = self.batch(xd_path, "vocab-unsupported")

        self.assertEqual(summary["failure_count"], 0)
        for entry in summary["entries"]:
            self.assertEqual(entry["status"], "success")
            # The limitation is reported, and is explicitly not a failure.
            self.assertIn("node:hologram", entry["unsupported_node_counts"])

    def test_failed_entry_status_is_failed(self) -> None:
        broken = build_multi_artboard_xd(
            self.tmp_path, filename="vocab-broken.xd", broken_indices=(1,)
        )
        summary = self.batch(broken, "vocab-failed")

        failed = [e for e in summary["entries"] if e["status"] != "success"]
        self.assertEqual(len(failed), 1)
        self.assertEqual(failed[0]["status"], "failed")
        self.assertEqual(summary["failure_count"], 1)
        self.assertEqual(summary["success_count"], len(MULTI_SPECS) - 1)

    def test_batch_metadata_constants_are_unchanged(self) -> None:
        summary = self.batch(self.xd_path, "vocab-meta")
        self.assertEqual(xdref.EXPORTER_ITERATION, "MERZOX-UI-GOLDEN-I3-R2-D7-I1")
        self.assertEqual(summary["iteration"], "MERZOX-UI-GOLDEN-I3-R2-D7-I1")
        self.assertEqual(xdref.BATCH_REPORT_SCHEMA, "merzox.xd_reference_batch/1")
        self.assertEqual(summary["schema"], "merzox.xd_reference_batch/1")


class TestAmbiguousNameDiagnostic(ExporterTestCase):
    """The attempted selector text must survive into the diagnostic.

    The regression was an encoding one: the name reached the message intact but
    was written to stderr in the host ANSI code page (cp1256 on this machine),
    so a UTF-8 consumer dropped the bytes and saw an empty name.
    """

    DUPLICATED = ("اعدادات المتجر", "الرسائل", "معاينة")

    def setUp(self) -> None:
        super().setUp()
        self.xd_path = build_multi_artboard_xd(self.tmp_path)

    def test_lookup_error_preserves_every_duplicated_name(self) -> None:
        with xdref.XdPackage(self.xd_path) as package:
            for name in self.DUPLICATED:
                with self.subTest(name=name):
                    with self.assertRaises(xdref.XdExportError) as ctx:
                        package.find_artboard_by_exact_name(name)
                    message = str(ctx.exception)
                    self.assertIn(name, message)
                    self.assertIn("ambiguous", message)

    def test_export_api_error_preserves_the_attempted_name(self) -> None:
        with self.assertRaises(xdref.XdExportError) as ctx:
            xdref.export_artboard(
                self.xd_path,
                "الرسائل",
                render_png=False,
                font_path=self.font_path,
            )
        self.assertIn("الرسائل", str(ctx.exception))

    def test_ambiguous_diagnostic_offers_the_stable_selectors(self) -> None:
        with xdref.XdPackage(self.xd_path) as package:
            with self.assertRaises(xdref.XdExportError) as ctx:
                package.find_artboard_by_exact_name("الرسائل")
        message = str(ctx.exception)
        # Manifest ids are ASCII and stay readable in any terminal.
        self.assertIn(MULTI_SPECS[4][1], message)
        self.assertIn(MULTI_SPECS[5][1], message)
        self.assertIn("--artboard-id", message)

    def test_cli_stderr_is_utf8_and_keeps_the_name(self) -> None:
        """End-to-end through a real subprocess: only that exercises encoding."""
        for name in self.DUPLICATED:
            with self.subTest(name=name):
                proc = subprocess.run(
                    [
                        sys.executable,
                        str(Path(xdref.__file__).resolve()),
                        "--xd", str(self.xd_path),
                        "--artboard-name", name,
                        "--output-svg", str(self.tmp_path / "never.svg"),
                        "--font", str(self.font_path),
                        "--skip-png",
                    ],
                    capture_output=True,
                )
                self.assertNotEqual(proc.returncode, 0)
                # Decoding as UTF-8 must not lose the attempted selector.
                stderr = proc.stderr.decode("utf-8")
                self.assertIn(name, stderr)
                self.assertIn("ambiguous", stderr)
                # Fail-closed: nothing was rendered.
                self.assertFalse((self.tmp_path / "never.svg").exists())

    def test_cli_list_artboards_stdout_is_utf8(self) -> None:
        proc = subprocess.run(
            [
                sys.executable,
                str(Path(xdref.__file__).resolve()),
                "--xd", str(self.xd_path),
                "--list-artboards",
            ],
            capture_output=True,
        )
        self.assertEqual(proc.returncode, 0)
        stdout = proc.stdout.decode("utf-8")
        for name, _manifest_id, _uuid in MULTI_SPECS:
            self.assertIn(name, stdout)

    def test_duplicate_name_remains_fail_closed(self) -> None:
        """No first-match selection, and unique selectors still work."""
        with xdref.XdPackage(self.xd_path) as package:
            with self.assertRaises(xdref.XdExportError):
                package.find_artboard_by_exact_name("الرسائل")
            for name, manifest_id, artwork_uuid in MULTI_SPECS:
                artboard = package.find_artboard_by_manifest_id(manifest_id)
                self.assertEqual(artboard.name, name)
                self.assertEqual(artboard.path, f"artwork/artboard-{artwork_uuid}")


# ---------------------------------------------------------------------------
# I3-R2-I1: syncSourceGuid is the source selector; guid is the instance.
# ---------------------------------------------------------------------------


#: Distinct on purpose: the defect was using the instance guid as the source key.
INSTANCE_GUID = "11111111-aaaa-4000-8000-instance00001"
SOURCE_GUID = "22222222-bbbb-4000-8000-source0000001"
TEXT_SOURCE_GUID = "33333333-cccc-4000-8000-source0000002"


def border_source_node(guid: str = SOURCE_GUID) -> Dict[str, Any]:
    """An identity-bearing leaf shape, like the real 'Border' definitions."""
    return {
        "type": "shape",
        "id": "border-def",
        "name": "Border",
        "guid": guid,
        "transform": {"a": 1, "b": 0, "c": 0, "d": 1, "tx": 5, "ty": 7},
        "shape": {"type": "rect", "x": 0, "y": 0, "width": 40, "height": 2},
        "style": {"fill": solid_fill(0x11, 0x22, 0x33), "opacity": 0.75},
    }


def capacity_source_node(guid: str = TEXT_SOURCE_GUID) -> Dict[str, Any]:
    """An identity-bearing leaf text node, like the real 'Capacity' definition."""
    return {
        "type": "text",
        "id": "capacity-def",
        "name": "Capacity",
        "guid": guid,
        "transform": {"a": 1, "b": 0, "c": 0, "d": 1, "tx": 9, "ty": 11},
        "style": {
            "font": {"family": "Tajawal", "style": "Regular", "size": 12},
            "fill": solid_fill(0x44, 0x55, 0x66),
        },
        "text": {
            "rawText": "Capacity",
            "paragraphs": [{"lines": [[{"from": 0, "to": 8, "x": 0, "y": 0}]]}],
        },
    }


def shared_agc_with(*definitions: Dict[str, Any]) -> Dict[str, Any]:
    return {
        "version": "3.0.0",
        "artboards": {},
        "resources": {"meta": {"ux": {"symbols": list(definitions)}}},
        "children": [],
    }


def sync_ref_instance(
    source_guid: Optional[str] = SOURCE_GUID,
    instance_guid: Optional[str] = INSTANCE_GUID,
    tx: float = 23,
    ty: float = 3.6666667461395264,
    node_id: str = "sync-instance",
) -> Dict[str, Any]:
    """A flat modern XD syncRef node as it appears in the real package."""
    node: Dict[str, Any] = {
        "type": "syncRef",
        "id": node_id,
        "transform": {"a": 1, "b": 0, "c": 0, "d": 1, "tx": tx, "ty": ty},
    }
    if instance_guid is not None:
        node["guid"] = instance_guid
    if source_guid is not None:
        node["syncSourceGuid"] = source_guid
    return node


class TestSyncSourceGuidResolution(ExporterTestCase):
    def setUp(self) -> None:
        super().setUp()
        self.symbol_lookups: List[Any] = []
        original = xdref.AgcResourceIndex.symbol

        def spy(index_self: Any, symbol_id: Any) -> Any:
            self.symbol_lookups.append(symbol_id)
            return original(index_self, symbol_id)

        xdref.AgcResourceIndex.symbol = spy
        self.addCleanup(setattr, xdref.AgcResourceIndex, "symbol", original)

    def build(
        self, children: List[Dict[str, Any]], definitions: Any = None
    ) -> xdref.ExportResult:
        if definitions is None:
            definitions = [border_source_node()]
        xd_path = build_xd(
            self.tmp_path,
            children,
            shared_agc=shared_agc_with(*definitions),
        )
        return self.export(xd_path)

    # -- 1/2/3/14: the canonical identity rule -----------------------------
    def test_flat_sync_ref_prefers_sync_source_guid(self) -> None:
        result = self.build([sync_ref_instance()])
        self.assertEqual(result.report["resolved_sync_refs"], 1)
        self.assertIn(SOURCE_GUID, self.symbol_lookups)

    def test_instance_guid_is_never_used_as_the_source_key(self) -> None:
        self.assertNotEqual(INSTANCE_GUID, SOURCE_GUID)
        self.build([sync_ref_instance()])
        self.assertNotIn(INSTANCE_GUID, self.symbol_lookups)
        self.assertEqual(self.symbol_lookups, [SOURCE_GUID])

    def test_source_guid_wins_even_when_the_instance_guid_also_resolves(self) -> None:
        """A decoy definition indexed under the instance guid must be ignored."""
        decoy = {
            "type": "shape",
            "id": "decoy",
            "name": "Decoy",
            "guid": INSTANCE_GUID,
            "shape": {"type": "rect", "x": 0, "y": 0, "width": 9, "height": 9},
            "style": {"fill": solid_fill(0xFF, 0x00, 0xFF)},
        }
        result = self.build([sync_ref_instance()], [border_source_node(), decoy])

        self.assertEqual(self.symbol_lookups, [SOURCE_GUID])
        self.assertIn('fill="#112233"', result.svg)  # the real source
        self.assertNotIn("#ff00ff", result.svg)  # never the instance-guid decoy

    # -- 4/5: placement and source fidelity --------------------------------
    def test_instance_transform_is_preserved(self) -> None:
        result = self.build([sync_ref_instance()])
        self.assertIn('<g transform="matrix(1 0 0 1 23 3.666667)">', result.svg)

    def test_second_real_placement_shape_is_preserved(self) -> None:
        result = self.build(
            [sync_ref_instance(tx=2, ty=1.9999998807907104)]
        )
        self.assertIn('transform="matrix(1 0 0 1 2 2)"', result.svg)

    def test_source_leaf_transform_and_style_survive(self) -> None:
        result = self.build([sync_ref_instance()])
        # The source keeps its own transform, opacity and fill under the wrapper.
        self.assertIn('transform="matrix(1 0 0 1 5 7)"', result.svg)
        self.assertIn('opacity="0.75"', result.svg)
        self.assertIn('<rect x="0" y="0" width="40" height="2" fill="#112233"/>', result.svg)

    # -- 6: text leaf ------------------------------------------------------
    def test_text_source_resolves_through_sync_source_guid(self) -> None:
        result = self.build(
            [sync_ref_instance(source_guid=TEXT_SOURCE_GUID)],
            [capacity_source_node()],
        )
        self.assertEqual(self.symbol_lookups, [TEXT_SOURCE_GUID])
        self.assertIn(">Capacity</text>", result.svg)
        self.assertIn('transform="matrix(1 0 0 1 9 11)"', result.svg)
        self.assertEqual(result.report["text_node_count"], 1)

    # -- 7/8/9: reporting --------------------------------------------------
    def test_successful_resolution_reporting(self) -> None:
        report = self.build([sync_ref_instance()]).report
        self.assertEqual(report["resolved_sync_refs"], 1)
        self.assertEqual(report["unresolved_sync_refs"], 0)
        self.assertEqual(report["handled_node_counts"]["syncRef"], 1)
        self.assertNotIn("syncRef:unresolved", report["unsupported_node_counts"])

    def test_multiple_instances_share_one_source(self) -> None:
        """Distinct instances of one source all resolve; no false recursion."""
        result = self.build(
            [
                sync_ref_instance(node_id="a", instance_guid="inst-a", tx=1, ty=1),
                sync_ref_instance(node_id="b", instance_guid="inst-b", tx=2, ty=2),
            ]
        )
        self.assertEqual(result.report["resolved_sync_refs"], 2)
        self.assertEqual(result.report["unresolved_sync_refs"], 0)
        self.assertEqual(self.symbol_lookups, [SOURCE_GUID, SOURCE_GUID])

    # -- 10: legacy fallback -----------------------------------------------
    def test_missing_sync_source_guid_uses_the_legacy_fallback(self) -> None:
        legacy = {
            "type": "syncRef",
            "id": "legacy",
            "guid": SOURCE_GUID,  # old fixtures put the source key in guid
            "transform": {"a": 1, "b": 0, "c": 0, "d": 1, "tx": 4, "ty": 6},
        }
        result = self.build([legacy])
        self.assertEqual(result.report["resolved_sync_refs"], 1)
        self.assertEqual(self.symbol_lookups, [SOURCE_GUID])
        self.assertIn('transform="matrix(1 0 0 1 4 6)"', result.svg)

    def test_identity_helper_reports_the_selector_used(self) -> None:
        renderer_cls = xdref.AgcRenderer
        modern = sync_ref_instance()
        self.assertEqual(
            renderer_cls._sync_ref_identity(renderer_cls, modern, {}),
            (INSTANCE_GUID, SOURCE_GUID, "syncSourceGuid"),
        )
        legacy = {"type": "syncRef", "guid": SOURCE_GUID}
        self.assertEqual(
            renderer_cls._sync_ref_identity(renderer_cls, legacy, {}),
            (SOURCE_GUID, SOURCE_GUID, "legacy-fallback"),
        )
        nested = {"type": "syncRef"}
        self.assertEqual(
            renderer_cls._sync_ref_identity(renderer_cls, nested, {"ref": "sym-1"}),
            (None, "sym-1", "legacy-fallback"),
        )

    # -- 11/12: fail-closed and diagnostics --------------------------------
    def test_missing_source_definition_remains_fail_closed(self) -> None:
        missing = "99999999-dddd-4000-8000-missing000001"
        result = self.build([sync_ref_instance(source_guid=missing)])
        report = result.report

        self.assertEqual(report["resolved_sync_refs"], 0)
        self.assertEqual(report["unresolved_sync_refs"], 1)
        self.assertIn("syncRef:unresolved", report["unsupported_node_counts"])
        self.assertNotIn("#112233", result.svg)

    def test_unresolved_diagnostic_names_instance_and_source(self) -> None:
        missing = "99999999-dddd-4000-8000-missing000001"
        report = self.build([sync_ref_instance(source_guid=missing)]).report
        warnings = [w for w in report["warnings"] if "syncRef" in w]
        self.assertTrue(warnings, report["warnings"])
        warning = warnings[0]
        self.assertIn(missing, warning)
        self.assertIn(INSTANCE_GUID, warning)
        self.assertIn("syncSourceGuid", warning)

    # -- 13: recursion protection keyed on the source guid ------------------
    def test_recursion_is_keyed_on_the_source_guid(self) -> None:
        recursive_source = {
            "type": "group",
            "id": "recursive-def",
            "name": "Recursive",
            "guid": SOURCE_GUID,
            "group": {
                "children": [
                    # A different instance guid, but the same source: recursion.
                    sync_ref_instance(
                        instance_guid="inner-instance", node_id="inner", tx=0, ty=0
                    )
                ]
            },
        }
        result = self.build([sync_ref_instance()], [recursive_source])
        report = result.report

        self.assertEqual(report["resolved_sync_refs"], 1)
        self.assertEqual(report["unresolved_sync_refs"], 1)
        self.assertTrue(
            any("recursive reference" in w for w in report["warnings"]),
            report["warnings"],
        )

    # -- 15/16: metadata ----------------------------------------------------
    def test_iteration_and_batch_schema(self) -> None:
        self.assertEqual(xdref.EXPORTER_ITERATION, "MERZOX-UI-GOLDEN-I3-R2-D7-I1")
        self.assertEqual(xdref.BATCH_REPORT_SCHEMA, "merzox.xd_reference_batch/1")
        self.assertEqual(xdref.REPORT_SCHEMA, "merzox.xd_reference_exporter/1")
        report = self.build([sync_ref_instance()]).report
        self.assertEqual(report["iteration"], "MERZOX-UI-GOLDEN-I3-R2-D7-I1")


# ---------------------------------------------------------------------------
# I3-R2-I3: closed inside-stroke emulation.
# ---------------------------------------------------------------------------


def inside_stroke(width: Any = 1, **extra: Any) -> Dict[str, Any]:
    stroke: Dict[str, Any] = {
        "type": "solid",
        "color": {"mode": "RGB", "value": {"r": 0, "g": 0, "b": 0}},
        "width": width,
        "align": "inside",
    }
    stroke.update(extra)
    return stroke


def shape_node(
    shape: Dict[str, Any],
    style: Dict[str, Any],
    node_id: str = "shape-1",
    transform: Optional[Dict[str, Any]] = None,
) -> Dict[str, Any]:
    node: Dict[str, Any] = {
        "type": "shape",
        "id": node_id,
        "shape": shape,
        "style": style,
    }
    if transform is not None:
        node["transform"] = transform
    return node


class TestInsideStrokeEmulation(ExporterTestCase):
    RECT = {"type": "rect", "x": 0, "y": 0, "width": 100, "height": 100}
    CIRCLE = {"type": "circle", "cx": 50, "cy": 50, "r": 20}
    CLOSED_PATH = {"type": "path", "path": "M0 0 L10 0 L10 10 Z"}
    OPEN_PATH = {"type": "path", "path": "M0 0 L10 0 L10 10"}
    LINE = {"type": "line", "x1": 0, "y1": 0, "x2": 10, "y2": 10}

    def render(
        self,
        shape: Dict[str, Any],
        style: Dict[str, Any],
        transform: Optional[Dict[str, Any]] = None,
        nodes: Any = None,
    ) -> xdref.ExportResult:
        children = (
            nodes
            if nodes is not None
            else [shape_node(shape, style, transform=transform)]
        )
        return self.export(build_xd(self.tmp_path, children))

    def lines(self, svg: str, needle: str) -> List[str]:
        return [line for line in svg.splitlines() if needle in line]

    # -- 1/2/3: eligible geometries produce a clipPath ---------------------
    def test_inside_rect_creates_clip_path(self) -> None:
        result = self.render(self.RECT, {"fill": solid_fill(1, 2, 3), "stroke": inside_stroke()})
        self.assertIn(
            '<clipPath id="mxg-inside-stroke-1" clipPathUnits="userSpaceOnUse">'
            '<rect x="0" y="0" width="100" height="100"/></clipPath>',
            result.svg,
        )
        self.assertIn('clip-path="url(#mxg-inside-stroke-1)"', result.svg)

    def test_inside_circle_creates_clip_path(self) -> None:
        result = self.render(self.CIRCLE, {"fill": {"type": "none"}, "stroke": inside_stroke()})
        self.assertIn(
            '<clipPath id="mxg-inside-stroke-1" clipPathUnits="userSpaceOnUse">'
            '<circle cx="50" cy="50" r="20"/></clipPath>',
            result.svg,
        )

    def test_inside_closed_path_creates_clip_path(self) -> None:
        result = self.render(
            self.CLOSED_PATH, {"fill": {"type": "none"}, "stroke": inside_stroke()}
        )
        self.assertIn(
            '<clipPath id="mxg-inside-stroke-1" clipPathUnits="userSpaceOnUse">'
            '<path d="M0 0 L10 0 L10 10 Z"/></clipPath>',
            result.svg,
        )

    # -- 4: width doubling --------------------------------------------------
    def test_stroke_width_doubles_for_every_real_corpus_width(self) -> None:
        for original, doubled in (
            (0.3, "0.6"),
            (0.5, "1"),
            (1, "2"),
            (1.5, "3"),
        ):
            with self.subTest(width=original):
                result = self.render(
                    self.RECT,
                    {"fill": {"type": "none"}, "stroke": inside_stroke(original)},
                )
                stroke_lines = self.lines(result.svg, "data-xd-stroke-align")
                self.assertEqual(len(stroke_lines), 1)
                self.assertIn(f'stroke-width="{doubled}"', stroke_lines[0])

    # -- 5/6: the fill/stroke split ----------------------------------------
    def test_fill_renders_exactly_once_and_stroke_copy_has_no_fill(self) -> None:
        result = self.render(
            self.RECT, {"fill": solid_fill(0x12, 0x34, 0x56), "stroke": inside_stroke()}
        )
        self.assertEqual(result.svg.count('fill="#123456"'), 1)

        stroke_lines = self.lines(result.svg, "data-xd-stroke-align")
        self.assertEqual(len(stroke_lines), 1)
        self.assertIn('fill="none"', stroke_lines[0])
        self.assertNotIn("#123456", stroke_lines[0])

        fill_lines = [
            line
            for line in self.lines(result.svg, "#123456")
            if "data-xd-stroke-align" not in line
        ]
        self.assertEqual(len(fill_lines), 1)
        self.assertNotIn("stroke=", fill_lines[0])

    def test_unfilled_shape_still_clips_the_inside_stroke(self) -> None:
        result = self.render(
            self.RECT, {"fill": {"type": "none"}, "stroke": inside_stroke()}
        )
        self.assertIn('<clipPath id="mxg-inside-stroke-1"', result.svg)
        self.assertIn('clip-path="url(#mxg-inside-stroke-1)"', result.svg)

    # -- 7: clip geometry matches the visible geometry ----------------------
    def test_clip_geometry_matches_visible_geometry(self) -> None:
        result = self.render(
            self.CIRCLE, {"fill": solid_fill(1, 2, 3), "stroke": inside_stroke()}
        )
        for fragment in ('cx="50"', 'cy="50"', 'r="20"'):
            # once in the clip, once on the fill copy, once on the stroke copy
            self.assertEqual(result.svg.count(fragment), 3, fragment)

    def test_compound_even_odd_becomes_clip_rule(self) -> None:
        compound = {
            "type": "shape",
            "id": "compound-inside",
            "shape": {
                "type": "compound",
                "operation": "subtract",
                "path": "M0 0 H10 V10 H0 Z",
            },
            "style": {"fill": solid_fill(1, 2, 3), "stroke": inside_stroke()},
        }
        result = self.render(self.RECT, {}, nodes=[compound])
        self.assertIn('clip-rule="evenodd"', result.svg)
        self.assertIn('<clipPath id="mxg-inside-stroke-1"', result.svg)

    # -- 8/9/24: node semantics apply exactly once --------------------------
    def test_transform_is_applied_once_to_the_composite(self) -> None:
        result = self.render(
            self.RECT,
            {"fill": solid_fill(1, 2, 3), "stroke": inside_stroke()},
            transform={"a": 1, "b": 0, "c": 0, "d": 1, "tx": 12, "ty": 34},
        )
        self.assertEqual(result.svg.count("matrix(1 0 0 1 12 34)"), 1)
        # Both painted copies live inside that single wrapper: the shape's own
        # geometry appears three times (clip region + fill copy + stroke copy).
        self.assertEqual(
            len(self.lines(result.svg, '<rect x="0" y="0" width="100" height="100"')),
            3,
        )

    def test_opacity_is_applied_once_to_the_composite(self) -> None:
        result = self.render(
            self.RECT,
            {"fill": solid_fill(1, 2, 3), "opacity": 0.5, "stroke": inside_stroke()},
        )
        self.assertEqual(result.svg.count('opacity="0.5"'), 1)

    def test_node_clip_and_inside_clip_are_not_conflated(self) -> None:
        node = shape_node(
            self.RECT,
            {
                "fill": solid_fill(1, 2, 3),
                "stroke": inside_stroke(),
                "clipPath": {"ref": "cp1"},
            },
        )
        xd_path = build_xd(
            self.tmp_path,
            [node],
            agc_resources={
                "clipPaths": {
                    "cp1": {
                        "type": "clipPath",
                        "clipPath": {
                            "children": [
                                {
                                    "type": "shape",
                                    "id": "cp-rect",
                                    "shape": {
                                        "type": "rect",
                                        "x": 0,
                                        "y": 0,
                                        "width": 8,
                                        "height": 8,
                                    },
                                }
                            ]
                        },
                    }
                }
            },
        )
        result = self.export(xd_path)
        # The node clip applies once, on the wrapper; the inside clip is separate.
        self.assertEqual(result.svg.count('clip-path="url(#mxg-clip-1)"'), 1)
        self.assertEqual(result.svg.count('clip-path="url(#mxg-inside-stroke-1)"'), 1)
        self.assertEqual(result.report["clip_path_count"], 1)

    def test_filter_is_applied_once_to_the_composite(self) -> None:
        style = {
            "fill": solid_fill(1, 2, 3),
            "stroke": inside_stroke(),
            "filters": [
                {
                    "type": "dropShadow",
                    "visible": True,
                    "params": {"dropShadows": [{"dx": 0, "dy": 2, "r": 4, "a": 0.5}]},
                }
            ],
        }
        result = self.render(self.RECT, style)
        self.assertEqual(result.svg.count('filter="url(#mxg-filter-1)"'), 1)
        self.assertEqual(result.report["visible_drop_shadow_count"], 1)

    # -- 10-14: paint properties preserved, not doubled --------------------
    def test_dash_cap_join_miter_and_opacity_are_preserved(self) -> None:
        stroke = inside_stroke(
            1,
            cap="round",
            join="miter",
            miterLimit=8,
            dash=[4, 2],
            dashOffset=3,
            color={"mode": "RGB", "value": {"r": 0, "g": 0, "b": 0}, "alpha": 0.5},
        )
        result = self.render(self.RECT, {"fill": {"type": "none"}, "stroke": stroke})
        line = self.lines(result.svg, "data-xd-stroke-align")[0]

        self.assertIn('stroke-width="2"', line)  # doubled
        self.assertIn('stroke-dasharray="4 2"', line)  # NOT doubled
        self.assertIn('stroke-dashoffset="3"', line)  # NOT doubled
        self.assertIn('stroke-opacity="0.5"', line)  # NOT doubled
        self.assertIn('stroke-linecap="round"', line)
        self.assertIn('stroke-linejoin="miter"', line)
        self.assertIn('stroke-miterlimit="8"', line)

    # -- 15/16: report accounting ------------------------------------------
    def test_handled_inside_alignment_is_counted_not_unsupported(self) -> None:
        result = self.render(
            self.RECT, {"fill": {"type": "none"}, "stroke": inside_stroke()}
        )
        report = result.report
        self.assertEqual(report["handled_node_counts"]["stroke-align:inside"], 1)
        self.assertNotIn("stroke-align:inside", report["unsupported_node_counts"])
        self.assertEqual(report["handled_node_counts"]["stroke:solid"], 1)
        self.assertFalse(
            [w for w in report["warnings"] if "no SVG equivalent" in w],
            report["warnings"],
        )

    # -- 17/18: fail-closed fallbacks --------------------------------------
    def test_open_path_inside_stroke_remains_unsupported(self) -> None:
        result = self.render(
            self.OPEN_PATH, {"fill": {"type": "none"}, "stroke": inside_stroke()}
        )
        report = result.report
        self.assertIn("stroke-align:inside", report["unsupported_node_counts"])
        self.assertNotIn("stroke-align:inside", report["handled_node_counts"])
        self.assertNotIn("inside-stroke", result.svg)
        self.assertIn('stroke-width="1"', result.svg)  # centred, not doubled
        self.assertTrue(
            any("not provably closed" in w for w in report["warnings"]),
            report["warnings"],
        )

    def test_line_geometry_inside_stroke_remains_unsupported(self) -> None:
        result = self.render(
            self.LINE, {"fill": {"type": "none"}, "stroke": inside_stroke()}
        )
        self.assertIn("stroke-align:inside", result.report["unsupported_node_counts"])
        self.assertNotIn("inside-stroke", result.svg)

    # -- 19/20: non-inside rendering is untouched ---------------------------
    def test_centred_stroke_does_not_use_the_emulation(self) -> None:
        centred = self.render(
            self.RECT,
            {"fill": solid_fill(1, 2, 3), "stroke": inside_stroke(2, align="center")},
        )
        self.assertNotIn("inside-stroke", centred.svg)
        self.assertIn('stroke-width="2"', centred.svg)
        # A centred stroke emits the shape's geometry exactly once.
        self.assertEqual(
            len(self.lines(centred.svg, '<rect x="0" y="0" width="100" height="100"')),
            1,
        )

        stroke = inside_stroke(2)
        stroke.pop("align")
        unaligned = self.render(
            self.RECT, {"fill": solid_fill(1, 2, 3), "stroke": stroke}
        )
        # An absent align renders exactly like an explicit centre alignment.
        self.assertEqual(centred.svg, unaligned.svg)

    def test_stroke_type_none_is_unaffected(self) -> None:
        result = self.render(
            self.RECT,
            {"fill": solid_fill(1, 2, 3), "stroke": {"type": "none", "align": "inside"}},
        )
        self.assertNotIn("inside-stroke", result.svg)
        self.assertNotIn("stroke=", result.svg)

    def test_outside_alignment_still_unsupported(self) -> None:
        result = self.render(
            self.RECT,
            {"fill": {"type": "none"}, "stroke": inside_stroke(1, align="outside")},
        )
        self.assertIn("stroke-align:outside", result.report["unsupported_node_counts"])
        self.assertNotIn("inside-stroke", result.svg)

    # -- 21/22: deterministic, collision-free IDs ---------------------------
    def test_clip_ids_are_deterministic_across_exports(self) -> None:
        style = {"fill": solid_fill(1, 2, 3), "stroke": inside_stroke()}
        xd_path = build_xd(self.tmp_path, [shape_node(self.RECT, style)])
        first = self.export(xd_path).svg
        second = self.export(xd_path).svg
        self.assertEqual(first, second)
        self.assertIn("mxg-inside-stroke-1", first)

    def test_two_inside_strokes_get_collision_free_ids(self) -> None:
        style = {"fill": {"type": "none"}, "stroke": inside_stroke()}
        result = self.render(
            self.RECT,
            style,
            nodes=[
                shape_node(self.RECT, style, node_id="a"),
                shape_node(self.CIRCLE, style, node_id="b"),
            ],
        )
        self.assertIn('<clipPath id="mxg-inside-stroke-1"', result.svg)
        self.assertIn('<clipPath id="mxg-inside-stroke-2"', result.svg)
        self.assertEqual(result.svg.count('clip-path="url(#mxg-inside-stroke-1)"'), 1)
        self.assertEqual(result.svg.count('clip-path="url(#mxg-inside-stroke-2)"'), 1)
        self.assertEqual(result.report["handled_node_counts"]["stroke-align:inside"], 2)

    # -- 23: shared syncRef sources use the same mechanism -------------------
    def test_sync_ref_source_shape_uses_the_same_emulation(self) -> None:
        source = {
            "type": "shape",
            "id": "border-def",
            "name": "Border",
            "guid": SOURCE_GUID,
            "shape": {"type": "rect", "x": 0, "y": 0, "width": 40, "height": 2},
            "style": {"fill": {"type": "none"}, "stroke": inside_stroke(0.5)},
        }
        xd_path = build_xd(
            self.tmp_path,
            [sync_ref_instance()],
            shared_agc=shared_agc_with(source),
        )
        result = self.export(xd_path)

        self.assertEqual(result.report["resolved_sync_refs"], 1)
        self.assertEqual(result.report["unresolved_sync_refs"], 0)
        self.assertIn('<clipPath id="mxg-inside-stroke-1"', result.svg)
        self.assertEqual(result.report["handled_node_counts"]["stroke-align:inside"], 1)
        stroke_line = self.lines(result.svg, "data-xd-stroke-align")[0]
        self.assertIn('stroke-width="1"', stroke_line)  # 0.5 doubled
        # The instance placement still applies exactly once.
        self.assertEqual(result.svg.count("matrix(1 0 0 1 23 3.666667)"), 1)

    # -- 25/26: metadata -----------------------------------------------------
    def test_iteration_and_schemas(self) -> None:
        self.assertEqual(xdref.EXPORTER_ITERATION, "MERZOX-UI-GOLDEN-I3-R2-D7-I1")
        self.assertEqual(xdref.BATCH_REPORT_SCHEMA, "merzox.xd_reference_batch/1")
        self.assertEqual(xdref.REPORT_SCHEMA, "merzox.xd_reference_exporter/1")
        report = self.render(
            self.RECT, {"fill": {"type": "none"}, "stroke": inside_stroke()}
        ).report
        self.assertEqual(report["iteration"], "MERZOX-UI-GOLDEN-I3-R2-D7-I1")

    def test_geometry_eligibility_helper(self) -> None:
        closed = xdref.AgcRenderer._is_closed_geometry
        make = xdref.ShapeGeometry
        self.assertTrue(closed(make("rect", OrderedDict())))
        self.assertTrue(closed(make("circle", OrderedDict())))
        self.assertTrue(closed(make("ellipse", OrderedDict())))
        self.assertTrue(closed(make("path", OrderedDict([("d", "M0 0 L1 1 Z")]))))
        self.assertTrue(closed(make("path", OrderedDict([("d", "M0 0 L1 1 z ")]))))
        self.assertFalse(closed(make("path", OrderedDict([("d", "M0 0 L1 1")]))))
        self.assertFalse(closed(make("path", OrderedDict([("d", "")]))))
        self.assertFalse(closed(make("line", OrderedDict())))


# ---------------------------------------------------------------------------
# I3-R2-I4: deterministic non-uniform rounded rectangles.
# ---------------------------------------------------------------------------


def rounded_rect_shape(
    radius: Any,
    x: float = 0,
    y: float = 0,
    width: float = 100,
    height: float = 100,
) -> Dict[str, Any]:
    """A compact AGC rect whose ``r`` is the proven (tl, tr, br, bl) list."""
    return {
        "type": "rect",
        "x": x,
        "y": y,
        "width": width,
        "height": height,
        "r": radius,
    }


class TestCornerRadiusScaling(ExporterTestCase):
    """The pure proportional-overlap policy, independent of any rendering."""

    # -- 5: nothing overlaps, nothing moves ---------------------------------
    def test_non_overlapping_radii_are_returned_unchanged(self) -> None:
        radii, factor = xdref.scale_corner_radii(100, 100, [1, 2, 3, 4])
        self.assertEqual(radii, (1.0, 2.0, 3.0, 4.0))
        self.assertEqual(factor, 1.0)

    def test_radii_exactly_filling_a_side_are_not_scaled(self) -> None:
        # top = 10 + 10 = 20 == width: touching is not overlapping.
        radii, factor = xdref.scale_corner_radii(20, 40, [10, 10, 0, 0])
        self.assertEqual(radii, (10.0, 10.0, 0.0, 0.0))
        self.assertEqual(factor, 1.0)

    def test_zero_radii_never_scale(self) -> None:
        radii, factor = xdref.scale_corner_radii(0, 0, [0, 0, 0, 0])
        self.assertEqual(radii, (0.0, 0.0, 0.0, 0.0))
        self.assertEqual(factor, 1.0)

    # -- 6: the exact target corpus cap -------------------------------------
    def test_target_corpus_class_a_scales_to_nine_and_a_half(self) -> None:
        radii, factor = xdref.scale_corner_radii(19, 19, [0, 10, 10, 0])
        self.assertEqual(factor, 0.95)
        self.assertEqual(radii, (0.0, 9.5, 9.5, 0.0))

    # -- 7: the mirrored target corpus cap ----------------------------------
    def test_target_corpus_class_b_scales_to_nine_and_a_half(self) -> None:
        radii, factor = xdref.scale_corner_radii(19, 19, [10, 0, 0, 10])
        self.assertEqual(factor, 0.95)
        self.assertEqual(radii, (9.5, 0.0, 0.0, 9.5))

    # -- 8: several sides could constrain; one common minimum factor wins ----
    def test_one_common_minimum_factor_scales_all_four_corners(self) -> None:
        # bottom wants 10/12 = 0.8333..., left wants 8/16 = 0.5: the left side
        # is the most violated, so 0.5 is applied to every corner - including
        # the top-right corner, which on its own never overflowed anything.
        radii, factor = xdref.scale_corner_radii(10, 8, [6, 2, 2, 10])
        self.assertEqual(factor, 0.5)
        self.assertEqual(radii, (3.0, 1.0, 1.0, 5.0))
        # Independent per-corner clamping would have left tr/br at 2.
        self.assertNotEqual(radii[1], 2.0)

    def test_negative_and_short_radius_lists_are_normalised(self) -> None:
        radii, factor = xdref.scale_corner_radii(100, 100, [-4, 5])
        self.assertEqual(radii, (0.0, 5.0, 0.0, 0.0))
        self.assertEqual(factor, 1.0)


class TestNonUniformRoundedRectPath(ExporterTestCase):
    """Path construction in the proven TL, TR, BR, BL order."""

    # -- 1: the proven corner order -----------------------------------------
    def test_proven_corner_order_maps_to_physical_corners(self) -> None:
        # r = [1, 2, 3, 4] on a 100x100 box at the origin: TL=1 (near 0,0),
        # TR=2 (near 100,0), BR=3 (near 100,100), BL=4 (near 0,100).
        self.assertEqual(
            xdref.rounded_rect_path_data(0, 0, 100, 100, (1, 2, 3, 4)),
            "M 1,0 L 98,0 A 2,2 0 0 1 100,2 L 100,97 A 3,3 0 0 1 97,100 "
            "L 4,100 A 4,4 0 0 1 0,96 L 0,1 A 1,1 0 0 1 1,0 Z",
        )

    # -- 2: four asymmetric one-hot cases -----------------------------------
    def test_one_hot_top_left(self) -> None:
        self.assertEqual(
            xdref.rounded_rect_path_data(0, 0, 100, 100, (8, 0, 0, 0)),
            "M 8,0 L 100,0 L 100,100 L 0,100 L 0,8 A 8,8 0 0 1 8,0 Z",
        )

    def test_one_hot_top_right(self) -> None:
        self.assertEqual(
            xdref.rounded_rect_path_data(0, 0, 100, 100, (0, 8, 0, 0)),
            "M 0,0 L 92,0 A 8,8 0 0 1 100,8 L 100,100 L 0,100 L 0,0 Z",
        )

    def test_one_hot_bottom_right(self) -> None:
        self.assertEqual(
            xdref.rounded_rect_path_data(0, 0, 100, 100, (0, 0, 8, 0)),
            "M 0,0 L 100,0 L 100,92 A 8,8 0 0 1 92,100 L 0,100 L 0,0 Z",
        )

    def test_one_hot_bottom_left(self) -> None:
        self.assertEqual(
            xdref.rounded_rect_path_data(0, 0, 100, 100, (0, 0, 0, 8)),
            "M 0,0 L 100,0 L 100,100 L 8,100 A 8,8 0 0 1 0,92 L 0,0 Z",
        )

    # -- 3: mixed zero / non-zero corners -----------------------------------
    def test_mixed_zero_and_non_zero_corners(self) -> None:
        self.assertEqual(
            xdref.rounded_rect_path_data(0, 0, 40, 30, (0, 10, 10, 0)),
            "M 0,0 L 30,0 A 10,10 0 0 1 40,10 L 40,20 A 10,10 0 0 1 30,30 "
            "L 0,30 L 0,0 Z",
        )

    # -- 4: fractional radii survive ----------------------------------------
    def test_fractional_radii_are_preserved(self) -> None:
        self.assertEqual(
            xdref.rounded_rect_path_data(0, 0, 100, 100, (2.5, 0, 1.25, 0)),
            "M 2.5,0 L 100,0 L 100,98.75 A 1.25,1.25 0 0 1 98.75,100 "
            "L 0,100 L 0,2.5 A 2.5,2.5 0 0 1 2.5,0 Z",
        )

    def test_path_offsets_follow_the_declared_origin(self) -> None:
        self.assertEqual(
            xdref.rounded_rect_path_data(5, 6, 20, 20, (0, 4, 0, 0)),
            "M 5,6 L 21,6 A 4,4 0 0 1 25,10 L 25,26 L 5,26 L 5,6 Z",
        )

    def test_path_is_closed_and_usable_as_an_interior_clip(self) -> None:
        geometry = xdref.ShapeGeometry(
            "path",
            OrderedDict(
                [("d", xdref.rounded_rect_path_data(0, 0, 10, 10, (2, 0, 3, 0)))]
            ),
        )
        self.assertTrue(xdref.AgcRenderer._is_closed_geometry(geometry))


class TestNonUniformRectRendering(ExporterTestCase):
    def render(self, children: List[Dict[str, Any]]) -> xdref.ExportResult:
        return self.export(build_xd(self.tmp_path, children))

    def lines(self, svg: str, needle: str) -> List[str]:
        return [line for line in svg.splitlines() if needle in line]

    # -- 11/12: reporting ----------------------------------------------------
    def test_non_uniform_rect_is_no_longer_unsupported(self) -> None:
        result = self.render(
            [
                shape_node(
                    rounded_rect_shape([0, 10, 10, 0], width=40, height=30),
                    {"fill": solid_fill(0x12, 0x34, 0x56)},
                )
            ]
        )
        self.assertNotIn(
            "rect:non-uniform-corner-radius", result.report["unsupported_node_counts"]
        )

    def test_non_uniform_rect_is_counted_as_handled(self) -> None:
        result = self.render(
            [
                shape_node(
                    rounded_rect_shape([0, 10, 10, 0], width=40, height=30),
                    {"fill": solid_fill(1, 2, 3)},
                    node_id="a",
                ),
                shape_node(
                    rounded_rect_shape([10, 0, 0, 10], width=40, height=30),
                    {"fill": solid_fill(1, 2, 3)},
                    node_id="b",
                ),
            ]
        )
        handled = result.report["handled_node_counts"]
        self.assertEqual(handled["rect:non-uniform-corner-radius"], 2)
        self.assertEqual(handled["shape:rect"], 2)
        self.assertNotIn("rect:corner-radius-overlap-scaled", handled)

    def test_overlap_scaled_rect_is_reported_separately(self) -> None:
        result = self.render(
            [
                shape_node(
                    rounded_rect_shape([0, 10, 10, 0], width=19, height=19),
                    {"fill": solid_fill(1, 2, 3)},
                )
            ]
        )
        handled = result.report["handled_node_counts"]
        self.assertEqual(handled["rect:non-uniform-corner-radius"], 1)
        self.assertEqual(handled["rect:corner-radius-overlap-scaled"], 1)
        self.assertIn(
            "M 0,0 L 9.5,0 A 9.5,9.5 0 0 1 19,9.5 L 19,9.5 "
            "A 9.5,9.5 0 0 1 9.5,19 L 0,19 L 0,0 Z",
            result.svg,
        )
        self.assertTrue(
            any(
                "not a claim of parity" in text
                for text in result.report["limitations"]
            )
        )

    def test_rect_element_is_replaced_by_an_exact_path(self) -> None:
        result = self.render(
            [
                shape_node(
                    rounded_rect_shape([0, 10, 10, 0], x=5, y=6, width=40, height=30),
                    {"fill": solid_fill(0x12, 0x34, 0x56)},
                )
            ]
        )
        self.assertIn(
            '<path d="M 5,6 L 35,6 A 10,10 0 0 1 45,16 L 45,26 '
            'A 10,10 0 0 1 35,36 L 5,36 L 5,6 Z" fill="#123456"/>',
            result.svg,
        )
        # The old uniform-rx approximation must be gone.
        self.assertNotIn('rx="0"', result.svg)
        self.assertNotIn('rx="10"', result.svg)

    # -- 9: a uniform four-value list keeps the plain rect -------------------
    def test_uniform_four_value_radius_still_renders_a_rect(self) -> None:
        result = self.render(
            [
                shape_node(
                    rounded_rect_shape([6, 6, 6, 6], width=40, height=30),
                    {"fill": solid_fill(1, 2, 3)},
                )
            ]
        )
        self.assertIn(
            '<rect x="0" y="0" width="40" height="30" rx="6" ry="6"', result.svg
        )
        self.assertNotIn(
            "rect:non-uniform-corner-radius", result.report["handled_node_counts"]
        )
        self.assertNotIn(
            "rect:non-uniform-corner-radius", result.report["unsupported_node_counts"]
        )

    # -- 10: a rect with no radius is untouched ------------------------------
    def test_rect_without_radius_is_unchanged(self) -> None:
        result = self.render([rect_node(x=5, y=6, width=30, height=40)])
        self.assertIn('<rect x="5" y="6" width="30" height="40"', result.svg)
        self.assertNotIn("rx=", result.svg)

    def test_all_zero_radius_list_is_unchanged(self) -> None:
        result = self.render(
            [
                shape_node(
                    rounded_rect_shape([0, 0, 0, 0], width=40, height=30),
                    {"fill": solid_fill(1, 2, 3)},
                )
            ]
        )
        self.assertIn('<rect x="0" y="0" width="40" height="30"', result.svg)
        self.assertNotIn("rx=", result.svg)

    def test_non_four_value_list_keeps_the_documented_approximation(self) -> None:
        result = self.render(
            [
                shape_node(
                    rounded_rect_shape([4, 8], width=40, height=30),
                    {"fill": solid_fill(1, 2, 3)},
                )
            ]
        )
        self.assertEqual(
            result.report["unsupported_node_counts"]["rect:non-uniform-corner-radius"],
            1,
        )
        self.assertIn('rx="4" ry="4"', result.svg)

    # -- 13: inside-stroke composition reuses the same path ------------------
    def test_inside_stroke_reuses_the_path_geometry(self) -> None:
        result = self.render(
            [
                shape_node(
                    rounded_rect_shape([0, 10, 10, 0], width=40, height=30),
                    {"fill": solid_fill(0x12, 0x34, 0x56), "stroke": inside_stroke(1.5)},
                )
            ]
        )
        path_data = (
            "M 0,0 L 30,0 A 10,10 0 0 1 40,10 L 40,20 A 10,10 0 0 1 30,30 "
            "L 0,30 L 0,0 Z"
        )
        # Interior clip, filled copy and stroked copy: all the same geometry.
        self.assertIn(
            f'<clipPath id="mxg-inside-stroke-1" clipPathUnits="userSpaceOnUse">'
            f'<path d="{path_data}"/></clipPath>',
            result.svg,
        )
        self.assertEqual(result.svg.count(f'd="{path_data}"'), 3)

        stroke_lines = self.lines(result.svg, "data-xd-stroke-align")
        self.assertEqual(len(stroke_lines), 1)
        self.assertIn(f'<path d="{path_data}"', stroke_lines[0])
        self.assertIn('stroke-width="3"', stroke_lines[0])  # 1.5 doubled
        self.assertIn('fill="none"', stroke_lines[0])
        self.assertIn('clip-path="url(#mxg-inside-stroke-1)"', stroke_lines[0])
        self.assertEqual(
            result.report["handled_node_counts"]["stroke-align:inside"], 1
        )
        # The fill is still painted exactly once.
        self.assertEqual(result.svg.count('fill="#123456"'), 1)

    def test_scaled_inside_stroke_rect_uses_the_scaled_path_everywhere(self) -> None:
        result = self.render(
            [
                shape_node(
                    rounded_rect_shape([10, 0, 0, 10], width=19, height=19),
                    {"fill": {"type": "none"}, "stroke": inside_stroke(0.5)},
                )
            ]
        )
        path_data = (
            "M 9.5,0 L 19,0 L 19,19 L 9.5,19 A 9.5,9.5 0 0 1 0,9.5 "
            "L 0,9.5 A 9.5,9.5 0 0 1 9.5,0 Z"
        )
        self.assertEqual(result.svg.count(f'd="{path_data}"'), 3)
        stroke_line = self.lines(result.svg, "data-xd-stroke-align")[0]
        self.assertIn('stroke-width="1"', stroke_line)  # 0.5 doubled

    # -- 14: node semantics still apply exactly once -------------------------
    def test_transform_still_wraps_the_path_geometry(self) -> None:
        result = self.render(
            [
                shape_node(
                    rounded_rect_shape([0, 10, 10, 0], width=40, height=30),
                    {"fill": solid_fill(1, 2, 3), "opacity": 0.5},
                    transform={"a": 1, "b": 0, "c": 0, "d": 1, "tx": 12, "ty": 34},
                )
            ]
        )
        self.assertEqual(result.svg.count("matrix(1 0 0 1 12 34)"), 1)
        self.assertEqual(result.svg.count('opacity="0.5"'), 1)
        # Coordinates stay in the node's own space; only the wrapper moves.
        self.assertIn('<path d="M 0,0 L 30,0 A 10,10 0 0 1 40,10', result.svg)

    def test_output_is_deterministic_across_exports(self) -> None:
        children = [
            shape_node(
                rounded_rect_shape([0, 10, 10, 0], width=19, height=19),
                {"fill": solid_fill(1, 2, 3), "stroke": inside_stroke()},
            )
        ]
        xd_path = build_xd(self.tmp_path, children)
        self.assertEqual(self.export(xd_path).svg, self.export(xd_path).svg)


# ---------------------------------------------------------------------------
# I3-R2-D7-I1: strict local path bounds for image fills.
# ---------------------------------------------------------------------------


#: The exact path shared by all six repaired pattern fills in the real
#: design.xd - a closed 33x33 circle built from four cubic segments.
TARGET_CIRCLE_PATH = (
    "M 16.5 0\n"
    "C 25.61269760131836 0 33 7.387302398681641 33 16.5\n"
    "C 33 25.61269760131836 25.61269760131836 33 16.5 33\n"
    "C 7.387302398681641 33 0 25.61269760131836 0 16.5\n"
    "C 0 7.387302398681641 7.387302398681641 0 16.5 0\n"
    "Z"
)


class TestStrictAbsoluteMlcZBounds(unittest.TestCase):
    """The fail-closed reader itself: what it accepts and what it refuses."""

    def bounds(self, path_data: Any) -> Any:
        return xdref.strict_absolute_mlc_z_bounds(path_data)

    def assertBounds(self, path_data: Any, expected: Any) -> None:
        derived = self.bounds(path_data)
        self.assertIsNotNone(derived, path_data)
        assert derived is not None  # narrows the type for readers
        for actual, wanted in zip(derived, expected):
            self.assertAlmostEqual(actual, wanted, places=9)

    # -- 1: the proven corpus target ------------------------------------
    def test_target_cubic_circle_path(self) -> None:
        self.assertBounds(TARGET_CIRCLE_PATH, (0.0, 0.0, 33.0, 33.0))

    def test_target_path_survives_single_line_spelling(self) -> None:
        self.assertBounds(
            " ".join(TARGET_CIRCLE_PATH.split()), (0.0, 0.0, 33.0, 33.0)
        )

    # -- 2: explicit closed M/L rectangle --------------------------------
    def test_simple_closed_rectangle(self) -> None:
        self.assertBounds("M 2 3 L 12 3 L 12 13 L 2 13 Z", (2.0, 3.0, 10.0, 10.0))

    # -- 3: a true extremum strictly inside a cubic segment --------------
    def test_interior_cubic_extremum_is_solved_not_approximated(self) -> None:
        # y peaks at t=0.5 with B(0.5)=7.5; the control-point box would say 10,
        # and the endpoints alone would say 0.
        self.assertBounds("M 0 0 C 0 10 10 10 10 0 Z", (0.0, 0.0, 10.0, 7.5))

    def test_negative_interior_cubic_extremum(self) -> None:
        self.assertBounds("M 0 0 C 0 -10 10 -10 10 0 Z", (0.0, -7.5, 10.0, 7.5))

    # -- 4: several explicit commands and subpaths -----------------------
    def test_multiple_commands_and_closed_subpaths(self) -> None:
        self.assertBounds(
            "M 0 0 L 10 0 L 10 10 Z M 20 20 L 30 20 L 30 30 Z",
            (0.0, 0.0, 30.0, 30.0),
        )

    def test_mixed_line_and_cubic_commands(self) -> None:
        self.assertBounds(
            "M 0 0 L 10 0 C 10 10 20 10 20 0 L 20 -5 Z",
            (0.0, -5.0, 20.0, 12.5),
        )

    # -- 5: separators ---------------------------------------------------
    def test_comma_and_whitespace_separators_are_equivalent(self) -> None:
        for spelling in (
            "M 2 3 L 12 3 L 12 13 L 2 13 Z",
            "M2,3L12,3L12,13L2,13Z",
            "M 2,3  L 12 ,3\tL\n12,13 L 2 13 Z ",
            "  M 2 3 L 12 3 L 12 13 L 2 13 Z  ",
        ):
            with self.subTest(spelling=spelling):
                self.assertBounds(spelling, (2.0, 3.0, 10.0, 10.0))

    # -- 6: negative and fractional coordinates --------------------------
    def test_negative_and_fractional_coordinates(self) -> None:
        self.assertBounds(
            "M -2.5 -1.5 L 3.5 -1.5 L 3.5 4.5 L -2.5 4.5 Z",
            (-2.5, -1.5, 6.0, 6.0),
        )

    def test_explicit_plus_sign_and_exponent_forms(self) -> None:
        self.assertBounds("M +0 +0 L 1e1 0 L 1e1 5e0 L 0 5 Z", (0.0, 0.0, 10.0, 5.0))

    # -- 7: lowercase / relative commands are refused --------------------
    def test_lowercase_relative_commands_are_rejected(self) -> None:
        for path_data in (
            "m 0 0 L 10 10 Z",
            "M 0 0 l 10 10 Z",
            "M 0 0 L 10 0 c 0 5 5 5 5 0 Z",
            "m 0 0 l 10 0 l 0 10 z",
            "M 0 0 L 10 0 L 10 10 z",
        ):
            with self.subTest(path_data=path_data):
                self.assertIsNone(self.bounds(path_data))

    # -- 8: H / V are refused --------------------------------------------
    def test_horizontal_and_vertical_commands_are_rejected(self) -> None:
        for path_data in (
            "M 0 0 H 10 V 10 Z",
            "M 0 0 H 10 Z",
            "M 0 0 V 10 Z",
            "M 0 0 L 10 0 h 5 Z",
        ):
            with self.subTest(path_data=path_data):
                self.assertIsNone(self.bounds(path_data))

    # -- 9: Q / S / T / A are refused ------------------------------------
    def test_quadratic_smooth_and_arc_commands_are_rejected(self) -> None:
        for path_data in (
            "M 0 0 Q 5 5 10 0 Z",
            "M 0 0 C 0 5 5 5 5 0 S 10 -5 10 0 Z",
            "M 0 0 Q 5 5 10 0 T 20 0 Z",
            "M 0 0 A 5 5 0 0 1 10 10 Z",
            "M 5,6 L 35,6 A 10,10 0 0 1 45,16 L 45,26 Z",
        ):
            with self.subTest(path_data=path_data):
                self.assertIsNone(self.bounds(path_data))

    # -- 10: implicit command repetition is refused ----------------------
    def test_implicit_command_repetition_is_rejected(self) -> None:
        for path_data in (
            "M 0 0 10 10",
            "M 0 0 10 10 Z",
            "M 0 0 L 10 0 10 10 Z",
            "M 0 0 C 0 5 5 5 5 0 5 -5 10 -5 10 0 Z",
        ):
            with self.subTest(path_data=path_data):
                self.assertIsNone(self.bounds(path_data))

    # -- 11: wrong argument counts are refused ---------------------------
    def test_malformed_argument_counts_are_rejected(self) -> None:
        for path_data in (
            "M 0",
            "M 0 0 L 10 Z",
            "M 0 0 C 0 5 5 5 5 Z",
            "M 0 0 C 0 5 5 5 Z",
            "M 0 0 L 10 0 L 10 10 Z 5",
            "Z",
            "M",
        ):
            with self.subTest(path_data=path_data):
                self.assertIsNone(self.bounds(path_data))

    def test_z_takes_no_arguments(self) -> None:
        self.assertIsNone(self.bounds("M 0 0 L 10 0 L 10 10 Z 0 0"))

    # -- 12: stray characters a loose regex would ignore -----------------
    def test_stray_characters_are_rejected(self) -> None:
        for path_data in (
            "M 0 0 L 10 0 L 10 10 Z !",
            "M 0 0 L 10 0 X L 10 10 Z",
            "M 0 0 L 10 0 L 10 10 Z </path>",
            "M 0 0 L (10) 0 L 10 10 Z",
            "M 0 0 L 10 0; L 10 10 Z",
            "path M 0 0 L 10 0 L 10 10 Z",
            "M 0 0 L 10 0 L 10 10 Z ",
        ):
            with self.subTest(path_data=path_data):
                self.assertIsNone(self.bounds(path_data))

    # -- 13: non-finite numeric forms ------------------------------------
    def test_non_finite_numbers_are_rejected(self) -> None:
        for path_data in (
            "M 0 0 L 1e400 10 L 10 10 Z",
            "M 0 0 L NaN 10 Z",
            "M 0 0 L Infinity 10 Z",
            "M 0 0 L -inf 10 Z",
            "M 0 0 L nan nan Z",
        ):
            with self.subTest(path_data=path_data):
                self.assertIsNone(self.bounds(path_data))

    # -- 14: open paths ---------------------------------------------------
    def test_open_paths_are_rejected(self) -> None:
        for path_data in (
            "M 0 0 L 10 0 L 10 10",
            "M 0 0 C 0 10 10 10 10 0",
            "M 0 0 L 10 0 L 10 10 Z M 20 20 L 30 20 L 30 30",
            "M 0 0 L 10 0 M 20 20 L 30 20 L 30 30 Z",
        ):
            with self.subTest(path_data=path_data):
                self.assertIsNone(self.bounds(path_data))

    def test_geometry_before_a_moveto_is_rejected(self) -> None:
        for path_data in (
            "L 10 10 Z",
            "C 0 5 5 5 5 0 Z",
            "M 0 0 L 10 0 L 10 10 Z L 20 20 Z",
        ):
            with self.subTest(path_data=path_data):
                self.assertIsNone(self.bounds(path_data))

    # -- 15: degenerate bounds -------------------------------------------
    def test_degenerate_bounds_are_rejected(self) -> None:
        for path_data in (
            "M 0 0 L 10 0 Z",  # zero height
            "M 0 0 L 0 10 Z",  # zero width
            "M 5 5 Z",  # a single point
            "M 0 0 C 0 0 0 0 0 0 Z",
        ):
            with self.subTest(path_data=path_data):
                self.assertIsNone(self.bounds(path_data))

    # -- non-string / empty input ----------------------------------------
    def test_empty_and_non_string_input_is_rejected(self) -> None:
        for path_data in ("", "   ", " , ", None, 42, ["M 0 0 L 10 10 Z"], b"M 0 0 Z"):
            with self.subTest(path_data=path_data):
                self.assertIsNone(self.bounds(path_data))

    # -- control points must not be used as the bounding box -------------
    def test_control_point_box_is_not_used(self) -> None:
        derived = self.bounds("M 0 0 C 0 100 10 100 10 0 Z")
        self.assertIsNotNone(derived)
        assert derived is not None
        self.assertAlmostEqual(derived[3], 75.0, places=9)


class TestDerivedPathBoundsImageFill(ExporterTestCase):
    """Image fills on strictly parseable closed paths now get real bounds."""

    UID = "98578658e496669a0df69fdd35cc42fe"

    def pattern_fill(
        self,
        scale_behavior: Optional[str] = "fill",
        natural: Any = (200, 200),
        offset: Optional[Any] = None,
    ) -> Dict[str, Any]:
        ux: Dict[str, Any] = {"uid": self.UID}
        if scale_behavior is not None:
            ux["scaleBehavior"] = scale_behavior
        if offset is not None:
            ux["offsetX"], ux["offsetY"] = offset
        return {
            "type": "pattern",
            "pattern": {"width": natural[0], "height": natural[1], "meta": {"ux": ux}},
        }

    def build(self, node: Dict[str, Any]) -> xdref.ExportResult:
        xd_path = build_xd(
            self.tmp_path, [node], blobs={f"resources/{self.UID}": TINY_PNG}
        )
        return self.export(xd_path)

    def path_fill_node(
        self,
        path_data: str = TARGET_CIRCLE_PATH,
        scale_behavior: Optional[str] = "fill",
        offset: Optional[Any] = None,
    ) -> Dict[str, Any]:
        return {
            "type": "shape",
            "id": "path-fill",
            "shape": {"type": "path", "path": path_data},
            "style": {"fill": self.pattern_fill(scale_behavior, offset=offset)},
        }

    # -- 16: reliable stored bounds stay preferred and unchanged ---------
    def test_reliable_rect_bounds_still_win(self) -> None:
        node = rect_node(
            x=10, y=20, width=813, height=812, style={"fill": self.pattern_fill()}
        )
        result = self.build(node)
        entry = result.report["pattern_fills"][0]
        self.assertEqual(entry["bounds_source"], "shape-bounds")
        self.assertEqual(
            entry["target_bounds"],
            {"x": 10.0, "y": 20.0, "width": 813.0, "height": 812.0},
        )
        self.assertNotIn(
            xdref.PATTERN_DERIVED_PATH_BOUNDS_KEY,
            result.report["handled_node_counts"],
        )

    def test_non_uniform_rounded_rect_path_keeps_its_stored_bounds(self) -> None:
        """A generated path with reliable bounds must not go through the reader."""
        node = {
            "type": "shape",
            "id": "rounded-1",
            "shape": {
                "type": "rect",
                "x": 0,
                "y": 0,
                "width": 40,
                "height": 30,
                "r": [0, 10, 10, 0],
            },
            "style": {"fill": self.pattern_fill()},
        }
        result = self.build(node)
        entry = result.report["pattern_fills"][0]
        self.assertEqual(entry["bounds_source"], "shape-bounds")
        self.assertEqual(
            entry["target_bounds"],
            {"x": 0.0, "y": 0.0, "width": 40.0, "height": 30.0},
        )
        self.assertNotIn(
            xdref.PATTERN_DERIVED_PATH_BOUNDS_KEY,
            result.report["handled_node_counts"],
        )

    # -- 17/18: supported path with unreliable bounds --------------------
    def test_target_path_uses_derived_bounds_in_cover_mode(self) -> None:
        result = self.build(self.path_fill_node())
        entry = result.report["pattern_fills"][0]

        self.assertEqual(entry["bounds_source"], "derived-path-bounds")
        self.assertEqual(
            entry["target_bounds"],
            {"x": 0.0, "y": 0.0, "width": 33.0, "height": 33.0},
        )
        self.assertEqual(
            entry["preserve_aspect_ratio"], xdref.COVER_PRESERVE_ASPECT_RATIO
        )
        self.assertIn(
            '<pattern id="mxg-pattern-1" patternUnits="userSpaceOnUse" '
            'x="0" y="0" width="33" height="33">',
            result.svg,
        )
        self.assertIn(
            '<image x="0" y="0" width="33" height="33" '
            'preserveAspectRatio="xMidYMid slice"',
            result.svg,
        )
        # The natural bitmap box never becomes the tile.
        self.assertEqual(entry["natural_width"], 200.0)
        self.assertEqual(entry["natural_height"], 200.0)

    def test_simple_closed_rect_path_uses_derived_bounds(self) -> None:
        result = self.build(self.path_fill_node("M 2 3 L 12 3 L 12 13 L 2 13 Z"))
        entry = result.report["pattern_fills"][0]
        self.assertEqual(entry["bounds_source"], "derived-path-bounds")
        self.assertEqual(
            entry["target_bounds"],
            {"x": 2.0, "y": 3.0, "width": 10.0, "height": 10.0},
        )

    # -- 19: offsets move the tile origin only ---------------------------
    def test_offsets_shift_the_tile_origin_only(self) -> None:
        result = self.build(self.path_fill_node(offset=(-5, -10)))
        entry = result.report["pattern_fills"][0]

        self.assertEqual(entry["bounds_source"], "derived-path-bounds")
        self.assertEqual(
            entry["target_bounds"],
            {"x": -5.0, "y": -10.0, "width": 33.0, "height": 33.0},
        )
        self.assertIn(
            'patternUnits="userSpaceOnUse" x="-5" y="-10" width="33" height="33">',
            result.svg,
        )

    def test_positive_offsets_shift_a_non_zero_origin(self) -> None:
        result = self.build(
            self.path_fill_node("M 2 3 L 12 3 L 12 13 L 2 13 Z", offset=(4, 6))
        )
        self.assertEqual(
            result.report["pattern_fills"][0]["target_bounds"],
            {"x": 6.0, "y": 9.0, "width": 10.0, "height": 10.0},
        )

    # -- 20: stretch mode keeps the existing preserve behaviour ----------
    def test_stretch_mode_uses_the_existing_stretch_constant(self) -> None:
        result = self.build(self.path_fill_node(scale_behavior="stretch"))
        entry = result.report["pattern_fills"][0]

        self.assertEqual(entry["bounds_source"], "derived-path-bounds")
        self.assertEqual(entry["mode"], "stretch")
        self.assertEqual(
            entry["preserve_aspect_ratio"], xdref.STRETCH_PRESERVE_ASPECT_RATIO
        )
        self.assertIn('preserveAspectRatio="none"', result.svg)
        self.assertEqual(entry["target_bounds"]["width"], 33.0)

    def test_unspecified_scale_behavior_still_covers(self) -> None:
        result = self.build(self.path_fill_node(scale_behavior=None))
        entry = result.report["pattern_fills"][0]
        self.assertEqual(entry["bounds_source"], "derived-path-bounds")
        self.assertEqual(
            entry["preserve_aspect_ratio"], xdref.COVER_PRESERVE_ASPECT_RATIO
        )

    # -- 21/22: reporting -------------------------------------------------
    def test_derived_bounds_are_counted_exactly_once_as_handled(self) -> None:
        result = self.build(self.path_fill_node())
        handled = result.report["handled_node_counts"]

        self.assertEqual(
            xdref.PATTERN_DERIVED_PATH_BOUNDS_KEY, "fill:pattern:path-bounds-derived"
        )
        self.assertEqual(handled[xdref.PATTERN_DERIVED_PATH_BOUNDS_KEY], 1)
        self.assertEqual(handled["fill:pattern"], 1)

    def test_derived_bounds_do_not_report_no_shape_bounds(self) -> None:
        result = self.build(self.path_fill_node())
        report = result.report

        self.assertNotIn(
            "fill:pattern:no-shape-bounds", report["unsupported_node_counts"]
        )
        self.assertFalse(
            [w for w in report["warnings"] if "no reliable local" in w],
            report["warnings"],
        )
        self.assertEqual(report["resolved_pattern_fill_count"], 1)

    def test_two_target_paths_count_twice(self) -> None:
        first = self.path_fill_node()
        second = dict(self.path_fill_node())
        second["id"] = "path-fill-2"
        xd_path = build_xd(
            self.tmp_path,
            [first, second],
            blobs={f"resources/{self.UID}": TINY_PNG},
        )
        result = self.export(xd_path)
        self.assertEqual(
            result.report["handled_node_counts"][
                xdref.PATTERN_DERIVED_PATH_BOUNDS_KEY
            ],
            2,
        )
        self.assertNotIn(
            "fill:pattern:no-shape-bounds", result.report["unsupported_node_counts"]
        )

    # -- 23: unsupported commands keep the documented fallback -----------
    def test_unsupported_path_commands_keep_the_natural_bitmap_fallback(self) -> None:
        for path_data in (
            "M 0 0 H 10 V 10 Z",
            "m 0 0 L 10 10 Z",
            "M 0 0 Q 5 5 10 0 Z",
            "M 0 0 A 5 5 0 0 1 10 10 Z",
            "M 0 0 10 10 Z",
            "M 0 0 L 10 0 L 10 10",
        ):
            with self.subTest(path_data=path_data):
                result = self.build(self.path_fill_node(path_data))
                report = result.report
                self.assertEqual(
                    report["pattern_fills"][0]["bounds_source"],
                    "natural-bitmap-fallback",
                )
                self.assertEqual(
                    report["unsupported_node_counts"]["fill:pattern:no-shape-bounds"],
                    1,
                )
                self.assertNotIn(
                    xdref.PATTERN_DERIVED_PATH_BOUNDS_KEY,
                    report["handled_node_counts"],
                )

    def test_degenerate_path_keeps_the_natural_bitmap_fallback(self) -> None:
        result = self.build(self.path_fill_node("M 0 0 L 10 0 Z"))
        report = result.report
        self.assertEqual(
            report["pattern_fills"][0]["bounds_source"], "natural-bitmap-fallback"
        )
        self.assertIn(
            "fill:pattern:no-shape-bounds", report["unsupported_node_counts"]
        )

    # -- schema and identity are untouched --------------------------------
    def test_schema_is_unchanged_and_iteration_is_stamped(self) -> None:
        result = self.build(self.path_fill_node())
        self.assertEqual(result.report["schema"], "merzox.xd_reference_exporter/1")
        self.assertEqual(xdref.REPORT_SCHEMA, "merzox.xd_reference_exporter/1")
        self.assertEqual(
            result.report["iteration"], "MERZOX-UI-GOLDEN-I3-R2-D7-I1"
        )
        json.dumps(result.report, ensure_ascii=False)


if __name__ == "__main__":  # pragma: no cover
    unittest.main()

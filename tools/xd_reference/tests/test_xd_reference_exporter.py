#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""Unit tests for the Merzox XD reference exporter (MERZOX-UI-GOLDEN-I2-R2).

These tests never touch the real ``design.xd``. Every fixture is a minimal
``.xd`` ZIP package generated into a temporary directory, so the suite is
hermetic and does not require Adobe XD, a browser, or Pillow.
"""

from __future__ import annotations

import base64
import json
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
                            "align": "inside",
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
        # Inside/outside alignment has no SVG equivalent: reported, not faked.
        self.assertIn(
            "stroke-align:inside", result.report["unsupported_node_counts"]
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
        node = {
            "type": "shape",
            "id": "path-fill",
            "shape": {"type": "path", "path": "M0 0 L10 10 Z"},
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

    def test_normalized_report_counts_replacements(self) -> None:
        xd_path = build_xd(self.tmp_path, [text_node("Bictov and Bictov")])
        result = self.export(xd_path, normalize_brand=True)
        self.assertEqual(result.report["brand_replacement_count"], 2)

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


class TestUnsupportedFeatureReporting(ExporterTestCase):
    def test_background_blur_is_reported_not_approximated(self) -> None:
        style = {
            "fill": solid_fill(0, 0, 0),
            "filters": [
                {
                    "type": "uxdesign#blur",
                    "visible": True,
                    "params": {"blurAmount": 20, "backgroundEffect": True},
                }
            ],
        }
        xd_path = build_xd(self.tmp_path, [rect_node(style=style)])
        result = self.export(xd_path)
        report = result.report

        self.assertEqual(report["unsupported_background_blur_count"], 1)
        self.assertEqual(report["visible_blur_count"], 0)
        self.assertNotIn("feGaussianBlur", result.svg)
        self.assertIn(
            "filter:uxdesign#blur:background", report["unsupported_node_counts"]
        )
        self.assertTrue(
            any("backgroundEffect" in warning for warning in report["warnings"]),
            report["warnings"],
        )

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

        self.assertEqual(report["iteration"], "MERZOX-UI-GOLDEN-I2-R2")
        self.assertEqual(report["iteration"], xdref.EXPORTER_ITERATION)
        self.assertNotEqual(report["iteration"], "MERZOX-UI-GOLDEN-I1")

        # The schema version is independent of the calibration iteration and
        # must NOT be bumped just because the iteration moved.
        self.assertEqual(report["schema"], "merzox.xd_reference_exporter/1")
        self.assertEqual(report["schema"], xdref.REPORT_SCHEMA)

        # Still serializable, and the stamp survives a JSON round-trip.
        decoded = json.loads(json.dumps(report, ensure_ascii=False))
        self.assertEqual(decoded["iteration"], "MERZOX-UI-GOLDEN-I2-R2")
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
        self.assertEqual(loaded["iteration"], "MERZOX-UI-GOLDEN-I2-R2")
        # The generated SVG must not advertise a stale iteration either.
        svg = svg_out.read_text(encoding="utf-8")
        self.assertIn("MERZOX-UI-GOLDEN-I2-R2", svg)
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


if __name__ == "__main__":  # pragma: no cover
    unittest.main()

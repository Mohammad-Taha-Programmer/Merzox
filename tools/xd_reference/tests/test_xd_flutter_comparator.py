#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""Unit tests for the XD ↔ Flutter golden comparator (MERZOX-UI-GOLDEN-I5-I1).

The suite is hermetic: it never requires the real ``design.xd``, a browser, a
Flutter toolchain or any third-party package. Every image is a synthetic PNG
built here with ``struct``/``zlib``, and every mapping is a synthetic dict.
"""

from __future__ import annotations

import contextlib
import copy
import io
import json
import struct
import sys
import tempfile
import unittest
import zlib
from pathlib import Path
from typing import Any, Dict, List, Sequence, Tuple

MODULE_DIR = Path(__file__).resolve().parents[1]
if str(MODULE_DIR) not in sys.path:
    sys.path.insert(0, str(MODULE_DIR))

import xd_flutter_comparator as cmp  # noqa: E402  (path set up above)


Pixel = Tuple[int, int, int, int]

PNG_SIGNATURE = b"\x89PNG\r\n\x1a\n"
CHANNELS_FOR_COLOR_TYPE = {0: 1, 2: 3, 4: 2, 6: 4}


# ---------------------------------------------------------------------------
# Synthetic PNG encoder (test-only; the comparator itself never encodes PNGs).
# ---------------------------------------------------------------------------


def _chunk(chunk_type: bytes, payload: bytes) -> bytes:
    crc = zlib.crc32(chunk_type + payload) & 0xFFFFFFFF
    return struct.pack(">I", len(payload)) + chunk_type + payload + struct.pack(
        ">I", crc
    )


def _paeth(a: int, b: int, c: int) -> int:
    p = a + b - c
    pa, pb, pc = abs(p - a), abs(p - b), abs(p - c)
    if pa <= pb and pa <= pc:
        return a
    if pb <= pc:
        return b
    return c


def _apply_filter(filter_type: int, raw: bytes, prev: bytes, bpp: int) -> bytes:
    out = bytearray(len(raw))
    for i, x in enumerate(raw):
        left = raw[i - bpp] if i >= bpp else 0
        up = prev[i]
        up_left = prev[i - bpp] if i >= bpp else 0
        if filter_type == 0:
            out[i] = x
        elif filter_type == 1:
            out[i] = (x - left) & 0xFF
        elif filter_type == 2:
            out[i] = (x - up) & 0xFF
        elif filter_type == 3:
            out[i] = (x - ((left + up) >> 1)) & 0xFF
        elif filter_type == 4:
            out[i] = (x - _paeth(left, up, up_left)) & 0xFF
        else:  # pragma: no cover - test helper misuse
            raise AssertionError(f"bad filter {filter_type}")
    return bytes(out)


def encode_png(
    width: int,
    height: int,
    pixels: Sequence[Pixel],
    *,
    color_type: int = 6,
    filter_type: int = 0,
    header_bit_depth: int = 8,
    header_color_type: int = None,
    header_interlace: int = 0,
) -> bytes:
    """Build a minimal PNG. Header fields may be overridden to test rejection."""
    channels = CHANNELS_FOR_COLOR_TYPE[color_type]
    rows: List[bytes] = []
    for y in range(height):
        raw = bytearray()
        for x in range(width):
            r, g, b, a = pixels[y * width + x]
            if color_type == 0:
                raw.append(r)
            elif color_type == 2:
                raw.extend((r, g, b))
            elif color_type == 4:
                raw.extend((r, a))
            else:
                raw.extend((r, g, b, a))
        rows.append(bytes(raw))

    stride = width * channels
    previous = bytes(stride)
    body = bytearray()
    for raw in rows:
        body.append(filter_type)
        body.extend(_apply_filter(filter_type, raw, previous, channels))
        previous = raw

    ihdr = struct.pack(
        ">IIBBBBB",
        width,
        height,
        header_bit_depth,
        color_type if header_color_type is None else header_color_type,
        0,
        0,
        header_interlace,
    )
    return (
        PNG_SIGNATURE
        + _chunk(b"IHDR", ihdr)
        + _chunk(b"IDAT", zlib.compress(bytes(body)))
        + _chunk(b"IEND", b"")
    )


def gradient_pixels(width: int, height: int, *, seed: int = 0) -> List[Pixel]:
    """Deterministic, non-uniform pixel data (no RNG, no timestamps)."""
    out: List[Pixel] = []
    for y in range(height):
        for x in range(width):
            out.append(
                (
                    (x * 7 + y * 13 + seed) % 256,
                    (x * 31 + y * 3 + seed * 5) % 256,
                    (x * 11 + y * 47 + seed * 9) % 256,
                    255 - ((x + y + seed) % 4),
                )
            )
    return out


def image_from(width: int, height: int, pixels: Sequence[Pixel]) -> cmp.DecodedImage:
    data = bytearray()
    for r, g, b, a in pixels:
        data.extend((r, g, b, a))
    return cmp.DecodedImage(width=width, height=height, pixels=bytes(data))


# ---------------------------------------------------------------------------
# Synthetic mapping fixtures.
# ---------------------------------------------------------------------------


def base_mapping() -> Dict[str, Any]:
    """A structurally valid four-entry mapping, shaped like the real one."""
    return {
        "schema": cmp.MAPPING_SCHEMA,
        "target_surface": {"width": 375, "height": 812},
        "entries": [
            {
                "seed": "splash",
                "flutter_golden": "test/goldens/seed/splash_page_ar_375x812.png",
                "xd": {
                    "name": "A",
                    "manifest_id": "id-a",
                    "artboard_path": "artwork/artboard-a",
                    "width": 375,
                    "height": 812,
                },
                "normalization": "exact",
                "semantic_reason": "reason a",
            },
            {
                "seed": "onboarding",
                "flutter_golden": "test/goldens/seed/onboarding_initial_ar_375x812.png",
                "xd": {
                    "name": "B",
                    "manifest_id": "id-b",
                    "artboard_path": "artwork/artboard-b",
                    "width": 375,
                    "height": 812,
                },
                "normalization": "exact",
                "semantic_reason": "reason b",
            },
            {
                "seed": "login",
                "flutter_golden": "test/goldens/seed/login_idle_ar_375x812.png",
                "xd": {
                    "name": "C",
                    "manifest_id": "id-c",
                    "artboard_path": "artwork/artboard-c",
                    "width": 375,
                    "height": 812,
                },
                "normalization": "exact",
                "semantic_reason": "reason c",
            },
            {
                "seed": "store_preview",
                "flutter_golden": "test/goldens/seed/store_preview_loaded_ar_375x812.png",
                "xd": {
                    "name": "D",
                    "manifest_id": "id-d",
                    "artboard_path": "artwork/artboard-d",
                    "width": 375,
                    "height": 810,
                },
                "normalization": "extend_final_row_to_812",
                "semantic_reason": "reason d",
            },
        ],
    }


class MappingContractTests(unittest.TestCase):
    """The mapping is a locked contract and fails closed on every breach."""

    def setUp(self) -> None:
        self._tmp = tempfile.TemporaryDirectory()
        self.repo_root = Path(self._tmp.name)
        self.addCleanup(self._tmp.cleanup)

    def validate(self, payload: Dict[str, Any]) -> cmp.GoldenMapping:
        return cmp.validate_mapping(payload, repo_root=self.repo_root)

    def assert_rejected(self, payload: Dict[str, Any], fragment: str) -> None:
        with self.assertRaises(cmp.ComparatorError) as ctx:
            self.validate(payload)
        self.assertIn(fragment, str(ctx.exception))

    # -- happy path -------------------------------------------------------
    def test_valid_synthetic_mapping_accepted(self) -> None:
        mapping = self.validate(base_mapping())
        self.assertEqual(mapping.schema, cmp.MAPPING_SCHEMA)
        self.assertEqual((mapping.target_width, mapping.target_height), (375, 812))
        self.assertEqual(len(mapping.entries), 4)
        self.assertEqual(mapping.seeds(), cmp.ACCEPTED_SEEDS)

    def test_real_mapping_file_matches_the_locked_four_entries(self) -> None:
        mapping = cmp.load_mapping()
        self.assertEqual(mapping.schema, "merzox.xd_flutter_mapping/1")
        self.assertEqual((mapping.target_width, mapping.target_height), (375, 812))
        actual = [
            (
                e.seed,
                e.flutter_golden,
                e.xd_name,
                e.xd_manifest_id,
                e.xd_artboard_path,
                e.xd_width,
                e.xd_height,
                e.normalization,
            )
            for e in mapping.entries
        ]
        self.assertEqual(
            actual,
            [
                (
                    "splash",
                    "test/goldens/seed/splash_page_ar_375x812.png",
                    "سبلاش – 1",
                    "1ff58a48-0e8d-49eb-be2f-4b7a24adcf9c",
                    "artwork/artboard-29c52d7e-0f4c-439b-87cc-5d4a5cd8f229",
                    375,
                    812,
                    "exact",
                ),
                (
                    "onboarding",
                    "test/goldens/seed/onboarding_initial_ar_375x812.png",
                    "شاشة ترحيبية",
                    "670c3191-2903-4423-85bc-4dcfcdaf3a6f",
                    "artwork/artboard-39b3dc74-2728-41f4-a7ff-52ab7d2bbc1f",
                    375,
                    812,
                    "exact",
                ),
                (
                    "login",
                    "test/goldens/seed/login_idle_ar_375x812.png",
                    "تسجيل الدخول",
                    "7253b94f-6b60-4685-83c2-e3086ed0ac20",
                    "artwork/artboard-b371399a-3aed-45f5-8a33-b1f7c4972ef7",
                    375,
                    812,
                    "exact",
                ),
                (
                    "store_preview",
                    "test/goldens/seed/store_preview_loaded_ar_375x812.png",
                    "معاينة المتجر",
                    "693ab1c9-14b2-4448-a867-cb5553a8f813",
                    "artwork/artboard-98945093-5916-454b-a1ea-946956675bf0",
                    375,
                    810,
                    "extend_final_row_to_812",
                ),
            ],
        )

    def test_real_mapping_goldens_exist_under_repo_root(self) -> None:
        mapping = cmp.load_mapping()
        for entry in mapping.entries:
            resolved = cmp.resolve_repo_relative(entry.flutter_golden, cmp.REPO_ROOT)
            self.assertTrue(resolved.is_file(), f"missing golden: {resolved}")

    def test_repo_root_is_derived_from_file_not_cwd(self) -> None:
        self.assertTrue((cmp.REPO_ROOT / "pubspec.yaml").is_file())
        self.assertEqual(
            cmp.DEFAULT_MAPPING_PATH,
            cmp.REPO_ROOT / "tools" / "xd_reference" / "golden_mapping.json",
        )

    # -- rejection paths --------------------------------------------------
    def test_wrong_schema_rejected(self) -> None:
        payload = base_mapping()
        payload["schema"] = "merzox.xd_flutter_mapping/2"
        self.assert_rejected(payload, "Mapping schema must be")

    def test_non_object_mapping_rejected(self) -> None:
        self.assert_rejected([], "Mapping must be a JSON object.")

    def test_wrong_target_dimensions_rejected(self) -> None:
        payload = base_mapping()
        payload["target_surface"] = {"width": 390, "height": 844}
        self.assert_rejected(payload, "target surface must be exactly 375x812")

    def test_missing_target_surface_rejected(self) -> None:
        payload = base_mapping()
        del payload["target_surface"]
        self.assert_rejected(payload, "'target_surface' must be an object")

    def test_wrong_entry_count_rejected(self) -> None:
        payload = base_mapping()
        payload["entries"] = payload["entries"][:3]
        self.assert_rejected(payload, "exactly 4 entries")

    def test_duplicate_seed_rejected(self) -> None:
        payload = base_mapping()
        payload["entries"][1]["seed"] = "splash"
        self.assert_rejected(payload, "duplicate seed(s): ['splash']")

    def test_duplicate_manifest_id_rejected(self) -> None:
        payload = base_mapping()
        payload["entries"][1]["xd"]["manifest_id"] = "id-a"
        self.assert_rejected(payload, "duplicate XD manifest id(s): ['id-a']")

    def test_duplicate_artboard_path_rejected(self) -> None:
        payload = base_mapping()
        payload["entries"][2]["xd"]["artboard_path"] = "artwork/artboard-a"
        self.assert_rejected(
            payload, "duplicate XD artboard path(s): ['artwork/artboard-a']"
        )

    def test_unexpected_seed_name_rejected(self) -> None:
        payload = base_mapping()
        payload["entries"][2]["seed"] = "checkout"
        self.assert_rejected(payload, "Mapping seeds must be exactly")

    def test_reordered_seeds_rejected(self) -> None:
        payload = base_mapping()
        payload["entries"][0], payload["entries"][1] = (
            payload["entries"][1],
            payload["entries"][0],
        )
        self.assert_rejected(payload, "Mapping seeds must be exactly")

    def test_missing_required_entry_field_rejected(self) -> None:
        for field in cmp.REQUIRED_ENTRY_FIELDS:
            payload = base_mapping()
            del payload["entries"][0][field]
            self.assert_rejected(payload, f"required field '{field}' is missing")

    def test_missing_required_xd_field_rejected(self) -> None:
        for field in cmp.REQUIRED_XD_FIELDS:
            payload = base_mapping()
            del payload["entries"][0]["xd"][field]
            self.assert_rejected(payload, f"required field 'xd.{field}' is missing")

    def test_invalid_normalization_rejected(self) -> None:
        payload = base_mapping()
        payload["entries"][0]["normalization"] = "scale_to_fit"
        self.assert_rejected(payload, "unsupported normalization policy 'scale_to_fit'")

    def test_exact_normalization_with_non_target_dimensions_rejected(self) -> None:
        payload = base_mapping()
        payload["entries"][0]["xd"]["height"] = 810
        self.assert_rejected(payload, "requires XD dimensions 375x812")

    def test_extend_normalization_with_wrong_dimensions_rejected(self) -> None:
        payload = base_mapping()
        payload["entries"][3]["xd"]["height"] = 812
        self.assert_rejected(payload, "requires XD dimensions 375x810")

    def test_non_integer_dimension_rejected(self) -> None:
        payload = base_mapping()
        payload["entries"][0]["xd"]["width"] = "375"
        self.assert_rejected(payload, "'width' must be a positive integer")

    def test_repo_path_escape_rejected(self) -> None:
        for bad in ("../outside/x.png", "test/../../x.png"):
            payload = base_mapping()
            payload["entries"][0]["flutter_golden"] = bad
            self.assert_rejected(payload, "escapes the repository root")

    def test_absolute_flutter_golden_rejected(self) -> None:
        payload = base_mapping()
        payload["entries"][0]["flutter_golden"] = "/etc/passwd"
        self.assert_rejected(payload, "must not be absolute")

    def test_backslash_flutter_golden_rejected(self) -> None:
        payload = base_mapping()
        payload["entries"][0]["flutter_golden"] = "test\\goldens\\seed\\x.png"
        self.assert_rejected(payload, "must use '/' separators")

    def test_resolve_repo_relative_returns_path_under_root(self) -> None:
        resolved = cmp.resolve_repo_relative("a/b/c.png", self.repo_root)
        self.assertEqual(resolved, self.repo_root / "a" / "b" / "c.png")

    def test_load_mapping_missing_file_rejected(self) -> None:
        missing = self.repo_root / "nope.json"
        with self.assertRaises(cmp.ComparatorError) as ctx:
            cmp.load_mapping(missing, repo_root=self.repo_root)
        self.assertIn("Mapping file not found", str(ctx.exception))

    def test_load_mapping_invalid_json_rejected(self) -> None:
        broken = self.repo_root / "broken.json"
        broken.write_text("{ not json", encoding="utf-8")
        with self.assertRaises(cmp.ComparatorError) as ctx:
            cmp.load_mapping(broken, repo_root=self.repo_root)
        self.assertIn("Cannot read mapping", str(ctx.exception))

    def test_load_mapping_round_trips_a_written_document(self) -> None:
        path = self.repo_root / "m.json"
        path.write_text(
            json.dumps(base_mapping(), ensure_ascii=False), encoding="utf-8"
        )
        mapping = cmp.load_mapping(path, repo_root=self.repo_root)
        self.assertEqual(mapping.seeds(), cmp.ACCEPTED_SEEDS)


class SeedSelectionTests(unittest.TestCase):
    def setUp(self) -> None:
        self._tmp = tempfile.TemporaryDirectory()
        self.addCleanup(self._tmp.cleanup)
        self.mapping = cmp.validate_mapping(
            base_mapping(), repo_root=Path(self._tmp.name)
        )

    def test_all_follows_mapping_order(self) -> None:
        selected = cmp.select_entries(self.mapping, cmp.SEED_ALL)
        self.assertEqual(
            [e.seed for e in selected],
            ["splash", "onboarding", "login", "store_preview"],
        )

    def test_single_seed_selects_only_that_entry(self) -> None:
        for seed in cmp.ACCEPTED_SEEDS:
            selected = cmp.select_entries(self.mapping, seed)
            self.assertEqual([e.seed for e in selected], [seed])

    def test_unknown_seed_rejected(self) -> None:
        with self.assertRaises(cmp.ComparatorError) as ctx:
            cmp.select_entries(self.mapping, "cart")
        self.assertIn("Unknown seed 'cart'", str(ctx.exception))

    def test_cli_seed_choices_are_exactly_all_plus_four(self) -> None:
        parser = cmp.build_arg_parser()
        action = next(a for a in parser._actions if a.dest == "seed")
        self.assertEqual(
            list(action.choices),
            ["all", "splash", "onboarding", "login", "store_preview"],
        )

    def test_cli_requires_the_four_documented_arguments(self) -> None:
        parser = cmp.build_arg_parser()
        required = {a.dest for a in parser._actions if getattr(a, "required", False)}
        self.assertEqual(required, {"xd", "seed", "output_json", "artifact_dir"})
        mapping_action = next(a for a in parser._actions if a.dest == "mapping")
        self.assertFalse(mapping_action.required)
        self.assertIsNone(mapping_action.default)


class PngDecoderTests(unittest.TestCase):
    def test_valid_rgba_png_decodes(self) -> None:
        pixels = gradient_pixels(5, 4)
        image = cmp.decode_png(encode_png(5, 4, pixels))
        self.assertEqual((image.width, image.height), (5, 4))
        self.assertEqual(image.rgba_tuples(), pixels)

    def test_all_scanline_filters_reconstruct_identically(self) -> None:
        pixels = gradient_pixels(9, 7, seed=3)
        expected = cmp.decode_png(encode_png(9, 7, pixels, filter_type=0)).pixels
        for filter_type in (0, 1, 2, 3, 4):
            with self.subTest(filter_type=filter_type):
                decoded = cmp.decode_png(
                    encode_png(9, 7, pixels, filter_type=filter_type)
                )
                self.assertEqual(decoded.pixels, expected)
                self.assertEqual(decoded.rgba_tuples(), pixels)

    def test_paeth_predictor_matches_the_spec(self) -> None:
        self.assertEqual(cmp._paeth_predictor(10, 20, 30), 10)
        self.assertEqual(cmp._paeth_predictor(30, 20, 10), 30)
        self.assertEqual(cmp._paeth_predictor(10, 40, 20), 40)
        self.assertEqual(cmp._paeth_predictor(0, 0, 0), 0)

    def test_grayscale_color_type_0_expands_to_rgba(self) -> None:
        pixels = [(10, 0, 0, 255), (200, 0, 0, 255)]
        image = cmp.decode_png(encode_png(2, 1, pixels, color_type=0, filter_type=4))
        self.assertEqual(
            image.rgba_tuples(), [(10, 10, 10, 255), (200, 200, 200, 255)]
        )

    def test_truecolor_color_type_2_gets_opaque_alpha(self) -> None:
        pixels = [(1, 2, 3, 7), (4, 5, 6, 9)]
        image = cmp.decode_png(encode_png(2, 1, pixels, color_type=2, filter_type=3))
        self.assertEqual(image.rgba_tuples(), [(1, 2, 3, 255), (4, 5, 6, 255)])

    def test_gray_alpha_color_type_4_preserves_alpha(self) -> None:
        pixels = [(60, 0, 0, 128), (61, 0, 0, 3)]
        image = cmp.decode_png(encode_png(2, 1, pixels, color_type=4, filter_type=1))
        self.assertEqual(image.rgba_tuples(), [(60, 60, 60, 128), (61, 61, 61, 3)])

    def test_bad_signature_rejected(self) -> None:
        data = bytearray(encode_png(2, 2, gradient_pixels(2, 2)))
        data[1] = ord("X")
        with self.assertRaises(cmp.ComparatorError) as ctx:
            cmp.decode_png(bytes(data))
        self.assertIn("bad 8-byte signature", str(ctx.exception))

    def test_unsupported_bit_depth_rejected(self) -> None:
        data = encode_png(2, 2, gradient_pixels(2, 2), header_bit_depth=16)
        with self.assertRaises(cmp.ComparatorError) as ctx:
            cmp.decode_png(data)
        self.assertIn("Unsupported PNG bit depth 16", str(ctx.exception))

    def test_palette_color_type_rejected(self) -> None:
        data = encode_png(2, 2, gradient_pixels(2, 2), header_color_type=3)
        with self.assertRaises(cmp.ComparatorError) as ctx:
            cmp.decode_png(data)
        self.assertIn("Unsupported PNG colour type 3", str(ctx.exception))

    def test_interlaced_png_rejected(self) -> None:
        data = encode_png(2, 2, gradient_pixels(2, 2), header_interlace=1)
        with self.assertRaises(cmp.ComparatorError) as ctx:
            cmp.decode_png(data)
        self.assertIn("Unsupported PNG interlace method 1", str(ctx.exception))

    def test_truncated_png_rejected(self) -> None:
        data = encode_png(4, 4, gradient_pixels(4, 4))
        with self.assertRaises(cmp.ComparatorError):
            cmp.decode_png(data[: len(data) - 10])

    def test_corrupt_chunk_crc_rejected(self) -> None:
        data = bytearray(encode_png(4, 4, gradient_pixels(4, 4)))
        data[-1] ^= 0xFF  # corrupt the IEND chunk's stored CRC
        with self.assertRaises(cmp.ComparatorError) as ctx:
            cmp.decode_png(bytes(data))
        self.assertIn("failed its CRC check", str(ctx.exception))

    def test_missing_iend_rejected(self) -> None:
        data = encode_png(2, 2, gradient_pixels(2, 2))
        with self.assertRaises(cmp.ComparatorError) as ctx:
            cmp.decode_png(data[: -len(_chunk(b"IEND", b""))])
        self.assertIn("no IEND chunk", str(ctx.exception))

    def test_non_bytes_input_rejected(self) -> None:
        with self.assertRaises(cmp.ComparatorError):
            cmp.decode_png("not bytes")  # type: ignore[arg-type]

    def test_decode_png_file_round_trip_and_hash(self) -> None:
        with tempfile.TemporaryDirectory() as tmp:
            path = Path(tmp) / "sample.png"
            pixels = gradient_pixels(6, 5, seed=11)
            data = encode_png(6, 5, pixels)
            path.write_bytes(data)
            image = cmp.decode_png_file(path)
            self.assertEqual(image.rgba_tuples(), pixels)
            self.assertEqual(cmp.sha256_file(path), cmp.hashlib.sha256(data).hexdigest())

    def test_decoded_image_helpers(self) -> None:
        image = image_from(2, 2, [(1, 2, 3, 4), (5, 6, 7, 8), (9, 10, 11, 12), (13, 14, 15, 16)])
        self.assertEqual(image.stride, 8)
        self.assertEqual(image.row(1), bytes([9, 10, 11, 12, 13, 14, 15, 16]))
        self.assertEqual(image.pixel(1, 0), (5, 6, 7, 8))
        with self.assertRaises(cmp.ComparatorError):
            image.row(2)
        with self.assertRaises(cmp.ComparatorError):
            image.pixel(2, 0)

    def test_decoded_image_rejects_inconsistent_buffer(self) -> None:
        with self.assertRaises(cmp.ComparatorError):
            cmp.DecodedImage(width=2, height=2, pixels=b"\x00" * 8)


class NormalizationTests(unittest.TestCase):
    def test_exact_normalization_success(self) -> None:
        image = image_from(1, 1, [(1, 2, 3, 4)])
        result = cmp.normalize_reference(
            image,
            policy="exact",
            declared_width=1,
            declared_height=1,
            target_width=1,
            target_height=1,
        )
        self.assertIs(result.image, image)
        self.assertEqual(result.appended_row_count, 0)
        self.assertEqual(result.policy, "exact")

    def test_exact_normalization_on_the_real_surface(self) -> None:
        image = image_from(375, 2, gradient_pixels(375, 2))
        with self.assertRaises(cmp.ComparatorError) as ctx:
            cmp.normalize_reference(
                image, policy="exact", declared_width=375, declared_height=812
            )
        self.assertIn("requires a decoded XD reference of 375x812", str(ctx.exception))

    def test_exact_normalization_rejects_wrong_declared_dimensions(self) -> None:
        image = image_from(1, 1, [(0, 0, 0, 255)])
        with self.assertRaises(cmp.ComparatorError) as ctx:
            cmp.normalize_reference(
                image,
                policy="exact",
                declared_width=375,
                declared_height=810,
                target_width=375,
                target_height=812,
            )
        self.assertIn("mapping XD dimensions to equal the target", str(ctx.exception))

    def test_extend_final_row_converts_810_to_812(self) -> None:
        pixels = gradient_pixels(375, 810, seed=5)
        result = cmp.normalize_reference(
            image_from(375, 810, pixels),
            policy="extend_final_row_to_812",
            declared_width=375,
            declared_height=810,
        )
        self.assertEqual((result.image.width, result.image.height), (375, 812))
        self.assertEqual(result.appended_row_count, 2)
        self.assertEqual((result.source_width, result.source_height), (375, 810))

    def test_extend_final_row_duplicates_the_last_row_exactly_twice(self) -> None:
        # Give the final row a colour that appears nowhere else, so "the last
        # row was appended exactly twice" is directly observable.
        pixels = [(0, 0, 0, 255)] * (375 * 809) + [(7, 9, 11, 255)] * 375
        result = cmp.normalize_reference(
            image_from(375, 810, pixels),
            policy="extend_final_row_to_812",
            declared_width=375,
            declared_height=810,
        )
        normalized = result.image
        marker = bytes([7, 9, 11, 255]) * 375
        self.assertEqual(normalized.height, 812)
        marker_rows = [y for y in range(812) if normalized.row(y) == marker]
        self.assertEqual(marker_rows, [809, 810, 811])
        self.assertEqual(normalized.row(808), bytes([0, 0, 0, 255]) * 375)

    def test_extend_final_row_preserves_pixels_and_repeats_the_final_row(self) -> None:
        pixels = gradient_pixels(375, 810, seed=8)
        source = image_from(375, 810, pixels)
        result = cmp.normalize_reference(
            source,
            policy="extend_final_row_to_812",
            declared_width=375,
            declared_height=810,
        )
        normalized = result.image
        # All 375x810 real pixels survive untouched, in place.
        self.assertEqual(normalized.pixels[: len(source.pixels)], source.pixels)
        last = source.row(809)
        self.assertEqual(normalized.row(809), last)
        self.assertEqual(normalized.row(810), last)
        self.assertEqual(normalized.row(811), last)
        self.assertEqual(
            len(normalized.pixels), len(source.pixels) + 2 * source.stride
        )

    def test_extend_final_row_rejects_wrong_source_height(self) -> None:
        source = image_from(375, 812, gradient_pixels(375, 812))
        with self.assertRaises(cmp.ComparatorError) as ctx:
            cmp.normalize_reference(
                source,
                policy="extend_final_row_to_812",
                declared_width=375,
                declared_height=810,
            )
        self.assertIn("requires a decoded XD reference of 375x810", str(ctx.exception))

    def test_extend_final_row_rejects_wrong_declared_dimensions(self) -> None:
        source = image_from(375, 810, gradient_pixels(375, 810))
        with self.assertRaises(cmp.ComparatorError) as ctx:
            cmp.normalize_reference(
                source,
                policy="extend_final_row_to_812",
                declared_width=375,
                declared_height=812,
            )
        self.assertIn("requires mapping XD dimensions 375x810", str(ctx.exception))

    def test_extend_final_row_rejects_non_canonical_target(self) -> None:
        source = image_from(375, 810, gradient_pixels(375, 810))
        with self.assertRaises(cmp.ComparatorError) as ctx:
            cmp.normalize_reference(
                source,
                policy="extend_final_row_to_812",
                declared_width=375,
                declared_height=810,
                target_width=375,
                target_height=800,
            )
        self.assertIn("only targets 375x812", str(ctx.exception))

    def test_unsupported_policy_rejected(self) -> None:
        source = image_from(1, 1, [(0, 0, 0, 0)])
        with self.assertRaises(cmp.ComparatorError) as ctx:
            cmp.normalize_reference(
                source,
                policy="crop_to_812",
                declared_width=1,
                declared_height=1,
            )
        self.assertIn("Unsupported normalization policy 'crop_to_812'", str(ctx.exception))

    def test_normalized_rgba_sha_is_deterministic(self) -> None:
        pixels = gradient_pixels(375, 810, seed=4)
        first = cmp.normalize_reference(
            image_from(375, 810, pixels),
            policy="extend_final_row_to_812",
            declared_width=375,
            declared_height=810,
        )
        second = cmp.normalize_reference(
            image_from(375, 810, list(pixels)),
            policy="extend_final_row_to_812",
            declared_width=375,
            declared_height=810,
        )
        self.assertEqual(first.image.sha256(), second.image.sha256())
        self.assertEqual(
            first.image.sha256(),
            cmp.hashlib.sha256(first.image.pixels).hexdigest(),
        )
        self.assertNotEqual(
            first.image.sha256(),
            cmp.hashlib.sha256(image_from(375, 810, pixels).pixels).hexdigest(),
        )

    def test_normalization_dict_declares_no_visual_correction(self) -> None:
        result = cmp.normalize_reference(
            image_from(375, 810, gradient_pixels(375, 810)),
            policy="extend_final_row_to_812",
            declared_width=375,
            declared_height=810,
        )
        payload = result.to_dict()
        for flag in ("scaled", "interpolated", "cropped", "translated", "color_adjusted"):
            self.assertFalse(payload[flag], flag)
        self.assertEqual(payload["appended_row_count"], 2)
        self.assertEqual(payload["normalized_height"], 812)


class MetricsTests(unittest.TestCase):
    def test_identical_images_measure_zero_difference(self) -> None:
        pixels = gradient_pixels(16, 9, seed=6)
        left = image_from(16, 9, pixels)
        right = image_from(16, 9, list(pixels))
        metrics = cmp.compute_metrics(left, right)
        self.assertEqual(metrics["rgb_mae"], 0.0)
        self.assertEqual(metrics["rgb_rms"], 0.0)
        self.assertEqual(metrics["exact_pixel_diff_ratio"], 0.0)
        self.assertEqual(metrics["differing_pixel_count"], 0)
        self.assertEqual(metrics["rgb_channels_within_5_ratio"], 1.0)
        self.assertEqual(metrics["rgb_channels_within_10_ratio"], 1.0)
        self.assertEqual(metrics["coarse_luma_mae"], 0.0)
        self.assertEqual(metrics["pixel_count"], 144)
        self.assertEqual(metrics["rgb_channel_count"], 432)

    def test_known_single_channel_difference(self) -> None:
        reference = image_from(1, 1, [(10, 10, 10, 255)])
        flutter = image_from(1, 1, [(16, 10, 10, 255)])
        metrics = cmp.compute_metrics(reference, flutter)
        self.assertAlmostEqual(metrics["rgb_mae"], 2.0)
        self.assertAlmostEqual(metrics["rgb_rms"], (36 / 3) ** 0.5)
        self.assertEqual(metrics["exact_pixel_diff_ratio"], 1.0)
        self.assertEqual(metrics["differing_pixel_count"], 1)
        # A 6-step difference is outside the 5 tolerance but inside 10.
        self.assertAlmostEqual(metrics["rgb_channels_within_5_ratio"], 2 / 3)
        self.assertEqual(metrics["rgb_channels_within_10_ratio"], 1.0)

    def test_within_5_ratio_boundary_is_inclusive(self) -> None:
        reference = image_from(1, 1, [(0, 0, 0, 255)])
        inside = cmp.compute_metrics(reference, image_from(1, 1, [(5, 5, 5, 255)]))
        outside = cmp.compute_metrics(reference, image_from(1, 1, [(6, 6, 6, 255)]))
        self.assertEqual(inside["rgb_channels_within_5_ratio"], 1.0)
        self.assertEqual(outside["rgb_channels_within_5_ratio"], 0.0)
        self.assertEqual(outside["rgb_channels_within_10_ratio"], 1.0)

    def test_within_10_ratio_boundary_is_inclusive(self) -> None:
        reference = image_from(1, 1, [(0, 0, 0, 255)])
        inside = cmp.compute_metrics(reference, image_from(1, 1, [(10, 10, 10, 255)]))
        outside = cmp.compute_metrics(reference, image_from(1, 1, [(11, 11, 11, 255)]))
        self.assertEqual(inside["rgb_channels_within_10_ratio"], 1.0)
        self.assertEqual(outside["rgb_channels_within_10_ratio"], 0.0)

    def test_mixed_ratios_over_several_pixels(self) -> None:
        reference = image_from(
            2, 2, [(0, 0, 0, 255), (0, 0, 0, 255), (0, 0, 0, 255), (0, 0, 0, 255)]
        )
        flutter = image_from(
            2,
            2,
            [(0, 0, 0, 255), (3, 3, 3, 255), (8, 8, 8, 255), (40, 40, 40, 255)],
        )
        metrics = cmp.compute_metrics(reference, flutter)
        # 6 of 12 channels within 5; 9 of 12 within 10.
        self.assertAlmostEqual(metrics["rgb_channels_within_5_ratio"], 6 / 12)
        self.assertAlmostEqual(metrics["rgb_channels_within_10_ratio"], 9 / 12)
        self.assertAlmostEqual(metrics["rgb_mae"], (0 + 9 + 24 + 120) / 12)
        self.assertEqual(metrics["exact_pixel_diff_ratio"], 0.75)

    def test_coarse_luma_is_deterministic_integer_bt601(self) -> None:
        self.assertEqual(cmp.coarse_luma(0, 0, 0), 0)
        self.assertEqual(cmp.coarse_luma(255, 255, 255), 255)
        self.assertEqual(cmp.coarse_luma(10, 10, 10), 10)
        self.assertEqual(cmp.coarse_luma(16, 10, 10), 11)
        metrics = cmp.compute_metrics(
            image_from(1, 1, [(10, 10, 10, 255)]),
            image_from(1, 1, [(16, 10, 10, 255)]),
        )
        self.assertEqual(metrics["coarse_luma_mae"], 1.0)

    def test_coarse_luma_ignores_alpha(self) -> None:
        metrics = cmp.compute_metrics(
            image_from(1, 1, [(10, 20, 30, 255)]),
            image_from(1, 1, [(10, 20, 30, 0)]),
        )
        self.assertEqual(metrics["coarse_luma_mae"], 0.0)
        self.assertEqual(metrics["rgb_mae"], 0.0)
        # Exact-pixel difference uses complete RGBA equality, so alpha counts.
        self.assertEqual(metrics["exact_pixel_diff_ratio"], 1.0)

    def test_metrics_are_order_independent_and_reproducible(self) -> None:
        reference = image_from(37, 21, gradient_pixels(37, 21, seed=1))
        flutter = image_from(37, 21, gradient_pixels(37, 21, seed=2))
        first = cmp.compute_metrics(reference, flutter)
        second = cmp.compute_metrics(reference, flutter)
        self.assertEqual(first, second)
        self.assertGreater(first["rgb_mae"], 0.0)
        self.assertGreater(first["rgb_rms"], 0.0)
        self.assertGreater(first["exact_pixel_diff_ratio"], 0.0)

    def test_metrics_reject_size_mismatch(self) -> None:
        with self.assertRaises(cmp.ComparatorError) as ctx:
            cmp.compute_metrics(
                image_from(2, 1, [(0, 0, 0, 0), (0, 0, 0, 0)]),
                image_from(1, 1, [(0, 0, 0, 0)]),
            )
        self.assertIn("different sizes", str(ctx.exception))

    def test_metrics_contain_no_pass_fail_vocabulary(self) -> None:
        metrics = cmp.compute_metrics(
            image_from(1, 1, [(1, 2, 3, 4)]), image_from(1, 1, [(1, 2, 3, 4)])
        )
        for key in metrics:
            for banned in ("pass", "fail", "parity", "pixel_perfect"):
                self.assertNotIn(banned, key)


class ExporterIntegrationTests(unittest.TestCase):
    def setUp(self) -> None:
        self._tmp = tempfile.TemporaryDirectory()
        self.addCleanup(self._tmp.cleanup)
        self.entry = cmp.validate_mapping(
            base_mapping(), repo_root=Path(self._tmp.name)
        ).entries[0]

    def test_positive_counts_keeps_only_positive_sorted_entries(self) -> None:
        self.assertEqual(
            cmp.positive_counts({"b": 2, "a": 0, "c": 1}, "handled_node_counts"),
            {"b": 2, "c": 1},
        )
        self.assertEqual(
            list(cmp.positive_counts({"z": 1, "a": 1}, "handled_node_counts")),
            ["a", "z"],
        )

    def test_positive_counts_rejects_non_integer_values(self) -> None:
        with self.assertRaises(cmp.ComparatorError):
            cmp.positive_counts({"a": "1"}, "handled_node_counts")
        with self.assertRaises(cmp.ComparatorError):
            cmp.positive_counts([], "handled_node_counts")

    def test_exporter_summary_fails_closed_on_unsupported_nodes(self) -> None:
        report = {
            "iteration": "X",
            "schema": "merzox.xd_reference_exporter/1",
            "handled_node_counts": {"rect": 3},
            "unsupported_node_counts": {"filter:uxdesign#blur:background": 2},
        }
        with self.assertRaises(cmp.ComparatorError) as ctx:
            cmp.exporter_summary(report, self.entry)
        self.assertIn("visually incomplete", str(ctx.exception))

    def test_exporter_summary_accepts_zeroed_unsupported_counts(self) -> None:
        report = {
            "iteration": cmp.xdref.EXPORTER_ITERATION,
            "schema": cmp.xdref.REPORT_SCHEMA,
            "handled_node_counts": {"rect": 3, "never": 0},
            "unsupported_node_counts": {"filter:uxdesign#blur:background": 0},
            "brand_normalization_enabled": True,
            "brand_replacement_count": 1,
        }
        summary = cmp.exporter_summary(report, self.entry)
        self.assertEqual(summary["handled_node_counts"], {"rect": 3})
        self.assertEqual(summary["unsupported_node_counts"], {})
        self.assertEqual(summary["iteration"], cmp.xdref.EXPORTER_ITERATION)
        self.assertEqual(summary["schema"], cmp.xdref.REPORT_SCHEMA)
        self.assertTrue(summary["brand_normalization_enabled"])

    def test_verify_export_identity_accepts_the_locked_identity(self) -> None:
        cmp.verify_export_identity(
            {
                "selected_artboard_id": self.entry.xd_manifest_id,
                "selected_artboard_path": self.entry.xd_artboard_path,
                "selected_artboard_name": self.entry.xd_name,
            },
            self.entry,
        )

    def test_verify_export_identity_rejects_a_different_artboard(self) -> None:
        for field in (
            "selected_artboard_id",
            "selected_artboard_path",
            "selected_artboard_name",
        ):
            report = {
                "selected_artboard_id": self.entry.xd_manifest_id,
                "selected_artboard_path": self.entry.xd_artboard_path,
                "selected_artboard_name": self.entry.xd_name,
            }
            report[field] = "something-else"
            with self.assertRaises(cmp.ComparatorError) as ctx:
                cmp.verify_export_identity(report, self.entry)
            self.assertIn(field, str(ctx.exception))

    def test_verify_manifest_identity_selects_by_manifest_id_only(self) -> None:
        entry = self.entry

        class FakePackage:
            def __init__(self, artboards: List[Any]) -> None:
                self._artboards = artboards

            def artboards(self) -> List[Any]:
                return self._artboards

        good = cmp.xdref.ManifestArtboard(
            name=entry.xd_name,
            manifest_id=entry.xd_manifest_id,
            path=entry.xd_artboard_path,
            x=0.0,
            y=0.0,
            width=float(entry.xd_width),
            height=float(entry.xd_height),
        )
        # A same-named decoy with a different id must never be selected.
        decoy = cmp.xdref.ManifestArtboard(
            name=entry.xd_name,
            manifest_id="other-id",
            path="artwork/artboard-other",
            x=0.0,
            y=0.0,
            width=375.0,
            height=812.0,
        )
        resolved = cmp.verify_manifest_identity(FakePackage([decoy, good]), entry)
        self.assertIs(resolved, good)

        with self.assertRaises(cmp.ComparatorError) as ctx:
            cmp.verify_manifest_identity(FakePackage([decoy]), entry)
        self.assertIn("is absent from the XD package", str(ctx.exception))

        wrong_path = cmp.xdref.ManifestArtboard(
            name=entry.xd_name,
            manifest_id=entry.xd_manifest_id,
            path="artwork/artboard-moved",
            x=0.0,
            y=0.0,
            width=375.0,
            height=812.0,
        )
        with self.assertRaises(cmp.ComparatorError) as ctx:
            cmp.verify_manifest_identity(FakePackage([wrong_path]), entry)
        self.assertIn("but the mapping locks", str(ctx.exception))

        wrong_size = cmp.xdref.ManifestArtboard(
            name=entry.xd_name,
            manifest_id=entry.xd_manifest_id,
            path=entry.xd_artboard_path,
            x=0.0,
            y=0.0,
            width=375.0,
            height=810.0,
        )
        with self.assertRaises(cmp.ComparatorError) as ctx:
            cmp.verify_manifest_identity(FakePackage([wrong_size]), entry)
        self.assertIn("375x810", str(ctx.exception))

    def test_artifact_stems_are_deterministic_per_seed(self) -> None:
        mapping = cmp.validate_mapping(
            base_mapping(), repo_root=Path(self._tmp.name)
        )
        self.assertEqual(
            [cmp.artifact_stem(e) for e in mapping.entries],
            ["splash.xd", "onboarding.xd", "login.xd", "store_preview.xd"],
        )

    def test_run_comparison_rejects_a_missing_xd_package(self) -> None:
        with self.assertRaises(cmp.ComparatorError) as ctx:
            cmp.run_comparison(
                xd_path=Path(self._tmp.name) / "absent.xd",
                seed="splash",
                artifact_dir=Path(self._tmp.name) / "artifacts",
                mapping_path=None,
            )
        self.assertIn("XD package not found", str(ctx.exception))

    def test_cli_reports_a_missing_xd_package_without_writing_a_report(self) -> None:
        tmp = Path(self._tmp.name)
        output = tmp / "report.json"
        stderr = io.StringIO()
        with contextlib.redirect_stderr(stderr):
            exit_code = cmp.main(
                [
                    "--xd",
                    str(tmp / "absent.xd"),
                    "--seed",
                    "all",
                    "--output-json",
                    str(output),
                    "--artifact-dir",
                    str(tmp / "artifacts"),
                ]
            )
        self.assertEqual(exit_code, 2)
        self.assertIn("XD package not found", stderr.getvalue())
        self.assertFalse(output.exists())


def synthetic_result(seed: str) -> Dict[str, Any]:
    return {
        "seed": seed,
        "flutter": {
            "golden_path": f"test/goldens/seed/{seed}.png",
            "width": 375,
            "height": 812,
            "file_sha256": "0" * 64,
        },
        "xd": {
            "artboard_name": seed,
            "manifest_id": f"id-{seed}",
            "artboard_path": f"artwork/artboard-{seed}",
            "native_width": 375,
            "native_height": 812,
            "exported_width": 375,
            "exported_height": 812,
            "exported_png_sha256": "1" * 64,
        },
        "normalization": {"policy": "exact", "appended_row_count": 0},
        "exporter": {
            "iteration": "X",
            "schema": "merzox.xd_reference_exporter/1",
            "handled_node_counts": {"rect": 1},
            "unsupported_node_counts": {},
        },
        "metrics": {"rgb_mae": 1.5, "rgb_rms": 2.25},
        "measurement_status": cmp.MEASUREMENT_STATUS_MEASURED,
        "semantic_reason": "locked",
    }


class ReportTests(unittest.TestCase):
    def test_report_uses_the_locked_schemas_and_surface(self) -> None:
        report = cmp.build_report([synthetic_result("splash")])
        self.assertEqual(report["schema"], "merzox.xd_flutter_comparison/1")
        self.assertEqual(report["mapping_schema"], "merzox.xd_flutter_mapping/1")
        self.assertEqual(report["target_surface"], {"width": 375, "height": 812})

    def test_all_result_ordering_follows_mapping_ordering(self) -> None:
        with tempfile.TemporaryDirectory() as tmp:
            mapping = cmp.validate_mapping(base_mapping(), repo_root=Path(tmp))
        entries = cmp.select_entries(mapping, cmp.SEED_ALL)
        report = cmp.build_report([synthetic_result(e.seed) for e in entries])
        self.assertEqual(
            [r["seed"] for r in report["results"]],
            ["splash", "onboarding", "login", "store_preview"],
        )

    def test_serialization_is_deterministic_and_sorted(self) -> None:
        report = cmp.build_report(
            [synthetic_result(seed) for seed in cmp.ACCEPTED_SEEDS]
        )
        first = cmp.serialize_report(report)
        second = cmp.serialize_report(copy.deepcopy(report))
        self.assertEqual(first, second)
        self.assertTrue(first.endswith("}\n"))
        self.assertEqual(first.count("\n") - 1, first.rstrip("\n").count("\n"))
        # sort_keys puts "mapping_schema" before "measurement_policy" before
        # "results", and the result list order is preserved regardless.
        reloaded = json.loads(first)
        self.assertEqual(
            [r["seed"] for r in reloaded["results"]], list(cmp.ACCEPTED_SEEDS)
        )
        self.assertEqual(
            list(reloaded.keys()),
            [
                "mapping_schema",
                "measurement_policy",
                "results",
                "schema",
                "target_surface",
            ],
        )

    def test_serialization_keeps_arabic_readable(self) -> None:
        result = synthetic_result("splash")
        result["xd"]["artboard_name"] = "معاينة المتجر"
        text = cmp.serialize_report(cmp.build_report([result]))
        self.assertIn("معاينة المتجر", text)
        self.assertNotIn("\\u0645", text)

    def test_report_carries_no_volatile_provenance(self) -> None:
        text = cmp.serialize_report(
            cmp.build_report([synthetic_result(s) for s in cmp.ACCEPTED_SEEDS])
        )
        lowered = text.lower()
        for banned in ("timestamp", "generated_at", "artifact_dir", "c:\\", "/tmp/"):
            self.assertNotIn(banned, lowered)

    def test_measurement_status_vocabulary_is_only_measured(self) -> None:
        self.assertEqual(cmp.MEASUREMENT_STATUS_MEASURED, "measured")
        report = cmp.build_report([synthetic_result("splash")])
        self.assertEqual(report["results"][0]["measurement_status"], "measured")
        self.assertEqual(
            report["measurement_policy"]["measurement_status_vocabulary"],
            ["measured"],
        )

    def test_measurement_policy_declares_no_parity_threshold(self) -> None:
        policy = cmp.build_report([])["measurement_policy"]
        self.assertIs(policy["parity_threshold_exists"], False)
        self.assertIsNone(policy["parity_threshold"])
        self.assertIs(policy["metrics_are_measurements_only"], True)
        self.assertIs(policy["metrics_are_pass_fail"], False)
        self.assertIs(policy["pixel_perfect_claimed"], False)
        self.assertIs(policy["semantic_mapping_selected_by_visual_score"], False)
        self.assertEqual(policy["semantic_mapping_selector"], "xd_manifest_id")
        # No numeric threshold of any kind may live in the policy.
        for key, value in policy.items():
            self.assertNotIsInstance(value, float, key)
            if isinstance(value, int) and not isinstance(value, bool):
                self.fail(f"measurement_policy['{key}'] is a numeric threshold")

    def test_build_report_copies_results_defensively(self) -> None:
        source = [synthetic_result("splash")]
        report = cmp.build_report(source)
        report["results"][0]["seed"] = "mutated"
        self.assertEqual(source[0]["seed"], "splash")

    def test_module_declares_no_threshold_constants(self) -> None:
        for name in dir(cmp):
            lowered = name.lower()
            self.assertNotIn("threshold", lowered)
            self.assertNotIn("pixel_perfect", lowered)


if __name__ == "__main__":  # pragma: no cover
    unittest.main()

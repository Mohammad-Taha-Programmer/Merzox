# Merzox XD Reference Exporter — iteration I2-R2 (`MERZOX-UI-GOLDEN-I2-R2`)

> **I2-R2 changes at a glance**
> - A **calibrated `soft-light` hoist**: when it can be proven safe, the blend is
>   applied to the nearest ancestor opacity group instead of the blended node.
>   On the Splash artboard this moved MAE from **5.149241 → 0.457513** (RMS
>   5.762370 → 1.155373; background MAE 5.124378 → 0.441563).
> - All original nested opacities are **preserved exactly** — nothing is
>   multiplied, flattened or removed.
> - Soft-light that cannot be proven safe, and every other non-neutral blend
>   mode, stays **reported as unsupported and emits no CSS**.
> - New report fields `blend_mode_application_counts` and
>   `blend_mode_applications`.

> **I2-R1 changes at a glance**
> - Image fills now cover the **painted shape's bounds** instead of tiling the
>   natural bitmap box (the I1 defect). On the Splash artboard this moved the
>   measured error against the authentic XD preview from **MAE 6.32 / RMS 7.05 /
>   `err<=10` 0.846** to roughly **MAE 5.15 / RMS 5.76 / `err<=10` 0.996**.
> - `scaleBehavior` is classified, mapped and **reported**; unknown spellings are
>   never silently guessed.
> - Non-neutral blend modes (e.g. `soft-light`) are now **reported as explicit
>   fidelity blockers** instead of being ignored — and are still not faked with
>   CSS, because measurement showed that made the error worse.
> - **No translation and no global colour correction** are applied. A small
>   translation search over the Splash artboard proved the optimum is `dx=0,
>   dy=0`, so none is introduced.

A deterministic, standard-library-only tool that reads an Adobe XD `.xd` package
directly as a ZIP archive and exports **one** artboard through the pipeline:

```
AGC  ->  self-contained SVG  ->  PNG (installed Edge/Chrome, headless)
```

## What this is — and what it is not

This is an **engineering reference exporter**. It is not Adobe XD, it does not
embed Adobe's rendering engine, and it makes **no pixel-perfect claim**.

Its purpose is to give the Merzox UI-golden work a *reproducible, inspectable*
rendering of the original design so that Flutter output can be compared against
something better than a screenshot taken by hand. Where the exporter cannot
reproduce an XD feature exactly, it **reports the gap in the JSON report**
instead of silently approximating it.

This iteration deliberately targets a **single artboard**, not the full
112-artboard set. The immediate calibration target is:

```
سبلاش – 1     (canonical manifest size expected: 375 x 812)
```

## Requirements

- Python 3.9+ — **standard library only**. No `pip install`, no third-party
  packages. Pillow may be used in ad-hoc diagnostics if it already happens to be
  installed, but nothing in the AGC → SVG path depends on it.
- Microsoft Edge **or** Google Chrome installed locally (only for the PNG step;
  `--skip-png` produces the SVG and report without a browser).
- `assets/fonts/Tajawal-Regular.ttf` in the repository (used for font embedding).

Nothing is ever downloaded. No font is fetched, no browser is installed.

## CLI

Exact documented invocation:

```bash
python tools/xd_reference/xd_reference_exporter.py \
  --xd <path-to-xd> \
  --artboard-name "<exact manifest artboard name>" \
  --output-svg <path> \
  --output-png <path> \
  --report-json <path>
```

Real example (raw calibration mode — write outputs **outside** the repository):

```bash
python tools/xd_reference/xd_reference_exporter.py \
  --xd "C:/design/design.xd" \
  --artboard-name "سبلاش – 1" \
  --output-svg "C:/temp/merzox-xd/splash-1.raw.svg" \
  --output-png "C:/temp/merzox-xd/splash-1.raw.png" \
  --report-json "C:/temp/merzox-xd/splash-1.raw.report.json"
```

Normalized (future app-parity) mode:

```bash
python tools/xd_reference/xd_reference_exporter.py \
  --xd "C:/design/design.xd" \
  --artboard-name "سبلاش – 1" \
  --output-svg "C:/temp/merzox-xd/splash-1.merzox.svg" \
  --output-png "C:/temp/merzox-xd/splash-1.merzox.png" \
  --report-json "C:/temp/merzox-xd/splash-1.merzox.report.json" \
  --normalize-merzox-brand
```

Additional flags:

| Flag | Purpose |
| --- | --- |
| `--normalize-merzox-brand` | Replace the literal rendered text `Bictov` with `Merzox`. |
| `--list-artboards` | Print every canonical manifest artboard name, path and size. |
| `--skip-png` | Produce SVG + report without launching a browser. |
| `--font <path>` | Override the embedded Tajawal TTF. |
| `--browser <path>` | Force a specific Edge/Chrome executable. |

The `MERZOX_XD_BROWSER` environment variable is also honoured as a browser
override.

### Raw vs normalized Merzox mode

| Mode | Behaviour | Used for |
| --- | --- | --- |
| **Raw** (default) | XD text is preserved exactly. `Bictov` stays `Bictov`. | Calibrating the renderer against the original XD preview — the reference and the design must agree character-for-character. |
| **Normalized** (`--normalize-merzox-brand`) | The literal string `Bictov` in *rendered text content* becomes `Merzox`. | Comparing against the shipped Merzox app. |

Normalization rules:

- The `.xd` source package is **never modified**.
- Only text that is actually rendered is normalized. JSON payloads, node IDs,
  node names, resource UIDs and generated SVG IDs are left untouched — so a
  layer named `Bictov Logo` still appears as `data-xd-name="Bictov Logo"`.
- The number of replacements is reported as `brand_replacement_count`.

## SVG output

- `width` / `height` = canonical artboard width/height from the manifest.
- `viewBox` = artboard bounds. The origin is taken from the AGC `artboards`
  entry, because that is the coordinate space the child transforms are actually
  expressed in — this avoids subtracting a document offset twice when XD stores
  global coordinates. The chosen origin and its source are reported as
  `viewbox` and `viewbox_origin_source`, and a warning is emitted if the AGC
  origin and the manifest origin disagree.
- Content is clipped to the artboard rectangle via a generated `clipPath`.
- The file is self-contained: fonts and images are embedded as data URIs, so it
  renders identically from any directory.
- Generated IDs are deterministic (`mxg-clip-1`, `mxg-pattern-1`,
  `mxg-filter-1`, `mxg-gradient-1`, …), so two runs over the same input produce
  byte-identical SVG.

### Supported node and style features

| Feature | Support |
| --- | --- |
| Matrix transforms (`a b c d tx ty`) | `transform="matrix(...)"`; identity transforms omitted |
| Groups | `<g>` |
| `rect`, `circle`, `ellipse`, `line`, `path` | Direct SVG equivalents |
| Solid fills | `fill` + `fill-opacity` |
| Solid strokes | width, cap, join, miter limit, dash, dash offset |
| Opacity | Applied to the node's group wrapper |
| Pattern / image fills | See below |
| Gradients | `linearGradient` / `radialGradient` with stops, resolved through AGC `resources.gradients` |
| Drop shadows | `feDropShadow` (dx, dy, radius, colour, alpha) |
| `uxdesign#blur` | `feGaussianBlur` (visible foreground blur only) |
| `clipPath` | Emitted into `<defs>`; clip geometry never painted |
| Text | Per-segment placement from `rawText` + paragraph/line coordinates |
| `syncRef` | Resolved against the artboard AGC and `resources/graphics/graphicContent.agc` |

### Pattern / image fills

Visible image fills are reached through `style.fill` where
`style.fill.type == "pattern"`. The actual pattern payload may be nested:

```jsonc
// either
style.fill = { "type": "pattern", "pattern": { /* actual payload */ } }
// or, wrapped
style.fill = { "type": "pattern",
               "pattern": { "type": "pattern",
                            "pattern": { /* actual payload */ } } }
```

`normalize_pattern_payload()` descends through any number of these wrappers and
returns the innermost object. The image blob is then resolved as:

```
uid = pattern.meta.ux.uid
blob = resources/<uid>          # inside the .xd ZIP
```

The `uid` is **never** read from the outer `{"type": "pattern", "pattern": ...}`
wrapper — only from the normalized inner payload.

#### Image-fill cover semantics (repaired in I2-R1)

Adobe XD `ImageFill` **cover** semantics preserve the bitmap's aspect ratio,
scale it until the shape is completely covered, and crop the overflow. The
closest SVG equivalent is `preserveAspectRatio="xMidYMid slice"`.

I1 used `pattern.width` / `pattern.height` — the *natural bitmap* dimensions —
as the pattern tile size. That is wrong: a 1600×1600 bitmap on an 813×812 shape
produced a 1600×1600 tile in bitmap coordinate space instead of one image
scaled to cover the shape. I2-R1 lays image fills out against the **painted
shape's local bounds** instead.

Local paint bounds are derived from declared XD values:

| Shape | Bounds |
| --- | --- |
| `rect` | `x`, `y`, `width`, `height` |
| `circle` | `cx-r`, `cy-r`, `2r`, `2r` |
| `ellipse` | `cx-rx`, `cy-ry`, `2rx`, `2ry` |
| `polygon` (bbox fallback) | declared `width` / `height` |

For a cover fill on a shape with reliable bounds:

```xml
<pattern patternUnits="userSpaceOnUse"
         x="<bounds.x + offsetX>" y="<bounds.y + offsetY>"
         width="<bounds.width>" height="<bounds.height>">
  <image x="0" y="0"
         width="<bounds.width>" height="<bounds.height>"
         preserveAspectRatio="xMidYMid slice" href="data:…"/>
</pattern>
```

The shape keeps `fill="url(#…)"`, so the tile covers the shape exactly once
rather than tiling a bitmap-sized coordinate space.

> **Note on the `<image>` origin.** SVG places `<pattern>` content in a
> coordinate system whose origin is the *tile* origin, so the image sits at the
> tile-local `(0, 0)` while the tile itself is positioned at the shape bounds.
> Writing the bounds origin onto both elements would apply it twice. For the
> measured Splash node the bounds origin is `(0, 0)`, so both forms are
> identical there; this form is also correct for shapes that do not start at the
> origin (circles, ellipses, offset rects).

Artboard/document transforms are **not** subtracted a second time here — the
bounds used are the shape's own local values, exactly as they already appear in
the emitted geometry.

#### Scale-behavior mapping

| XD `meta.ux.scaleBehavior` | Mode | SVG |
| --- | --- | --- |
| `fill`, `cover`, `SCALE_COVER` (case-insensitive, `_`/`-` ignored) | cover | `preserveAspectRatio="xMidYMid slice"` |
| `stretch`, `SCALE_STRETCH` | stretch | `preserveAspectRatio="none"` |
| *absent* | cover (Adobe's default) | `xMidYMid slice`, reported as `unspecified` |
| anything else | **reported as unknown** | cover fallback, recorded in `unsupported_node_counts` as `fill:pattern:scaleBehavior:<value>` plus a warning |

`scaleBehavior: "fill"` is deliberately **not** implemented as distortion. The
one Splash experiment that made distortion look marginally better is not
evidence: that bitmap is 1600×1600 on an 813×812 shape, so the aspect-ratio
difference is negligible and the comparison cannot distinguish the two.

Every image fill is counted in `pattern_scale_behavior_counts` (keyed by the raw
XD spelling) and described in full under `pattern_fills`.

#### Other pattern details

- `pattern.meta.ux.offsetX` / `offsetY` are still applied to the pattern origin,
  on top of the shape bounds (`patternUnits="userSpaceOnUse"`).
- Natural bitmap dimensions remain available for diagnostics as
  `pattern_fills[].natural_width` / `natural_height` — but they never become the
  cover tile size.
- Geometry with no reliable local bounds (a `path`, for example) keeps the
  pre-repair natural-bitmap fallback rather than inventing a path
  bounding-box parser. That case is recorded as
  `fill:pattern:no-shape-bounds` with a warning saying cover semantics were
  **not** applied to that shape.

### Filter mapping (deterministic approximations)

| XD | SVG | Mapping |
| --- | --- | --- |
| `uxdesign#blur` `params.blurAmount` | `feGaussianBlur/@stdDeviation` | `stdDeviation = blurAmount * 0.5` |
| `dropShadow` `r` | `feDropShadow/@stdDeviation` | `stdDeviation = r * 0.5` |

Both constants are exported as `BLUR_AMOUNT_TO_STD_DEVIATION` and
`SHADOW_RADIUS_TO_STD_DEVIATION`, and echoed into every report under
`approximation_mapping`. They are linear approximations of XD's blur kernel —
**not** an exact reproduction.

Blur rules:

- `filter.visible == false` → the filter is **not** applied (counted as
  `hidden_blur_count`).
- `params.backgroundEffect == true` (backdrop blur) has no reliable standalone
  SVG equivalent. It is **reported as unsupported**
  (`unsupported_background_blur_count`) rather than approximated with a
  foreground blur that would look wrong.

### Blend modes

Any node carrying a non-neutral `blendMode` (checked on `style.blendMode`, then
the node itself, then `meta.ux.blendMode`) is counted in `blend_mode_counts` and
gets an entry in `blend_mode_applications` describing what was done with it.
`normal`, `source-over` and a missing `blendMode` are neutral and are **not**
reported at all.

Exactly one blend mode — `soft-light` — has been calibrated against the
authentic XD preview, and only under the structure described below. Everything
else is counted in `unsupported_node_counts` as `style:blendMode:<value>` with a
warning, and emits no CSS.

#### The I2-D3 calibration evidence

D3 measured several CSS placements of the Splash `soft-light` node against the
authentic Adobe XD preview:

| Placement | Full MAE |
| --- | --- |
| R1 baseline (no CSS blending at all) | 5.149241 |
| `mix-blend-mode: soft-light` on the `Image 4` wrapper | 5.395551 |
| `mix-blend-mode: soft-light` on the painted shape | 5.575304 |
| opacity flattened to 0.06 + blend on the shape | 0.514871 |
| **`soft-light` on `Repeat Grid 60`, opacities preserved** | **0.457513** |

The winning configuration keeps `Repeat Grid 60` at opacity `0.5` and `Image 4`
at opacity `0.12` and puts the blend on the *group*: full RMS 1.155373,
background MAE 0.441563, background RMS 0.733318.

Note that opacity flattening scored a close 0.514871 — and is still **not**
implemented, because it destroys source information to chase a worse number.

#### The safe soft-light hoist rule

For a visible node whose XD `blendMode` is `soft-light`, the exporter runs a
pre-pass (`BlendHoistPlanner`) over the artboard tree — necessary because the
hoist target is an *ancestor*, which the renderer emits before it reaches the
blended node.

1. Find the nearest ancestor **group** with an explicitly declared opacity
   strictly between 0 and 1. No such ancestor → refuse.
2. Prove the hoist cannot disturb unrelated content with a **single
   content-chain test**: every container from that opacity group down to the
   blended node must have exactly one visible *painting* child, and it must be
   the next link on the chain. Invisible nodes and non-painting metadata
   (`clipPath` definitions, groups whose whole subtree paints nothing) are
   ignored when counting branches. Any second painted branch → refuse.
3. If two soft-light sources would resolve to the same target group, **both**
   are refused: one CSS declaration cannot express two blend passes.
4. `syncRef` subtrees and unrecognised node types are treated as opaque painting
   leaves, so an ambiguous branch blocks hoisting rather than silently
   permitting it.

When the proof succeeds, the exporter adds `style="mix-blend-mode:soft-light"`
to the selected opacity group's existing `<g>` wrapper — and changes nothing
else. **All node and group opacities are preserved exactly as XD declared
them**: none are multiplied together, flattened, or dropped. No transform and
no geometry is moved. The blended source node's own wrapper and its painted
shape carry **no** `mix-blend-mode`.

For the real Splash tree the source is `Image 4` (opacity `0.12`) and the target
is `Repeat Grid 60` (opacity `0.5`):

```xml
<g data-xd-name="Repeat Grid 60" opacity="0.5" style="mix-blend-mode:soft-light">
  <g data-xd-name="Image 4" opacity="0.12">
    <rect x="0" y="0" width="813" height="812" fill="url(#mxg-pattern-1)"/>
  </g>
</g>
```

When the proof fails, nothing is emitted, `style:blendMode:soft-light` stays in
`unsupported_node_counts`, and the warning names the specific reason
(`no-opacity-group-ancestor`, `ancestor-chain-not-single-content-branch`,
`multiple-soft-light-sources-target-group`, …).

#### What this is not

This is a **calibrated approximation for one measured structure**, not a proof
that CSS blend semantics equal Adobe XD's. CSS composites against a different
backdrop stack, and the two agree here because the Splash tree happens to isolate
the blended content in a single-branch opacity group. The rule is deliberately
narrow: it is not generalised to `multiply` or any other mode, and it is not
applied wherever a soft-light happens to appear.

Likewise, **no global colour correction and no translation are applied.** A
small translation search on the Splash artboard found the optimum at `dx=0,
dy=0`, so introducing either would be fitting noise rather than fixing a defect.

### Compound (boolean) shapes

If XD has already flattened the boolean result into `shape.path`, that path is
used and the result is exact.

If it has not, the boolean operation is **not** faked. The exporter:

1. records `shape:compound:<operation>` in `unsupported_node_counts`,
2. emits a warning stating the boolean result is not accurate,
3. preserves the child geometry inside a
   `<g data-xd-unsupported-compound="<operation>">` so nothing is lost.

### clipPath

Clip definitions are emitted into `<defs>` with deterministic generated IDs and
referenced via `clip-path="url(#…)"`. Clip children are written as **geometry
only** — their fills and strokes are dropped, and they are never painted as
ordinary visible content. An unresolvable clip reference is counted, warned
about, and the node renders unclipped rather than disappearing.

### Text

- Segment text comes from `rawText[from:to]`, placed at the segment's own `x`/`y`.
- Font size, weight (from the XD style name), colour and node transforms are
  preserved. `paragraphAlign` maps to `text-anchor`.
- **Arabic strings are emitted verbatim.** No manual reversal or reshaping is
  performed — bidi ordering and shaping are left to the browser's text engine,
  which is the only correct place for them.

## Fonts

`assets/fonts/Tajawal-Regular.ttf` is embedded into the SVG as a base64 data URI
with `@font-face` aliases for every Tajawal name XD may reference:

`Tajawal`, `Tajawal-Regular`, `Tajawal-Medium`, `Tajawal-Bold`, `Tajawal-Light`
(plus family-level `Tajawal` at weights 300/400/500/700).

### Known limitation: synthetic Tajawal weights

**Only the regular weight is available.** All aliases point at the same regular
outlines, and the browser synthesises Light/Medium/Bold by faux-weighting them.
Real Tajawal Medium and Bold have different glyph outlines, so:

- text metrics (advance widths, line breaks) will differ slightly from XD,
- stroke weight will not match a genuine bold cut,
- **do not treat text as pixel-accurate in the current iteration.**

This limitation is surfaced in every report as
`synthetic_tajawal_weight_limitation: true` plus an entry in `limitations`.

### Non-Tajawal fonts

For any other family the exporter:

- requests the family by name so the browser uses it **if it is already
  installed**,
- records it under `fonts_requested` and `non_embedded_fonts`,
- emits a warning that rendering depends on locally installed fonts,
- **downloads and bundles nothing.**

## Browser PNG rendering

Discovery order (Edge first, then Chrome), across `ProgramFiles`,
`ProgramFiles(x86)` and `LOCALAPPDATA`, then `PATH`, with `MERZOX_XD_BROWSER`
and `--browser` as overrides.

Invocation:

```
--headless=new
--disable-gpu
--hide-scrollbars
--no-first-run
--disable-extensions
--force-device-scale-factor=1
--user-data-dir=<temporary isolated profile>
--window-size=<artboard width>,<artboard height>
--screenshot=<output-png>
file:///<absolute path to the SVG>
```

`--force-device-scale-factor=1` is added beyond the baseline flag set so the
screenshot is 1 CSS pixel = 1 image pixel regardless of the host display's DPI
scaling. The temporary profile directory is always removed afterwards.

The exporter fails loudly — never silently — if the browser cannot be found, the
browser exits non-zero, it times out, or no PNG file is produced.

## JSON report

Written with `--report-json`. Always includes at least:

`source_xd`, `selected_artboard_name`, `selected_artboard_path`,
`selected_artboard_id`, `artboard_bounds`, `svg_width`, `svg_height`, `viewbox`,
`viewbox_origin_source`, `output_svg`, `output_png`, `browser_path`,
`browser_return_code`, `node_type_counts`, `handled_node_counts`,
`unsupported_node_counts`, `resolved_sync_refs`, `unresolved_sync_refs`,
`pattern_fill_count`, `resolved_pattern_fill_count`,
`unresolved_pattern_fill_count`, `pattern_scale_behavior_counts`,
`pattern_fills`, `blend_mode_counts`, `gradient_fill_count`, `resource_ids_used`,
`text_node_count`, `invisible_node_count`, `fonts_requested`, `embedded_fonts`,
`non_embedded_fonts`, `synthetic_tajawal_weight_limitation`,
`visible_drop_shadow_count`, `visible_blur_count`, `hidden_blur_count`,
`unsupported_background_blur_count`, `clip_path_count`,
`brand_normalization_enabled`, `brand_replacement_count`,
`approximation_mapping`, `limitations`, `warnings`.

The report is the contract: if a feature was approximated or skipped, it appears
there. An empty `unsupported_node_counts` is the only claim of completeness this
tool will make.

Every report is stamped with `iteration` (currently `MERZOX-UI-GOLDEN-I2-R2`,
from the `EXPORTER_ITERATION` constant) and `schema`. The two are independent:
`schema` is the serialization version and only moves when the field set changes,
so a new calibration iteration does not bump it.

## Calibration workflow (against the XD preview)

1. List the artboards and confirm the exact canonical name and size:

   ```bash
   python tools/xd_reference/xd_reference_exporter.py --xd "C:/design/design.xd" --list-artboards
   ```

   Confirm `سبلاش – 1` reports `375x812`.

2. Export in **raw** mode to a scratch directory outside the repository:

   ```bash
   python tools/xd_reference/xd_reference_exporter.py \
     --xd "C:/design/design.xd" \
     --artboard-name "سبلاش – 1" \
     --output-svg "C:/temp/merzox-xd/splash-1.raw.svg" \
     --output-png "C:/temp/merzox-xd/splash-1.raw.png" \
     --report-json "C:/temp/merzox-xd/splash-1.raw.report.json"
   ```

3. Read the report **before** looking at the image. Check
   `unsupported_node_counts`, `unresolved_sync_refs`,
   `unresolved_pattern_fill_count`, `unsupported_background_blur_count` and
   `warnings`. Those entries explain, up front, every place the render is known
   to be wrong.

4. Compare `splash-1.raw.png` side by side with Adobe XD's own preview of the
   same artboard. Raw mode exists precisely so that this comparison is
   apples-to-apples — `Bictov` must still read `Bictov`.

5. Attribute each visual difference to a specific cause: a reported unsupported
   feature, the synthetic font weight, the blur/shadow mapping constants, or a
   genuine renderer bug. Fix renderer bugs; adjust the documented mapping
   constants only with a stated reason.

6. Re-export and repeat until the remaining differences are all explained by
   documented limitations.

7. Only then run the normalized mode and use it for Flutter parity work.

## Committing artefacts — not yet

**Do not commit generated reference images (SVG or PNG) until renderer
calibration has been formally accepted.**

Committing a golden image implies the renderer is trusted. It is not yet. A
premature golden would bake today's approximations — synthetic font weights,
the blur mapping constant, any unreported geometry bug — into the baseline every
future comparison is measured against.

Write every generated artefact to a scratch directory **outside** the
repository (for example `C:/temp/merzox-xd/`). Only this exporter's source,
tests and documentation belong in git while calibration is still in progress.

## Tests

Hermetic `unittest` suite. It generates minimal `.xd` ZIP fixtures in temporary
directories and never requires the real `design.xd`, a browser, or Pillow.

```bash
python -m unittest discover -s tools/xd_reference/tests -p 'test_*.py' -v
```

New in I2-R1:

- `pattern_scale_behavior_counts` — e.g. `{"fill": 1}`, keyed by the raw XD
  spelling (or `unspecified`).
- `pattern_fills` — one entry per resolved image fill: `uid`, `scale_behavior`,
  `mode`, `natural_width`/`natural_height`, `offset_x`/`offset_y`,
  `bounds_source` (`shape-bounds` / `natural-bitmap-fallback` / `unavailable`),
  `target_bounds` and `preserve_aspect_ratio`.
- `blend_mode_counts` — non-neutral blend modes encountered.

New in I2-R2:

- `blend_mode_application_counts` — `{"<mode>:<strategy>": n}`. The Splash
  artboard yields `{"soft-light:safe-opacity-group": 1}`; a refused hoist yields
  `{"soft-light:unsupported": 1}`.
- `blend_mode_applications` — one entry per non-neutral blend mode, with
  `blend_mode`, `strategy`, `safe_hoist`, `reason`, `source_node_name`,
  `target_group_name`, `source_opacity` and `target_opacity`.

A safely hoisted `soft-light` is deliberately **absent** from
`unsupported_node_counts` — it is no longer a gap. Every refused one is still
counted there.

All existing report fields are unchanged and remain backwards compatible.

## Current limitations (summary)

1. **No pixel-perfect claim.** This is a reference renderer, not Adobe XD. The
   Splash artboard now measures MAE 0.457513 against the authentic preview after
   the I2-R1 image-fill repair and the I2-R2 soft-light hoist — but that is
   **one calibrated artboard out of 112**. Nothing here claims fidelity for the
   rest of the design; every other artboard is uncalibrated until measured.
2. **Synthetic Tajawal weights** — only the regular cut is embedded; Light,
   Medium and Bold are browser-synthesised.
3. **Non-Tajawal fonts are not embedded** — they render only if installed
   locally.
4. **Blur and shadow radii use linear approximation constants** (`* 0.5`), not
   XD's actual kernel.
5. **Background (backdrop) blur is unsupported** and reported, never faked.
6. **Compound booleans without a pre-flattened path are not evaluated** — child
   geometry is preserved and the limitation is reported.
7. **Non-uniform corner radii collapse to a single uniform radius**, reported.
8. **Stroke alignment `inside`/`outside` has no SVG equivalent** — strokes are
   centred, reported.
9. **Blend modes remain the leading fidelity blocker.** Only `soft-light` is
   calibrated, and only when the safe-hoist proof succeeds. Every other mode —
   and every unprovable soft-light — is detected and reported
   (`style:blendMode:<value>`) but not rendered. Masks beyond `clipPath` and
   text-on-path are also not implemented.
10. **Image fills on geometry without reliable bounds** (paths) fall back to the
    natural-bitmap tile and do not get cover semantics; this is reported as
    `fill:pattern:no-shape-bounds`.
11. **No global colour correction and no translation offsets** are applied, by
    design — measurement showed neither is warranted.
12. **Single artboard only.** The 112-artboard batch renderer is a later
    iteration.
13. **PNG output depends on a locally installed Edge/Chrome**, and on the fonts
    that browser can see.

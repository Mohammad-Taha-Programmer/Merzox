# Merzox XD Reference Exporter — iteration I3-R2-D7-I1 (`MERZOX-UI-GOLDEN-I3-R2-D7-I1`)

> **I3-R2-D7-I1 changes at a glance**
> - Image fills still use **reliable stored geometry bounds** whenever the shape
>   has them; that path is byte-for-byte unchanged.
> - When a `path` has **no** reliable stored bounds, the exporter can now derive
>   its **exact local bounds** — but only for an explicitly supported, closed,
>   absolute `M`/`L`/`C`/`Z` subset, via `strict_absolute_mlc_z_bounds()`.
> - Cubic extrema are **solved analytically** (derivative roots in `0 < t < 1`),
>   never sampled and never approximated by the control-point box.
> - Anything outside that subset stays **fail-closed** and keeps the existing
>   documented natural-bitmap fallback plus `fill:pattern:no-shape-bounds`.
> - In the current `design.xd` this repairs exactly **six** occurrences across
>   **three** artboards, counted as
>   `handled_node_counts["fill:pattern:path-bounds-derived"]`.
> - Background blur remains honestly unsupported.

> **I3-R2-I4 changes at a glance**
> - **Non-uniform rounded rectangles are now rendered exactly**, as deterministic
>   closed SVG paths, instead of being approximated by a single uniform `rx`/`ry`.
>   That covers **315** rectangles across **70** artboards.
> - The compact AGC four-value `shape.r` corner order is **proven**:
>   `r[0] = top-left`, `r[1] = top-right`, `r[2] = bottom-right`,
>   `r[3] = bottom-left`.
> - Radii that overflow a side are reduced by a **deterministic proportional
>   overlap policy**: one common factor, applied to all four corners. Corners are
>   never clamped independently.
> - Inside-stroke composition is unchanged and simply consumes the new geometry:
>   fill, stroke copy and interior clip all use the *same* path.
> - `rect:non-uniform-corner-radius` moves from `unsupported_node_counts` to
>   `handled_node_counts`.

> **I3-R2-I3 changes at a glance**
> - **Inside-stroke alignment is now emulated** for provably closed shapes: the
>   fill renders once, then a stroke-only copy of the same geometry at double
>   width, clipped to that geometry's interior. That covers **482 / 482**
>   occurrences in the current corpus, across 111 artboards.
> - Only `stroke-width` is doubled — dash array, dash offset, caps, joins,
>   miter limit and stroke opacity are passed through untouched.
> - Geometry that cannot be proven closed keeps the honest centred-stroke
>   fallback and stays reported as unsupported.

> **I3-R2-I1 changes at a glance**
> - `syncRef` resolution now uses **`syncSourceGuid`** — the shared source
>   definition — instead of the instance `guid`. That single conflation caused
>   **all 432** unresolved-syncRef occurrences across **108** of the 112
>   artboards.
> - The instance's own transform is still the placement wrapper; the resolved
>   source renders underneath it with its own transform and style.
> - Recursion protection is keyed on the source guid actually used for lookup.
> - Nodes without `syncSourceGuid` keep the legacy fallback unchanged.

> **I3-I1 changes at a glance**
> - **Stable identity selectors**: `--artboard-id` (canonical manifest id) and
>   `--artboard-path` join `--artboard-name`. Exactly one may be used.
> - **All-artboard batch export** via `--all-artboards --output-dir <dir>`,
>   iterating every manifest entry in order — so the 7 artboards whose human
>   names collide are no longer unreachable.
> - Deterministic per-artboard output stems
>   (`017--سبلاش-1--1ff58a48`) and a `batch-report.json` summary.
> - Batch output directories **fail closed** when non-empty.
> - No rendering, compositing, opacity, image-fill or blend behaviour changed.
>
> **I3-I1-R1 acceptance repairs**
> - Batch entry status vocabulary is now exactly `success` / `failed`.
> - CLI output is forced to UTF-8, so Arabic artboard names survive in
>   diagnostics instead of being dropped by the host ANSI code page.

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

## Artboard identity

The real `design.xd` declares **112 artboards** but only **105 distinct human
names**. Three names are shared:

| Name | Artboards |
| --- | --- |
| `اعدادات المتجر` | 2 |
| `الرسائل` | 4 |
| `معاينة` | 4 |

That is 7 artboards in excess of the distinct-name count — and they are exactly
the ones a name-only workflow silently loses. Every artboard does, however, have
a **unique, non-null, UUID-like manifest id** and a **unique artwork path** of
the form `artwork/artboard-<uuid>`.

Note that an artboard's manifest id and the uuid in its artwork path are
*different values*. For the calibrated Splash artboard:

```
name        : سبلاش – 1
manifest id : 1ff58a48-0e8d-49eb-be2f-4b7a24adcf9c
path        : artwork/artboard-29c52d7e-0f4c-439b-87cc-5d4a5cd8f229
```

Three selectors are available, and **exactly one** may be used:

| Selector | Stability | Notes |
| --- | --- | --- |
| `--artboard-id` | **Canonical.** Unique per artboard. | Prefer this for scripts and automation. |
| `--artboard-path` | Stable secondary. | The canonical `artwork/artboard-<uuid>` directory. A single trailing `/` is normalised; nothing else is guessed, and passing a `graphicContent.agc` file path is rejected with a pointer to the directory. |
| `--artboard-name` | Convenient, **may be ambiguous**. | Fails closed: a name matching several artboards raises rather than picking one, and the error lists each match's manifest id so you can retry with `--artboard-id`. Unchanged from earlier iterations. |

CLI output is written as UTF-8 regardless of the host ANSI code page, so Arabic
artboard names survive intact in diagnostics and in `--list-artboards` even when
the console's default encoding could not represent them.

Supplying zero selectors, or more than one, is an error in both the CLI and the
Python API. Whichever selector is used, the report always carries all three
identity fields: `selected_artboard_name`, `selected_artboard_id` and
`selected_artboard_path`.

List everything with identity exposed (deterministic manifest order,
tab-separated `name`, `manifest_id`, `path`, `WxH`):

```bash
python tools/xd_reference/xd_reference_exporter.py --xd "C:/design/design.xd" --list-artboards
```

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

By manifest id — the recommended form, and the only one that works for a
duplicated name:

```bash
python tools/xd_reference/xd_reference_exporter.py \
  --xd "C:/design/design.xd" \
  --artboard-id 1ff58a48-0e8d-49eb-be2f-4b7a24adcf9c \
  --output-svg "C:/temp/merzox-xd/splash-1.svg"
```

By canonical artwork path:

```bash
python tools/xd_reference/xd_reference_exporter.py \
  --xd "C:/design/design.xd" \
  --artboard-path artwork/artboard-29c52d7e-0f4c-439b-87cc-5d4a5cd8f229 \
  --output-svg "C:/temp/merzox-xd/splash-1.svg"
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
| `--list-artboards` | Print name, manifest id, path and bounds for every artboard, in manifest order. |
| `--all-artboards` | Export every artboard into `--output-dir`. |
| `--output-dir <dir>` | Batch destination. Required by (and only valid with) `--all-artboards`. |
| `--skip-png` | Produce SVG + report without launching a browser. |
| `--font <path>` | Override the embedded Tajawal TTF. |
| `--browser <path>` | Force a specific Edge/Chrome executable. |

The `MERZOX_XD_BROWSER` environment variable is also honoured as a browser
override.

## All-artboard batch export

```bash
python tools/xd_reference/xd_reference_exporter.py \
  --xd "C:/design/design.xd" \
  --all-artboards \
  --output-dir "C:/temp/merzox-xd/corpus-raw"
```

Batch mode walks **every** `XdPackage.artboards()` entry in manifest order and
never deduplicates by name, so the real package produces exactly **112** exports,
including all four `الرسائل` and all four `معاينة`. Each artboard is selected by
its unique artwork path, so a duplicated name can never shadow another entry.

### Deterministic output naming

Each artboard gets the stem:

```
{manifest-order-index:03d}--{unicode-slug}--{first-8-of-manifest-id}
```

for example `017--سبلاش-1--1ff58a48`. The slug preserves Arabic (and any other
Unicode) letters and digits verbatim, collapses punctuation and whitespace to
single hyphens, trims leading/trailing hyphens, and falls back to `artboard` if
nothing slug-able remains. The id fragment is lowercased. The 1-based manifest
index alone already guarantees uniqueness; the slug and id fragment make a
filename identifiable when names collide.

Per artboard, inside `--output-dir` only:

```
<stem>.svg
<stem>.report.json
<stem>.png          # unless --skip-png
```

### Output-directory safety

Batch generation fails closed rather than mixing a new corpus with old files:

- the directory does not exist → it is created (including parents);
- it exists and is empty → it is used;
- it exists and contains anything → **error**, before a single file is written.

Nothing is ever deleted or overwritten. Point at a fresh directory, or clear the
old one yourself.

### `batch-report.json`

One deterministic summary is written into the output directory under the
independent schema `merzox.xd_reference_batch/1` (deliberately *not* the
single-artboard `merzox.xd_reference_exporter/1`, and not tied to the exporter
iteration). It contains `schema`, `iteration`, `source_xd`, `output_dir`,
`normalize_merzox_brand`, `skip_png`, `artboard_count`, `success_count`,
`failure_count` and an ordered `entries` list.

Each entry carries `index`, `name`, `manifest_id`, `artboard_path`,
`output_stem`, `output_svg`, `output_png`, `report_json`, `status`, `error`,
plus rollups from the per-artboard report: `artboard_bounds`, `svg_width`,
`svg_height`, `unsupported_node_counts`, `warning_count`, `pattern_fill_count`,
`resolved_pattern_fill_count`, `brand_replacement_count` and
`blend_mode_application_counts`.

Artifact paths in the summary are **relative filenames** inside the output
directory, never machine-specific absolute paths, so the summary is reproducible
across machines.

### Entry `status` vocabulary

`status` has exactly two values — there is no alias and no third state:

| Value | Meaning |
| --- | --- |
| `success` | Artifact generation succeeded: the SVG, the per-artboard report, and (unless `--skip-png`) the PNG were written. |
| `failed` | Artifact generation failed. `error` carries a concise description. |

`status` describes **artifact generation only — never rendering fidelity.** A
`success` entry may still contain unsupported renderer features; those are
described separately and honestly by that entry's `unsupported_node_counts` (and
by `warning_count`, with the detail in the per-artboard report). Unsupported
features are a documented limitation of this exporter, not an export failure, so
they never flip an entry to `failed` or increment `failure_count`.

A `success` entry therefore does **not** mean the artboard is pixel-perfect, and
a fully green batch does not mean the design renders correctly — see the
calibration caveat in the limitations below.

### Failure semantics

One artboard failing does not abort the run: the entry is recorded with
`status: "failed"` and a concise `error` string, and the remaining artboards are
still attempted. `failure_count` reflects reality and the CLI process exits
**non-zero** — a batch never claims complete corpus success when any artboard
failed.

`unsupported_node_counts` is *not* a failure. Those are renderer limitations
reported honestly per artboard; an export with unsupported features still counts
as a successful export.

### Batch flags

`--normalize-merzox-brand` and `--skip-png` apply uniformly to every entry.
Under `--skip-png` no PNG is produced and each entry's `output_png` is `null`.

Batch mode writes deterministic filenames and therefore rejects
`--output-svg`, `--output-png` and `--report-json`, as well as any single
artboard selector — those combinations are errors rather than guesses.

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
| Uniform rectangle corner radius | `rx` / `ry` on the `<rect>` |
| Non-uniform rectangle corner radii | Exact closed `<path>` — see below |
| Solid fills | `fill` + `fill-opacity` |
| Solid strokes | width, cap, join, miter limit, dash, dash offset |
| Opacity | Applied to the node's group wrapper |
| Pattern / image fills | See below |
| Gradients | `linearGradient` / `radialGradient` with stops, resolved through AGC `resources.gradients` |
| Drop shadows | `feDropShadow` (dx, dy, radius, colour, alpha) |
| `uxdesign#blur` | `feGaussianBlur` (visible foreground blur only) |
| `clipPath` | Emitted into `<defs>`; clip geometry never painted |
| Text | Per-segment placement from `rawText` + paragraph/line coordinates |
| `syncRef` | Resolved by `syncSourceGuid` against the artboard AGC and `resources/graphics/graphicContent.agc` — see below |

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
- Geometry with no reliable local bounds keeps the pre-repair natural-bitmap
  fallback, recorded as `fill:pattern:no-shape-bounds` with a warning saying
  cover semantics were **not** applied to that shape — **except** for the
  strictly supported closed absolute path subset described next.

#### Derived path bounds (I3-R2-D7-I1)

A `path` carries no stored width/height, so before this iteration *every* image
fill on a path fell back to the natural bitmap box. The exporter now derives the
path's exact local bounds — but only when it can do so with certainty.

`strict_absolute_mlc_z_bounds(path_data)` returns
`Optional[Tuple[float, float, float, float]]` — `(x, y, width, height)` — and is
deliberately **fail-closed**: anything it does not explicitly support returns
`None` and the caller keeps the documented fallback. It is **not** a general SVG
path-bounds implementation and no such support is claimed. The exporter runtime
stays standard-library-only.

Supported — and nothing else:

| Command | Arguments | Notes |
| --- | --- | --- |
| `M` | exactly 2 | Absolute moveto; must open every subpath |
| `L` | exactly 2 | Absolute lineto |
| `C` | exactly 6 | Absolute cubic Bézier |
| `Z` | exactly 0 | Closepath |

Rejected, every time:

- lowercase/relative commands (`m`, `l`, `c`, `z`);
- `H`, `V`, `S`, `Q`, `T`, `A`;
- **implicit command repetition** — `M 0 0 10 10` is refused, because the second
  pair is an unstated continuation rather than an explicit command;
- missing or excess arguments, malformed numbers, non-finite values
  (`1e400`, `NaN`, `Infinity`);
- geometry before a valid `M`, or any subpath left open;
- an empty path, or bounds with non-positive width or height;
- **stray characters.** The whole input string is validated by an index-driven
  tokenizer, not by a loose `re.findall()` that would silently skip what it does
  not recognise. Only whitespace and commas are accepted between tokens.

Cubic bounds are **exact**. For each segment `P0 → P1 → P2 → P3` and each
coordinate independently, the derivative
`a t² + b t + c` (with `a = -P0 + 3P1 - 3P2 + P3`, `b = 2(P0 - 2P1 + P2)`,
`c = P1 - P0`) is solved analytically; the curve is evaluated at `t = 0`, at
`t = 1`, and at every root strictly inside `0 < t < 1`. Segment extrema are then
unioned. The control-point box is never used as a bound and the curve is never
sampled. Line segments use their endpoints; `Z` adds the closing line back to the
subpath start, whose endpoints are already included.

Priority inside `AgcRenderer._image_fill_layout(...)`, highest first:

1. **reliable stored bounds** (`rect`, `circle`, `ellipse`, and the generated
   non-uniform rounded rectangle) — unchanged, and still preferred;
2. a `path` whose `d` parses under the strict subset with positive width and
   height → tile origin `(derived_x + offsetX, derived_y + offsetY)`, tile size
   `(derived_width, derived_height)`, `preserveAspectRatio` from the existing
   stretch/cover constants, and `bounds_source: "derived-path-bounds"`;
3. otherwise the pre-existing fallbacks, verbatim — natural-bitmap when natural
   dimensions exist, then the no-size fallback.

Offsets move the **tile origin only**; they never change the derived width or
height.

Each successful derivation increments
`handled_node_counts["fill:pattern:path-bounds-derived"]` exactly once. The
`fill:pattern:no-shape-bounds` key and its logic are unchanged and still
required — they remain the honest report for every path outside the subset.

##### Coverage measured on the real package

The current `design.xd` contains **six** such image fills, in **three**
artboards (`تفاصيل المتجر – 7`, `تفاصيل المتجر – 13` and `معاينة`, two each).
All six are independent AGC nodes that happen to share one identical local path:
a **closed 33 × 33 circle** built from four cubic segments, whose exact solved
bounds are `x = 0`, `y = 0`, `width = 33`, `height = 33`. All six are `cover`
fills of a 200 × 200 bitmap with zero offsets.

The repair was **pre-validated across all 112 artboards** as a read-only
simulation before being persisted: it derived the 33 × 33 bounds exactly six
times, took `fill:pattern:no-shape-bounds` from 6 to 0, exported 112/112
successfully with 112 valid correctly-sized PNGs and 112 distinct PNG hashes, and
left `syncRef` (216 resolved / 0 unresolved), `stroke-align:inside` (482),
`rect:non-uniform-corner-radius` (315), `rect:corner-radius-overlap-scaled` (6)
and `fill:pattern` (289) all identical.

After it, the only unsupported renderer feature remaining in the corpus is
`filter:uxdesign#blur:background = 2` — background blur, which stays honestly
unsupported and is never faked.

`REPORT_SCHEMA` is unchanged (`merzox.xd_reference_exporter/1`): the field set
did not change, only the value of an existing `handled_node_counts` key and of
`pattern_fills[].bounds_source`.

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

#### Background (backdrop) blur — final feasibility decision (I3-R2-D8-D3)

Background blur was investigated in full and the outcome is a **deliberate
decision not to implement it**. This subsection records that decision and the
evidence behind it; it does not change any code, report field or constant.

**Proven — the corpus evidence.** The current `design.xd` contains exactly
**two** visible `uxdesign#blur` effects with `backgroundEffect = true`, in the
artboards `الرئيسية` and `الرئيسية – 1`. The two cases are structurally
identical:

| Aspect | Value |
| --- | --- |
| Node | `type = shape`, `shape.type = rect`, `98 × 35` |
| Corner radii | `[5, 5, 5, 5]` |
| Transform | identity plus `tx = 81`, `ty = 178` |
| Filter | `uxdesign#blur`, `global = true`, `backgroundEffect = true` |
| Filter params | `blurAmount = 14`, `brightnessAmount = 15`, `fillOpacity = 0` |

The stacking context is the same in both: an underlying `293 × 110` image
rectangle, then an additional `293 × 110` overlay at approximately 10% opacity,
then the `98 × 35` background-blur rectangle, then foreground text
(`اشتري الآن`). `fillOpacity = 0` and that ordering together establish these as
genuine **backdrop** blur nodes, not ordinary foreground object blur.

**Proven — browser mechanism feasibility.** A controlled local Microsoft Edge
test was run against the same headless rendering path this exporter uses. It
used a candidate mapping (`blurAmount 14 → backdrop-filter: blur(14px)`,
`brightnessAmount 15 → brightness(115%)`) **purely to exercise browser
mechanics**; those numbers are explicitly *not* calibrated to Adobe XD.

| Mechanism | Result |
| --- | --- |
| CSS feature detection | reports `backdrop-filter` support |
| `backdrop-filter` directly on an SVG `<rect>` | computed style contained `blur(14px) brightness(1.15)`, but pixel comparison showed **zero changed pixels** inside the target region — **not a proven usable mechanism** in this Edge SVG/HTML rendering path |
| `backdrop-filter` on an HTML element inside an SVG `<foreignObject>` | produced a **real** backdrop effect: pixels changed only inside the backdrop region, an unrelated outside region was unchanged, and foreground content painted afterwards was unaltered |

So the technical mechanism **SVG `foreignObject` + HTML `backdrop-filter`** is
feasible in the current Edge runtime, while applying `backdrop-filter` directly
to an SVG graphics element is not.

**Not proven — numeric parity with Adobe XD.** There is no established
calibration showing that XD `blurAmount = 14` is CSS `blur(14px)`, nor that XD
`brightnessAmount = 15` is CSS `brightness(115%)`. The local Adobe XD/UXP oracle
is unavailable, and there is no authentic target-artboard screenshot or
reference for these two exact occurrences. Exact XD visual parity for the two
nodes is therefore **unproven**.

**Decision.** Background blur is **not implemented in this renderer iteration**.
The two occurrences stay honestly unsupported as
`filter:uxdesign#blur:background = 2`, and **no approximation is emitted**.
Shipping a `foreignObject` path driven by a guessed numeric conversion would be
a visual approximation dressed as parity; the existing fail-closed behaviour —
report `backgroundEffect = true` as unsupported rather than silently apply a
guessed effect — is the accepted final outcome for this iteration.

Nothing here claims pixel-perfect XD parity for those two nodes, that Adobe
`blurAmount` equals CSS pixels, that Adobe `brightnessAmount` maps directly to a
CSS percentage, or that `backdrop-filter` works directly on SVG graphics
elements in the current Edge rendering path.

### Non-uniform rectangle corner radii

A compact AGC rectangle carries its corner radii as a four-value `shape.r` list.
The physical order was determined independently against the corpus and is
**proven**: the list runs clockwise from the top-left corner.

| Index | Corner |
| --- | --- |
| `r[0]` | top-left |
| `r[1]` | top-right |
| `r[2]` | bottom-right |
| `r[3]` | bottom-left |

SVG's `<rect>` has only a single `rx`/`ry` pair, so before I3-R2-I4 a rectangle
whose four radii were not all equal was approximated with `r[0]` and reported as
`rect:non-uniform-corner-radius` in `unsupported_node_counts`. It is now emitted
as an exact, deterministic, **closed** path instead:

```xml
<path d="M 5,6 L 35,6 A 10,10 0 0 1 45,16 L 45,26 A 10,10 0 0 1 35,36
         L 5,36 L 5,6 Z" fill="#123456"/>
```

The path runs TL → TR → BR → BL in that proven order: a quarter-circle arc
(`A r,r 0 0 1 …`, clockwise, short arc) for every non-zero corner, and a plain
straight endpoint for every zero corner. Coordinates, transforms, artboard
coordinate semantics and fractional values are untouched — only the element
changes. The result is an ordinary geometry, so fill, stroke, opacity, filters,
blend, transforms and outer clips compose through the existing pipeline with no
special-casing.

Rectangles whose radii are **all equal** — including a uniform four-value list —
still render as a plain `<rect>` with `rx`/`ry`, and a rectangle with no radius
is completely unchanged.

#### Deterministic overlap policy

Two radii sharing a side may together demand more than that side's length. The
exporter resolves this with one **common** scale factor, taken from the most
violated side:

```
factor = min(1, w/(tl+tr), h/(tr+br), w/(bl+br), h/(tl+bl))
```

If `factor < 1`, **all four** radii are multiplied by it. Corners are never
clamped independently, so the shape's corner proportions are preserved. This is
the same rule CSS `border-radius` and Canvas `roundRect` specify.

In the current corpus there are exactly **six** scaling occurrences — six
independent nodes in the artboard `السلة – 1`, reducing to **two mirrored
19 × 19 geometry classes**:

| Class | Occurrences | Size | Raw `r` | Violating side | Effective `r` |
| --- | --- | --- | --- | --- | --- |
| A | 3 | 19 × 19 | `[0, 10, 10, 0]` | right | `[0, 9.5, 9.5, 0]` |
| B | 3 | 19 × 19 | `[10, 0, 0, 10]` | left | `[9.5, 0, 0, 9.5]` |

Both scale by `factor = 0.95` (`19 / 20`), i.e. `10 → 9.5`. Browser Canvas
`roundRect` validation returned exact pixel equality against manually
constructed 9.5-radius paths for both mirrored cases.

> **Not an Adobe parity claim.** Adobe documents that effective corner radii
> *may* be reduced, but its generic internal Scenegraph capping algorithm is
> undocumented and no local Adobe XD oracle is available. The rule above is
> **this renderer's deterministic overlap policy**, standards-backed and
> validated for the current target corpus. Nothing here claims that it matches
> Adobe's internal capping for inputs outside that corpus.

#### Reporting

| Key | Bucket | Meaning |
| --- | --- | --- |
| `rect:non-uniform-corner-radius` | `handled_node_counts` | Rendered exactly as a path |
| `rect:corner-radius-overlap-scaled` | `handled_node_counts` | Also needed `factor < 1` |

`rect:non-uniform-corner-radius` no longer appears in `unsupported_node_counts`
for valid four-value geometry; a scaled shape additionally records the overlap
policy in the report's `limitations` list. A malformed `r` list that is
non-uniform but does **not** have exactly four values keeps the previous
documented `rx`/`ry` approximation and stays reported as unsupported.

### Inside-stroke alignment

Adobe XD can align a stroke to the **inside** of a shape's path. SVG has no
native equivalent — its strokes are always centred on the path, so a naive
render puts half the stroke outside the shape and makes every bordered element
slightly too large.

For a **solid** stroke with `align: "inside"` on **provably closed** geometry,
the exporter emulates XD's behaviour:

1. the shape's fill renders once, at the original geometry;
2. a stroke-only copy of the *same* geometry renders at
   `2 x` the XD stroke width;
3. that doubled centred stroke is clipped to the same geometry's interior via a
   dedicated `<clipPath clipPathUnits="userSpaceOnUse">`.

Only the inward half survives the clip, which is exactly the width XD asked for.

```xml
<clipPath id="mxg-inside-stroke-1" clipPathUnits="userSpaceOnUse">
  <rect x="0" y="0" width="100" height="100"/>
</clipPath>
...
<rect x="0" y="0" width="100" height="100" fill="#123456"/>
<rect x="0" y="0" width="100" height="100" fill="none" stroke="#000000"
      stroke-width="1" clip-path="url(#mxg-inside-stroke-1)"
      data-xd-stroke-align="inside"/>
```

Both copies sit inside the node's **single existing wrapper**, so the node
transform, opacity, filter, blend mode and any outer clip still apply exactly
once to the composite. Nothing is numerically flattened.

#### Eligibility

Closure must be provable from the emitted geometry:

| Geometry | Eligible |
| --- | --- |
| `rect`, `circle`, `ellipse`, `polygon` | Yes — closed by definition |
| `path` ending in an explicit closepath (`Z`/`z`) | Yes — including the non-uniform rounded-rectangle path |
| `path` not ending in a closepath | **No** |
| `line`, anything else | **No** |

Ineligible geometry keeps the previous behaviour: a centred stroke, plus
`stroke-align:inside` counted in `unsupported_node_counts` with a warning saying
the geometry is not provably closed. That fallback exists even though the
current corpus has no ineligible case.

#### Coverage measured on the real package (I3-R2-D4)

All **482** inside-stroke occurrences across **111** artboards are eligible and
emulated:

| Geometry | Count |
| --- | --- |
| `rect` | 340 |
| `circle` | 101 |
| closed `path` | 41 |

Stroke widths present: `0.3` (11), `0.5` (262), `1` (143), `1.5` (66). Origin:
374 artboard-direct, 108 via shared `syncRef` sources — both routes use the same
mechanism. Four cases are dashed and three use round caps; those properties pass
through unchanged.

#### Paint semantics

The fill copy carries no stroke; the stroke copy carries `fill="none"`. A shape
with no visible fill still uses its geometry as the clip region. For a
non-uniform rounded rectangle this is the *same* generated path in all three
places — interior clip, filled copy and stroked copy — so the emulation needed
no change beyond consuming the new geometry, and the width doubling is
unaffected. Stroke colour,
stroke opacity, line cap, line join, miter limit, dash array and dash offset are
all preserved verbatim — **only `stroke-width` is doubled**. Dash lengths and
offsets are explicitly *not* scaled.

A successfully emulated inside stroke is counted in
`handled_node_counts["stroke-align:inside"]` and is no longer reported as
unsupported. `stroke-align:outside` remains unsupported and unchanged.

Clip IDs come from the existing deterministic `SvgDocument` counter
(`mxg-inside-stroke-1`, `-2`, …) — one dedicated clipPath per handled shape, for
auditability. No UUIDs, timestamps, random values or path-derived hashes are
used, so re-exporting the same artboard produces byte-identical SVG.

### `syncRef` resolution — `guid` vs `syncSourceGuid`

An XD `syncRef` node carries **two different identities**, and conflating them
was the defect repaired in I3-R2-I1:

| Field | Meaning |
| --- | --- |
| `guid` | Identity of **this instance** of the reference. Unique per occurrence. |
| `syncSourceGuid` | Identity of the **shared source definition** in the AGC symbol index. Shared by every instance of that definition. |

Only `syncSourceGuid` can index the shared definition. The pre-repair resolver
scanned `ref` / `guid` / `symbolId` / `componentId` and so passed the *instance*
guid to the symbol index, which by construction never contains it — every lookup
missed.

Measured on the real package (I3-R2-D2), across the accepted 112-artboard
corpus:

- **432** unresolved `syncRef` occurrences, spanning **108** of the 112 artboards;
- all 432 are real `type="syncRef"` nodes with **432 unique instance guids**;
- every one carries a `syncSourceGuid`;
- those 432 instances reference just **52 unique source GUIDs**;
- **52/52** of those definitions exist in `resources/graphics/graphicContent.agc`,
  as identity-bearing leaf shape/text nodes (`Border`, `Cap`, `Capacity`,
  `↳ Time`, …).

Resolution order:

1. If `syncSourceGuid` is present (checked on the nested `syncRef` payload, the
   node itself, then `meta.ux`), it is the source selector. The instance `guid`
   is never used for lookup in this case.
2. Otherwise the legacy `ref` / `guid` / `symbolId` / `componentId` scan applies
   unchanged, so older and synthetic fixtures keep working.

The resolved node is rendered **exactly as indexed** — the exporter does not
inline a whole parent symbol when the source guid identifies a single child —
underneath the instance's own placement wrapper, which keeps the syncRef's
`transform` (or its payload transform). The source keeps whatever transform and
style it already carries. Nothing is flattened or pre-composed.

Recursion protection is keyed on **the identity actually used for lookup**, so a
definition that references itself is caught even though each instance guid along
the chain is distinct. A recursive or missing source stays fail-closed: only the
referenced content is skipped, `unresolved_sync_refs` increments,
`syncRef:unresolved` is counted, and the warning names the instance guid, the
attempted source guid, the selector used, and whether the cause was recursion or
a missing definition.

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

Every report is stamped with `iteration` (currently
`MERZOX-UI-GOLDEN-I3-R2-D7-I1`, from the `EXPORTER_ITERATION` constant) and
`schema`. The two are independent:
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

## Current corpus coverage (accepted state)

Measured over the full 112-artboard corpus after the accepted repairs:

| Metric | Count |
| --- | --- |
| Artboards | 112 |
| `syncRef` handled | 216 |
| `syncRef` unresolved | 0 |
| Inside-aligned strokes handled | 482 |
| Non-uniform rounded rectangles handled | 315 |
| Proportional corner-overlap scaling handled | 6 |
| Image pattern fills handled | 289 |
| Derived path bounds for pattern fills | 6 |
| `fill:pattern:no-shape-bounds` unsupported | 0 |
| `filter:uxdesign#blur:background` unsupported | **2** |

Background blur is the **only** remaining known unsupported renderer feature in
this corpus — see the D8 feasibility decision above. Coverage counts are not
fidelity claims: an artboard with no unsupported features is still uncalibrated
unless it has been measured against the authentic XD preview.

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
5. **Background (backdrop) blur is unsupported** and reported, never faked —
   the two occurrences in the corpus stay
   `filter:uxdesign#blur:background = 2`. This is a *decision*, not an
   oversight: an `foreignObject` + `backdrop-filter` mechanism was proven to
   work in the Edge runtime, but the XD `blurAmount`/`brightnessAmount` → CSS
   conversion is uncalibrated and no XD oracle or authentic reference exists for
   those nodes, so emitting it would be a guessed approximation rather than
   parity. See the D8 feasibility decision above.
6. **Compound booleans without a pre-flattened path are not evaluated** — child
   geometry is preserved and the limitation is reported.
7. **Non-uniform corner radii are rendered exactly** as deterministic closed
   paths in the proven `TL, TR, BR, BL` order. Overlapping radii are reduced by
   this renderer's own proportional-overlap policy (one common factor for all
   four corners), validated for the six occurrences in the current corpus
   (`10 → 9.5`, factor `0.95`). **Parity with Adobe's undocumented internal
   Scenegraph capping algorithm is not claimed** outside that validated corpus.
   A non-uniform `r` list that does not have exactly four values still collapses
   to a single uniform radius and is still reported.
8. **Stroke alignment has no native SVG equivalent.** `inside` is *emulated*
   on provably closed geometry (doubled stroke clipped to the interior) — an
   approximation of XD's rasteriser, not a proof of equality, and not a claim of
   pixel parity for the 111 affected artboards. `outside`, and `inside` on
   geometry that is not provably closed, are still rendered centred and reported
   as unsupported.
9. **Blend modes remain the leading fidelity blocker.** Only `soft-light` is
   calibrated, and only when the safe-hoist proof succeeds. Every other mode —
   and every unprovable soft-light — is detected and reported
   (`style:blendMode:<value>`) but not rendered. Masks beyond `clipPath` and
   text-on-path are also not implemented.
10. **Image fills on geometry without reliable bounds.** A `path` whose `d` is
    inside the explicitly supported **closed absolute `M`/`L`/`C`/`Z`** subset
    now gets exact local bounds solved analytically
    (`fill:pattern:path-bounds-derived`, six occurrences in the current corpus).
    **This is not general SVG-path bounds support**: relative commands, `H`,
    `V`, `S`, `Q`, `T`, `A`, implicit command repetition, open paths, stray
    characters and degenerate bounds are all refused, and every refused case
    still falls back to the natural-bitmap tile without cover semantics,
    reported as `fill:pattern:no-shape-bounds`.
11. **No global colour correction and no translation offsets** are applied, by
    design — measurement showed neither is warranted.
12. **Batch export is not calibration.** `--all-artboards` can now render all
    112 artboards, but a successful batch says only that the exporter produced
    output for each one. **Only the Splash artboard has been measured against
    the authentic Adobe XD preview.** The other 111 are uncalibrated: read each
    `unsupported_node_counts` and `warnings` before trusting any of them, and do
    not treat a green batch as evidence that the design renders correctly.
13. **Resolving `syncSourceGuid` is not a fidelity claim.** Content that was
    previously dropped now renders, which is strictly more faithful than an
    empty region — but no artboard other than Splash has been measured against
    the authentic XD preview, so none of the 108 affected artboards is claimed
    pixel-perfect. Re-export and re-read the reports rather than assuming.
13. **PNG output depends on a locally installed Edge/Chrome**, and on the fonts
    that browser can see.

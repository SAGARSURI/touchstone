# Phase 0: node kinds and their decision

Every render object type the Phase 0 fixtures painted, across all base and
mutated captures. "Opaque" counts nodes whose paint could not be recorded by
value; those nodes carry a pixel hash of their region instead. A node's
region is every pixel its own paint can change: what it drew, widened for
stroke and blur, inside the clip in effect, grown to the whole clip under an
image filter and to any backdrop filter it overlaps.

Data: [report.json](report.json), Flutter 3.47.6, Linux x64, Skia software
renderer, 2026-10-07.

| Node kind | Nodes seen | Opaque | Decision | Opaque reasons |
| --- | ---: | ---: | --- | --- |
| `PlatformViewRenderBox` | 9 | 9 | Pixel hash | platformView |
| `RenderAbsorbPointer` | 68 | 0 | Recorded paint |  |
| `RenderAnimatedOpacity` | 290 | 0 | Recorded paint |  |
| `RenderAnnotatedRegion<SystemUiOverlayStyle>` | 4 | 0 | Recorded paint |  |
| `RenderBackdropFilter` | 14 | 0 | Recorded paint |  |
| `RenderBlockSemantics` | 68 | 0 | Recorded paint |  |
| `RenderClipOval` | 1 | 1 | Pixel hash (clips with an oval path) | path |
| `RenderClipPath` | 9 | 9 | Pixel hash (clips with a path) | path |
| `RenderClipRRect` | 10 | 0 | Recorded paint |  |
| `RenderClipRect` | 39 | 0 | Recorded paint |  |
| `RenderConstrainedBox` | 835 | 0 | Recorded paint |  |
| `RenderCustomMultiChildLayoutBox` | 72 | 0 | Recorded paint |  |
| `RenderCustomPaint` | 66 | 22 | Recorded paint; pixel hash per node when the painter draws a path, a gradient, a fragment shader or `TextPainter` text | fragmentShader, path, unknownShader, unknownTextSource |
| `RenderCustomSingleChildLayoutBox` | 4 | 0 | Recorded paint |  |
| `RenderDecoratedBox` | 109 | 72 | Recorded paint; pixel hash per node when the decoration paints a path (a border on some sides only, a non-rectangular shape) or a gradient that cannot be read back | path |
| `RenderEditable` | 9 | 0 | Recorded paint |  |
| `RenderExcludeSemantics` | 82 | 0 | Recorded paint |  |
| `RenderFittedBox` | 9 | 0 | Recorded paint |  |
| `RenderFlex` | 29 | 0 | Recorded paint |  |
| `RenderFollowerLayer` | 9 | 0 | Recorded paint |  |
| `RenderFractionalTranslation` | 272 | 0 | Recorded paint |  |
| `RenderIgnorePointer` | 243 | 0 | Recorded paint |  |
| `RenderImage` | 6 | 0 | Recorded paint |  |
| `RenderIndexedSemantics` | 259 | 0 | Recorded paint |  |
| `RenderLeaderLayer` | 18 | 0 | Recorded paint |  |
| `RenderLimitedBox` | 121 | 0 | Recorded paint |  |
| `RenderMouseRegion` | 118 | 0 | Recorded paint |  |
| `RenderOffstage` | 68 | 0 | Recorded paint |  |
| `RenderOpacity` | 19 | 0 | Recorded paint |  |
| `RenderPadding` | 280 | 0 | Recorded paint |  |
| `RenderParagraph` | 269 | 0 | Recorded paint |  |
| `RenderPhysicalModel` | 84 | 0 | Recorded paint |  |
| `RenderPhysicalShape` | 29 | 29 | Pixel hash (draws its shape as a path) | path |
| `RenderPointerListener` | 245 | 0 | Recorded paint |  |
| `RenderPositionedBox` | 183 | 0 | Recorded paint |  |
| `RenderRepaintBoundary` | 467 | 0 | Recorded paint |  |
| `RenderRotatedBox` | 9 | 0 | Recorded paint |  |
| `RenderSemanticsAnnotations` | 893 | 0 | Recorded paint |  |
| `RenderSemanticsGestureHandler` | 105 | 0 | Recorded paint |  |
| `RenderShaderMask` | 11 | 11 | Pixel hash, over its mask rect | unknownShader |
| `RenderSliverList` | 21 | 0 | Recorded paint |  |
| `RenderSliverPadding` | 17 | 0 | Recorded paint |  |
| `RenderStack` | 106 | 0 | Recorded paint |  |
| `RenderTapRegion` | 18 | 0 | Recorded paint |  |
| `RenderTapRegionSurface` | 68 | 0 | Recorded paint |  |
| `RenderTransform` | 120 | 0 | Recorded paint |  |
| `RenderViewport` | 21 | 0 | Recorded paint |  |
| `RenderWrap` | 11 | 0 | Recorded paint |  |
| `TextureBox` | 3 | 3 | Pixel hash | texture |
| `_ColorFilterRenderObject` | 11 | 0 | Recorded paint |  |
| `_ImageFilterRenderObject` | 11 | 0 | Recorded paint |  |
| `_RenderAppBarTitleBox` | 4 | 0 | Recorded paint |  |
| `_RenderColoredBox` | 309 | 0 | Recorded paint |  |
| `_RenderCompositionCallback` | 9 | 0 | Recorded paint |  |
| `_RenderDecoration` | 9 | 0 | Recorded paint |  |
| `_RenderEditableCustomPaint` | 18 | 0 | Recorded paint |  |
| `_RenderInkFeatures` | 104 | 0 | Recorded paint |  |
| `_RenderInputPadding` | 8 | 0 | Recorded paint |  |
| `_RenderListTile` | 8 | 0 | Recorded paint |  |
| `_RenderScrollSemantics` | 21 | 0 | Recorded paint |  |
| `_RenderSizeChangedWithCallback` | 9 | 0 | Recorded paint |  |
| `_RenderSliverPinnedPersistentHeaderForWidgets` | 4 | 0 | Recorded paint |  |
| `_RenderTheater` | 68 | 0 | Recorded paint |  |
| `_ReusableRenderView` | 68 | 0 | Recorded paint |  |

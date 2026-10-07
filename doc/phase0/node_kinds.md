# Phase 0: node kinds and their decision

Every render object type the Phase 0 fixtures painted, across all base and
mutated captures. "Opaque" counts nodes whose paint could not be recorded by
value; those nodes carry a pixel hash of their region instead.

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
| `RenderClipOval` | 1 | 0 | Recorded paint |  |
| `RenderClipPath` | 9 | 0 | Recorded paint |  |
| `RenderClipRRect` | 10 | 0 | Recorded paint |  |
| `RenderClipRect` | 39 | 0 | Recorded paint |  |
| `RenderConstrainedBox` | 835 | 0 | Recorded paint |  |
| `RenderCustomMultiChildLayoutBox` | 72 | 0 | Recorded paint |  |
| `RenderCustomPaint` | 66 | 15 | Recorded paint; pixel hash per node when it draws something undescribable | fragmentShader, unknownShader, unknownTextSource |
| `RenderCustomSingleChildLayoutBox` | 4 | 0 | Recorded paint |  |
| `RenderDecoratedBox` | 109 | 0 | Recorded paint |  |
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
| `RenderPhysicalShape` | 29 | 0 | Recorded paint |  |
| `RenderPointerListener` | 245 | 0 | Recorded paint |  |
| `RenderPositionedBox` | 183 | 0 | Recorded paint |  |
| `RenderRepaintBoundary` | 467 | 0 | Recorded paint |  |
| `RenderRotatedBox` | 9 | 0 | Recorded paint |  |
| `RenderSemanticsAnnotations` | 893 | 0 | Recorded paint |  |
| `RenderSemanticsGestureHandler` | 105 | 0 | Recorded paint |  |
| `RenderShaderMask` | 11 | 11 | Pixel hash | unknownShader |
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

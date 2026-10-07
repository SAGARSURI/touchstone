# Phase 0: mutation results

Each row is one edit to a fixture screen, captured against the unedited screen.
"Recording changed" compares root subtree hashes; "target changed" compares the
subtree hash of the edited widget's render object; "pixels" is the pixel oracle
(differing pixels at device pixel ratio 3).

| Screen | Mutation | Kind | Recording changed | Target changed | Pixels changed | Outcome |
| --- | --- | --- | --- | --- | --- | --- |
| text | text content | paint | yes | yes | no | outside oracle |
| text | text length | paint | yes | yes | yes (5626) | agree |
| text | font weight | paint | yes | yes | yes (5168) | agree |
| text | text colour | paint | yes | yes | yes (64890) | agree |
| text | truncation | layout | yes | yes | yes (73516) | agree |
| text | letter spacing | paint | yes | yes | yes (17019) | agree |
| text | decoration | paint | yes | yes | yes (3864) | agree |
| text | span colour | paint | yes | yes | yes (11350) | agree |
| decorated | colour token | paint | yes | yes | yes (177633) | agree |
| decorated | corner radius | paint | yes | yes | yes (858) | agree |
| decorated | border width | paint | yes | yes | yes (7420) | agree |
| decorated | gradient colour | paint | yes | yes | yes (135337) | agree |
| decorated | gradient stop | paint | yes | yes | yes (96294) | agree |
| decorated | shadow blur | paint | no | no | no | agree |
| decorated | shape | paint | yes | yes | yes (3328) | agree |
| effects | opacity | paint | yes | yes | yes (32400) | agree |
| effects | clip radius | paint | yes | yes | yes (619) | agree |
| effects | clip shape | paint | yes | yes | yes (5484) | agree |
| effects | rotation | paint | yes | yes | yes (1287) | agree |
| effects | scale | paint | yes | yes | yes (7530) | agree |
| effects | paint order | paint | yes | yes | yes (8100) | agree |
| effects | colour filter | paint | yes | yes | yes (30594) | agree |
| effects | blur sigma | paint | yes | yes | yes (56185) | agree |
| effects | shader mask | paint | yes | yes | yes (31514) | agree |
| effects | widget removed | structure | yes | yes | yes (32400) | agree |
| images | image pixel | paint | yes | yes | yes (144) | agree |
| images | image fit | paint | yes | yes | yes (39580) | agree |
| images | icon glyph | paint | yes | yes | no | outside oracle |
| images | icon colour | paint | yes | yes | yes (2880) | agree |
| images | icon size | layout | yes | yes | yes (636) | agree |
| lists | row colour | paint | yes | yes | yes (2363868) | agree |
| lists | divider height | layout | yes | no | yes (297752) | agree |
| lists | app bar title | paint | yes | yes | yes (4356) | agree |
| chart | data point | paint | yes | yes | yes (34805) | agree |
| chart | stroke width | paint | yes | yes | yes (5913) | agree |
| chart | gradient fill | paint | yes | yes | yes (133012) | agree |
| chart | painter label | paint | no | no | no | outside oracle |
| chart | curve control point | paint | yes | yes | yes (282) | agree |
| platform_view | header colour | paint | yes | yes | yes (276863) | agree |
| platform_view | header alpha below output precision | paint | yes | yes | no | false alarm |
| themed | dark theme | paint | yes | yes | yes (2955480) | agree |
| themed | theme seed | paint | yes | yes | yes (2944614) | agree |
| themed | switch state | paint | yes | yes | yes (13161) | agree |
| themed | disabled state | paint | yes | yes | yes (125989) | agree |
| themed | padding 1px | layout | yes | yes | yes (15490) | agree |
| themed | selected state | paint | yes | yes | yes (2896) | agree |
| themed | semantics label | semantics | no | no | no | agree |
| overlay | scrim opacity | paint | yes | yes | yes (2188974) | agree |
| overlay | dialog text | paint | yes | yes | yes (20726) | agree |
| overlay | sheet height | layout | yes | yes | yes (7448) | agree |
| kinds | editable text | paint | yes | yes | no | outside oracle |
| kinds | clip path | paint | yes | yes | yes (2030) | agree |
| kinds | physical shape colour | paint | yes | yes | yes (125790) | agree |
| kinds | fitted box | paint | yes | yes | yes (114480) | agree |
| kinds | rotated box | paint | yes | yes | yes (501264) | agree |
| kinds | follower offset | layout | yes | yes | yes (720) | agree |
| kinds | fade opacity | paint | yes | yes | yes (96660) | agree |
| kinds | fragment uniform | paint | yes | yes | yes (128400) | agree |

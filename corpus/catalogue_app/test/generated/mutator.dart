// The seeded mutation generator (spec: Verification strategy, "Generated
// mutations"): one random property, child or ordering change per run, applied
// to a render object of a settled catalogue scene. The pixel and semantics
// oracle supplies the ground truth, and every run replays from its seed.

import 'dart:math';

import 'package:flutter/rendering.dart';

/// A mutation applied to [target]; [description] says what changed.
class AppliedMutation {
  AppliedMutation(this.target, this.description);

  final RenderObject target;
  final String description;
}

typedef _Mutate = String? Function(RenderObject ro, Random random);

Color _shift(Color c, Random random) {
  final int channel = random.nextInt(3) * 8;
  final int argb = c.toARGB32();
  final int v = (argb >> channel) & 0xFF;
  final int nv = v < 0x80 ? v + 1 + random.nextInt(8) : v - 1 - random.nextInt(8);
  return Color((argb & ~(0xFF << channel)) | (nv << channel));
}

/// Changes one character of the first non-empty text in [span].
InlineSpan? _mutateText(InlineSpan span, Random random) {
  if (span is! TextSpan) {
    return null;
  }
  final String? text = span.text;
  if (text != null && text.isNotEmpty) {
    final int i = random.nextInt(text.length);
    final int code = text.codeUnitAt(i);
    final String replacement = String.fromCharCode(code == 0x58 ? 0x59 : 0x58); // X, or Y for an X
    return TextSpan(
      text: text.replaceRange(i, i + 1, replacement),
      style: span.style,
      children: span.children,
      recognizer: span.recognizer,
      semanticsLabel: span.semanticsLabel,
      locale: span.locale,
      spellOut: span.spellOut,
    );
  }
  final List<InlineSpan>? children = span.children;
  if (children == null) {
    return null;
  }
  for (var k = 0; k < children.length; k++) {
    final InlineSpan? m = _mutateText(children[k], random);
    if (m != null) {
      return TextSpan(
        text: span.text,
        style: span.style,
        children: <InlineSpan>[...children]..[k] = m,
        recognizer: span.recognizer,
        semanticsLabel: span.semanticsLabel,
        locale: span.locale,
        spellOut: span.spellOut,
      );
    }
  }
  return null;
}

TextSpan? _restyle(InlineSpan span, TextStyle Function(TextStyle) change) {
  if (span is! TextSpan) {
    return null;
  }
  return TextSpan(
    text: span.text,
    style: change(span.style ?? const TextStyle()),
    children: span.children,
    recognizer: span.recognizer,
    semanticsLabel: span.semanticsLabel,
    locale: span.locale,
    spellOut: span.spellOut,
  );
}

SemanticsProperties _relabel(SemanticsProperties p, String label) => SemanticsProperties(
  enabled: p.enabled,
  checked: p.checked,
  mixed: p.mixed,
  expanded: p.expanded,
  selected: p.selected,
  toggled: p.toggled,
  button: p.button,
  link: p.link,
  header: p.header,
  headingLevel: p.headingLevel,
  textField: p.textField,
  slider: p.slider,
  keyboardKey: p.keyboardKey,
  readOnly: p.readOnly,
  focused: p.focused,
  inMutuallyExclusiveGroup: p.inMutuallyExclusiveGroup,
  hidden: p.hidden,
  obscured: p.obscured,
  multiline: p.multiline,
  scopesRoute: p.scopesRoute,
  namesRoute: p.namesRoute,
  image: p.image,
  liveRegion: p.liveRegion,
  maxValueLength: p.maxValueLength,
  currentValueLength: p.currentValueLength,
  identifier: p.identifier,
  label: label,
  value: p.value,
  increasedValue: p.increasedValue,
  decreasedValue: p.decreasedValue,
  hint: p.hint,
  tooltip: p.tooltip,
  hintOverrides: p.hintOverrides,
  textDirection: p.textDirection,
  sortKey: p.sortKey,
  tagForChildren: p.tagForChildren,
  onTap: p.onTap,
  onLongPress: p.onLongPress,
  onScrollLeft: p.onScrollLeft,
  onScrollRight: p.onScrollRight,
  onScrollUp: p.onScrollUp,
  onScrollDown: p.onScrollDown,
  onIncrease: p.onIncrease,
  onDecrease: p.onDecrease,
  onCopy: p.onCopy,
  onCut: p.onCut,
  onPaste: p.onPaste,
  onDismiss: p.onDismiss,
  customSemanticsActions: p.customSemanticsActions,
  role: p.role,
  controlsNodes: p.controlsNodes,
  inputType: p.inputType,
  validationResult: p.validationResult,
);

/// The mutations available for a render object, by kind.
final Map<String, _Mutate> _kinds = <String, _Mutate>{
  'decoration colour': (RenderObject ro, Random random) {
    if (ro is! RenderDecoratedBox) return null;
    final Decoration d = ro.decoration;
    if (d is! BoxDecoration || d.color == null) return null;
    final Color c = _shift(d.color!, random);
    ro.decoration = d.copyWith(color: c);
    return 'BoxDecoration.color ${d.color} -> $c';
  },
  'decoration radius': (RenderObject ro, Random random) {
    if (ro is! RenderDecoratedBox) return null;
    final Decoration d = ro.decoration;
    if (d is! BoxDecoration || d.borderRadius == null) return null;
    ro.decoration = d.copyWith(borderRadius: d.borderRadius!.add(BorderRadius.circular(1)));
    return 'BoxDecoration.borderRadius +1';
  },
  'text': (RenderObject ro, Random random) {
    if (ro is! RenderParagraph) return null;
    final InlineSpan? m = _mutateText(ro.text, random);
    if (m == null) return null;
    ro.text = m;
    return 'text ${ro.text.toPlainText()}';
  },
  'text colour': (RenderObject ro, Random random) {
    if (ro is! RenderParagraph) return null;
    final TextSpan? m = _restyle(
      ro.text,
      (TextStyle s) => s.copyWith(color: _shift(s.color ?? const Color(0xFF000000), random)),
    );
    if (m == null) return null;
    ro.text = m;
    return 'text colour';
  },
  'font weight': (RenderObject ro, Random random) {
    if (ro is! RenderParagraph) return null;
    final TextSpan? m = _restyle(
      ro.text,
      (TextStyle s) => s.copyWith(fontWeight: s.fontWeight == FontWeight.w900 ? FontWeight.w100 : FontWeight.w900),
    );
    if (m == null) return null;
    ro.text = m;
    return 'font weight';
  },
  'padding 1px': (RenderObject ro, Random random) {
    if (ro is! RenderPadding) return null;
    final EdgeInsets p = ro.padding.resolve(TextDirection.ltr);
    final EdgeInsets add = <EdgeInsets>[
      const EdgeInsets.only(left: 1),
      const EdgeInsets.only(top: 1),
      const EdgeInsets.only(right: 1),
      const EdgeInsets.only(bottom: 1),
    ][random.nextInt(4)];
    ro.padding = p + add;
    return 'padding $p + $add';
  },
  'size 1px': (RenderObject ro, Random random) {
    if (ro is! RenderConstrainedBox) return null;
    final BoxConstraints c = ro.additionalConstraints;
    if (c.hasTightWidth && c.maxWidth.isFinite) {
      ro.additionalConstraints = c.tighten(width: c.maxWidth + 1);
      return 'width ${c.maxWidth} + 1';
    }
    if (c.hasTightHeight && c.maxHeight.isFinite) {
      ro.additionalConstraints = c.tighten(height: c.maxHeight + 1);
      return 'height ${c.maxHeight} + 1';
    }
    return null;
  },
  'reorder children': (RenderObject ro, Random random) {
    if (ro is! ContainerRenderObjectMixin<RenderBox, ContainerBoxParentData<RenderBox>>) return null;
    if (ro.childCount < 2) return null;
    ro.move(ro.lastChild!);
    return 'moved the last of ${ro.childCount} children first';
  },
  'flex alignment': (RenderObject ro, Random random) {
    if (ro is! RenderFlex) return null;
    final List<MainAxisAlignment> values = MainAxisAlignment.values;
    final MainAxisAlignment next = values[(values.indexOf(ro.mainAxisAlignment) + 1) % values.length];
    final MainAxisAlignment before = ro.mainAxisAlignment;
    ro.mainAxisAlignment = next;
    return 'mainAxisAlignment $before -> $next';
  },
  'opacity': (RenderObject ro, Random random) {
    if (ro is! RenderOpacity) return null;
    final double o = ro.opacity;
    ro.opacity = o > 0.5 ? o - 0.1 : o + 0.1;
    return 'opacity $o -> ${ro.opacity}';
  },
  'clip radius': (RenderObject ro, Random random) {
    if (ro is! RenderClipRRect) return null;
    ro.borderRadius = ro.borderRadius.add(BorderRadius.circular(2));
    return 'clip radius +2';
  },
  'shape colour': (RenderObject ro, Random random) {
    if (ro is! RenderPhysicalShape) return null;
    final Color c = ro.color;
    ro.color = _shift(c, random);
    return 'shape colour $c -> ${ro.color}';
  },
  'image': (RenderObject ro, Random random) {
    if (ro is! RenderImage || ro.image == null) return null;
    ro.invertColors = !ro.invertColors;
    return 'image invertColors';
  },
  'transform': (RenderObject ro, Random random) {
    if (ro is! RenderTransform) return null;
    ro.transform = Matrix4.translationValues(1, 0, 0);
    return 'transform -> translate(1, 0)';
  },
  'custom painter removed': (RenderObject ro, Random random) {
    if (ro is! RenderCustomPaint || ro.painter == null) return null;
    ro.painter = null;
    return 'painter removed';
  },
  'semantics label': (RenderObject ro, Random random) {
    if (ro is! RenderSemanticsAnnotations) return null;
    final String? label = ro.properties.label;
    if (label == null || label.isEmpty) return null;
    ro.properties = _relabel(ro.properties, '$label!');
    return 'semantics label "$label" -> "$label!"';
  },
};

/// Every (render object, kind) the generator can mutate in [view].
List<(RenderObject, String)> candidates(RenderView view) {
  final out = <(RenderObject, String)>[];
  final Random probe = Random(0);
  void visit(RenderObject ro) {
    if (ro.attached && !ro.debugNeedsLayout) {
      for (final MapEntry<String, _Mutate> k in _kinds.entries) {
        if (_applicable(ro, k.key, probe)) {
          out.add((ro, k.key));
        }
      }
    }
    ro.visitChildren(visit);
  }

  visit(view);
  return out;
}

bool _applicable(RenderObject ro, String kind, Random random) => switch (kind) {
  'decoration colour' =>
    ro is RenderDecoratedBox && ro.decoration is BoxDecoration && (ro.decoration as BoxDecoration).color != null,
  'decoration radius' =>
    ro is RenderDecoratedBox && ro.decoration is BoxDecoration && (ro.decoration as BoxDecoration).borderRadius != null,
  'text' || 'text colour' || 'font weight' => ro is RenderParagraph && ro.text is TextSpan,
  'padding 1px' => ro is RenderPadding,
  'size 1px' =>
    ro is RenderConstrainedBox &&
        ((ro.additionalConstraints.hasTightWidth && ro.additionalConstraints.maxWidth.isFinite) ||
            (ro.additionalConstraints.hasTightHeight && ro.additionalConstraints.maxHeight.isFinite)),
  'reorder children' =>
    ro is ContainerRenderObjectMixin<RenderBox, ContainerBoxParentData<RenderBox>> && ro.childCount >= 2,
  'flex alignment' => ro is RenderFlex,
  'opacity' => ro is RenderOpacity,
  'clip radius' => ro is RenderClipRRect,
  'shape colour' => ro is RenderPhysicalShape,
  'image' => ro is RenderImage && ro.image != null,
  'transform' => ro is RenderTransform,
  'custom painter removed' => ro is RenderCustomPaint && ro.painter != null,
  'semantics label' => ro is RenderSemanticsAnnotations && (ro.properties.label ?? '').isNotEmpty,
  _ => false,
};

/// Picks and applies one mutation to [view] from [random].
AppliedMutation? mutate(RenderView view, Random random) {
  final List<(RenderObject, String)> all = candidates(view);
  if (all.isEmpty) {
    return null;
  }
  final (RenderObject ro, String kind) = all[random.nextInt(all.length)];
  final String? description = _kinds[kind]!(ro, random);
  return description == null ? null : AppliedMutation(ro, '$kind: $description');
}

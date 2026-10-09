// Component selection (spec: Capture steps, "Select components"; A6).
//
// A component is a widget whose class is declared in one of the app's own
// packages, or that the test includes explicitly. Flutter keeps no record of
// which library declares a class at run time, so the app's source is scanned
// for class declarations. Where a widget was created is not the same thing: a
// framework `Text` created in app code is not a component.

import 'dart:io';

import 'package:flutter/widgets.dart';

/// Decides which widgets are components.
class ComponentPolicy {
  /// [packageRoots] are directories of the app's own packages; by default the
  /// package under test (the working directory of `flutter test`). [include]
  /// adds widget types from other packages.
  ComponentPolicy({List<String>? packageRoots, this.include = const <Type>{}})
    : _declared = _scan(packageRoots ?? <String>[Directory.current.path]);

  final Set<Type> include;

  /// Class name to the library that declares it, `package:name/path.dart`.
  final Map<String, String> _declared;

  /// Classes declared under the package roots, for reporting.
  Map<String, String> get declaredClasses => Map<String, String>.unmodifiable(_declared);

  bool isComponent(Widget widget) => include.contains(widget.runtimeType) || _declared.containsKey(_name(widget));

  /// Explanation field `type`: the class and the package it comes from.
  String typeOf(Widget widget) {
    final String name = _name(widget);
    final String? library = _declared[name];
    return library == null ? widget.runtimeType.toString() : '${widget.runtimeType} ($library)';
  }

  static String _name(Widget widget) {
    final String t = widget.runtimeType.toString();
    final int lt = t.indexOf('<');
    return lt < 0 ? t : t.substring(0, lt);
  }

  /// A class declaration with a supertype: a widget class always has one, so
  /// a plain class that shares a framework widget's name is not taken.
  static final RegExp _classDecl = RegExp(
    r'^\s*(?:(?:abstract|base|final|sealed|interface|mixin)\s+)*class\s+([A-Za-z_$][\w$]*)'
    r'(?:\s*<[^{]*?>)?\s+(?:extends|with|implements)\b',
    multiLine: true,
  );

  /// [source] with comments and string literals blanked, so a class
  /// declaration quoted in a string or comment is not read as one. Line breaks
  /// are kept.
  static String _code(String source) {
    final out = StringBuffer();
    var i = 0;
    while (i < source.length) {
      final int end = _skipNonCode(source, i);
      if (end == i) {
        out.write(source[i]);
        i++;
        continue;
      }
      for (final int unit in source.substring(i, end).codeUnits) {
        out.writeCharCode(unit == 0x0A ? 0x0A : 0x20);
      }
      i = end;
    }
    return out.toString();
  }

  /// The index after the comment or string literal starting at [i], or [i].
  static int _skipNonCode(String s, int i) {
    if (s.startsWith('//', i)) {
      final int end = s.indexOf('\n', i);
      return end < 0 ? s.length : end;
    }
    if (s.startsWith('/*', i)) {
      var depth = 0;
      var j = i;
      while (j < s.length) {
        if (s.startsWith('/*', j)) {
          depth++;
          j += 2;
        } else if (s.startsWith('*/', j)) {
          j += 2;
          if (--depth == 0) {
            return j;
          }
        } else {
          j++;
        }
      }
      return j;
    }
    final bool raw =
        s[i] == 'r' &&
        i + 1 < s.length &&
        (s[i + 1] == "'" || s[i + 1] == '"') &&
        (i == 0 || !RegExp(r'[\w$]').hasMatch(s[i - 1]));
    final int q = raw ? i + 1 : i;
    if (s[q] != "'" && s[q] != '"') {
      return i;
    }
    final String quote = s.startsWith(s[q] * 3, q) ? s[q] * 3 : s[q];
    var j = q + quote.length;
    while (j < s.length && !s.startsWith(quote, j)) {
      if (!raw && s[j] == r'\') {
        j += 2;
      } else if (!raw && s.startsWith(r'${', j)) {
        j = _skipBraces(s, j + 2);
      } else {
        j++;
      }
    }
    return j + quote.length > s.length ? s.length : j + quote.length;
  }

  /// The index after the `}` that closes a block whose body starts at [i].
  static int _skipBraces(String s, int i) {
    var depth = 1;
    var j = i;
    while (j < s.length) {
      final int k = _skipNonCode(s, j);
      if (k != j) {
        j = k;
        continue;
      }
      if (s[j] == '{') {
        depth++;
      } else if (s[j] == '}' && --depth == 0) {
        return j + 1;
      }
      j++;
    }
    return j;
  }

  static final RegExp _pubspecName = RegExp(r'^name:\s*([\w]+)', multiLine: true);

  static final Map<String, Map<String, String>> _cache = <String, Map<String, String>>{};

  static Map<String, String> _scan(List<String> roots) {
    final declared = <String, String>{};
    for (final root in roots) {
      final Map<String, String> found = _cache.putIfAbsent(root, () {
        final out = <String, String>{};
        final pubspec = File('$root/pubspec.yaml');
        final String package = pubspec.existsSync()
            ? (_pubspecName.firstMatch(pubspec.readAsStringSync())?.group(1) ?? root)
            : root;
        final lib = Directory('$root/lib');
        if (!lib.existsSync()) {
          return out;
        }
        final List<File> files =
            lib.listSync(recursive: true).whereType<File>().where((File f) => f.path.endsWith('.dart')).toList()
              ..sort((File a, File b) => a.path.compareTo(b.path));
        for (final file in files) {
          final String rel = file.path.substring(lib.path.length + 1).replaceAll(r'\', '/');
          for (final Match m in _classDecl.allMatches(_code(file.readAsStringSync()))) {
            out.putIfAbsent(m.group(1)!, () => 'package:$package/$rel');
          }
        }
        return out;
      });
      for (final MapEntry<String, String> e in found.entries) {
        declared.putIfAbsent(e.key, () => e.value);
      }
    }
    return declared;
  }
}

/// A component in the element tree, or the synthetic root.
class Component {
  Component._(this.element, this.parent);

  /// Null for the synthetic root, which owns everything above the first
  /// component.
  final Element? element;
  final Component? parent;
  final List<Component> children = <Component>[];

  /// This component's id segment, unique among its siblings.
  late String segment;

  String get fullId => parent == null ? segment : '${parent!.fullId}/$segment';

  /// The render object at the top of this component, which gives its bounds.
  RenderObject? get renderObject => element?.renderObject;

  /// The child of this component on the way down to [descendant], or null if
  /// [descendant] is not below this component.
  Component? childToward(Component descendant) {
    Component? c = descendant;
    while (c != null && c.parent != this) {
      c = c.parent;
    }
    return c;
  }
}

/// The component tree and the owner of every render object built by an
/// element.
class ComponentTree {
  ComponentTree._(this.root, this.ownerOf);

  /// Walks the element tree below [rootElement].
  factory ComponentTree.build(Element rootElement, ComponentPolicy policy) {
    final root = Component._(null, null)..segment = 'root';
    final ownerOf = <RenderObject, Component>{};
    void visit(Element e, Component current) {
      Component here = current;
      if (policy.isComponent(e.widget)) {
        here = Component._(e, current);
        current.children.add(here);
      }
      if (e is RenderObjectElement) {
        ownerOf[e.renderObject] = here;
      }
      e.visitChildren((Element child) => visit(child, here));
    }

    visit(rootElement, root);
    return ComponentTree._(root, ownerOf);
  }

  final Component root;

  /// Render objects built by an element, mapped to their nearest component.
  /// Render objects a render object creates for itself have no element and
  /// belong to their parent's component.
  final Map<RenderObject, Component> ownerOf;

  Component ownerOfRenderObject(RenderObject ro) {
    RenderObject? r = ro;
    while (r != null) {
      final Component? c = ownerOf[r];
      if (c != null) {
        return c;
      }
      r = r.parent;
    }
    return root;
  }

  /// The nearest component of [ro] that is still in the tree after
  /// [pruneAndName]: content that was not shown belongs to the shown
  /// component around it.
  Component shownOwnerOf(RenderObject ro) {
    bool shown(Component c) => c.parent == null || (c.parent!.children.contains(c) && shown(c.parent!));
    Component c = ownerOfRenderObject(ro);
    while (!shown(c)) {
      c = c.parent!;
    }
    return c;
  }

  Iterable<Component> get all sync* {
    Iterable<Component> visit(Component c) sync* {
      yield c;
      for (final Component child in c.children) {
        yield* visit(child);
      }
    }

    yield* visit(root);
  }

  /// Removes every component for which [keep] is false, with its subtree,
  /// then gives each remaining component its id segment. Ordinals count only
  /// the components kept, so content that is not shown does not renumber
  /// what is.
  void pruneAndName(bool Function(Component) keep) {
    void prune(Component c) {
      c.children.removeWhere((Component child) => !keep(child));
      c.children.forEach(prune);
    }

    prune(root);
    _assignSegments(root);
  }

  static void _assignSegments(Component c) {
    final counts = <String, int>{};
    final used = <String, int>{};
    for (final Component child in c.children) {
      final Widget w = child.element!.widget;
      final String type = w.runtimeType.toString();
      final String? key = _stableKey(w.key);
      String segment;
      if (key != null) {
        segment = '$type#$key';
      } else {
        final int n = counts[type] ?? 0;
        counts[type] = n + 1;
        segment = '$type@$n';
      }
      final int dup = used[segment] ?? 0;
      used[segment] = dup + 1;
      child.segment = dup == 0 ? segment : '$segment@$dup';
      _assignSegments(child);
    }
  }

  /// Keys whose value is the same in every run: a ValueKey of a string,
  /// number, boolean or enum. Other keys hold object identities.
  static String? _stableKey(Key? key) {
    if (key is! ValueKey) {
      return null;
    }
    final Object? v = key.value;
    final String? text = switch (v) {
      final String s => s,
      final num n => n.toString(),
      final bool b => b.toString(),
      final Enum e => '${e.runtimeType}.${e.name}',
      _ => null,
    };
    // Escaped so a key cannot read as a path step, a key marker or the
    // ordinal suffix that tells equal segments apart.
    return text?.replaceAll('%', '%25').replaceAll('/', '%2F').replaceAll('#', '%23').replaceAll('@', '%40');
  }
}

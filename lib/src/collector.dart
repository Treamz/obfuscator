import 'dart:convert' as dart_convert;
import 'dart:io' as dart_io;

import 'package:analyzer/dart/analysis/analysis_context.dart' as analyzer_context;
import 'package:analyzer/dart/analysis/analysis_context_collection.dart' as analyzer_context_collection;
import 'package:analyzer/dart/analysis/results.dart' as analyzer_results;
import 'package:analyzer/dart/ast/ast.dart' as analyzer_ast;
import 'package:analyzer/dart/ast/token.dart' as analyzer_token;
import 'package:analyzer/dart/ast/visitor.dart' as analyzer_visitor;
import 'package:analyzer/dart/element/element.dart' as analyzer_element;
import 'package:analyzer/dart/element/type.dart' as analyzer_type;
import 'package:analyzer/diagnostic/diagnostic.dart' as analyzer_diagnostic;
import 'package:analyzer/error/error.dart' as analyzer_error;
import 'package:obfuscator/src/config.dart';
import 'package:path/path.dart' as path;

/// Dart source code file reference.
///
class ObjectCollectorSource {
  /// Constructs a new reference of the object collector source [file].
  ///
  ObjectCollectorSource({
    required this.file,
    required this.resolvedUnitResult,
    required this.package,
    required this.isDeclarable,
  });

  /// A reference to the source file on the file system.
  ///
  final dart_io.File file;

  /// The result of building a resolved AST for a source file.
  ///
  final analyzer_results.ResolvedUnitResult resolvedUnitResult;

  /// The package this file belongs to.
  ///
  final SourcePackage package;

  /// Whether declarations of this file can be obfuscated.
  ///
  /// Only the declarations placed in the `lib` directory of a package are obfuscated,
  /// while the references are updated in all of the package files (e.g., `bin` and `test`).
  ///
  final bool isDeclarable;
}

/// Kind of a declaration renamed by the obfuscator.
///
enum ObfuscatedSymbolKind {
  /// Class declaration, including class type aliases.
  ///
  classDeclaration,

  /// Field declaration, including all of the fields overriding one another.
  ///
  field,
}

/// Position of a symbol name within a source file.
///
class ObjectOccurrence {
  /// Creates an occurrence of a symbol at the [offset] of the [filePath] file.
  ///
  /// An occurrence with [length] of `0` represents an insertion of the symbol name,
  /// e.g., for the shorthand object pattern fields (`Point(:final x)`).
  ///
  const ObjectOccurrence({
    required this.filePath,
    required this.offset,
    required this.length,
    required this.isDeclaration,
  });

  /// Path of the file containing the occurrence.
  ///
  final String filePath;

  /// Offset from the beginning of the file to the first character of the name.
  ///
  final int offset;

  /// Length of the replaced text.
  ///
  final int length;

  /// Whether the occurrence is the declaration of the symbol.
  ///
  final bool isDeclaration;
}

/// A declaration (and all of its occurrences) selected for obfuscation.
///
class ObfuscatedSymbol {
  /// Creates a symbol identified by the [key], originally named [name].
  ///
  ObfuscatedSymbol({
    required this.key,
    required this.name,
    required this.kind,
    required this.parentName,
  });

  /// Unique identifier, based on the declaring library URI and the declaration name.
  ///
  final String key;

  /// Original declaration name.
  ///
  final String name;

  /// Kind of the declaration.
  ///
  final ObfuscatedSymbolKind kind;

  /// Name of the class declaring the field, if the symbol is a field.
  ///
  final String? parentName;

  /// All of the positions of this symbol name within the source files.
  ///
  final occurrences = <ObjectOccurrence>[];

  /// File paths and offsets of the recorded [occurrences].
  ///
  final _occurrenceKeys = <(String, int)>{};

  /// Records an occurrence, ignoring any duplicate entries.
  ///
  void addOccurrence(ObjectOccurrence occurrence) {
    if (_occurrenceKeys.add((occurrence.filePath, occurrence.offset))) occurrences.add(occurrence);
  }
}

/// Class implemented for collecting object declarations and their respective references.
///
/// Declarations and references are matched using the resolved element model, so that
/// the same name used for unrelated elements (e.g., a local variable shadowing a field) is never mixed up.
///
/// Fields are grouped into families of members overriding one another. A family is renamed only
/// if all of its members are fields declared in the obfuscated packages. If any of the members
/// is an explicit getter, setter or method, is declared by a third-party library, or is excluded
/// from obfuscation, the whole family keeps its original name.
///
class ObjectCollector {
  /// Generates a new instance of the object declaration collector with the given [configuration].
  ///
  ObjectCollector({
    required Configuration configuration,
  }) : _configuration = configuration;

  /// Object defining the basic input options for the obfuscation service.
  ///
  final Configuration _configuration;

  /// Resolved source files of the obfuscated packages.
  ///
  final objectCollectorSources = <ObjectCollectorSource>[];

  /// Identifiers used within the source files, which generated names must not collide with.
  ///
  final usedIdentifiers = <String>{};

  /// Symbols selected for obfuscation.
  ///
  final symbols = <ObfuscatedSymbol>[];

  /// Symbols selected for obfuscation, mapped by the keys of all of the elements they represent.
  ///
  final _symbolsByKey = <String, ObfuscatedSymbol>{};

  /// Built-in annotations of generated types which must not be obfuscated.
  ///
  static const _excludedAnnotations = {'freezed', 'Freezed', 'unfreezed', 'RoutePage'};

  /// Unique identifier of a class-like [element].
  ///
  static String classKey(analyzer_element.InterfaceElement element) {
    return '${element.library.uri}#${element.name}';
  }

  /// Unique identifier of a member named [name], declared by the [element].
  ///
  static String memberKey(analyzer_element.InterfaceElement element, String name) {
    return '${classKey(element)}.$name';
  }

  /// Unique identifier of the [field] declaration, or `null` if it isn't declared by a class-like element.
  ///
  static String? _fieldKey(analyzer_element.FieldElement? field) {
    final enclosingElement = field?.enclosingElement;
    final name = field?.name;
    if (enclosingElement is! analyzer_element.InterfaceElement || name == null) return null;
    return memberKey(enclosingElement, name);
  }

  /// Unique identifier of the class or field an [element] reference resolves to.
  ///
  /// Parameters initialising fields (directly or through super parameters or redirecting factories)
  /// share the identifier of the field, as their names must match.
  ///
  static String? keyFor(analyzer_element.Element? element, [int depth = 0]) {
    if (element == null || depth > 32) return null;
    final base = element.baseElement;
    if (base is analyzer_element.ClassElement) return classKey(base);
    if (base is analyzer_element.FieldElement) return _fieldKey(base);
    if (base is analyzer_element.PropertyAccessorElement) {
      final variable = base.variable;
      return variable is analyzer_element.FieldElement ? _fieldKey(variable) : null;
    }
    if (base is analyzer_element.FieldFormalParameterElement) return _fieldKey(base.field);
    if (base is analyzer_element.SuperFormalParameterElement) {
      return keyFor(base.superConstructorParameter, depth + 1);
    }
    if (base is analyzer_element.FormalParameterElement && base.isNamed) {
      final constructor = base.enclosingElement;
      if (constructor is analyzer_element.ConstructorElement && constructor.isFactory) {
        final redirectedConstructor = constructor.redirectedConstructor;
        if (redirectedConstructor != null) {
          for (final parameter in redirectedConstructor.formalParameters) {
            if (parameter.isNamed && parameter.name == base.name) return keyFor(parameter, depth + 1);
          }
        }
      }
    }
    return null;
  }

  /// Returns the symbol selected for obfuscation which the [element] reference resolves to.
  ///
  ObfuscatedSymbol? symbolFor(analyzer_element.Element? element) {
    final key = keyFor(element);
    return key == null ? null : _symbolsByKey[key];
  }

  /// Returns the element assigned to or updated by the [node], e.g., `field` in `object.field += 1`.
  ///
  /// Such identifiers are not resolved to an element by the analyzer, as the element is defined
  /// with the enclosing assignment, prefix or postfix expression.
  ///
  static analyzer_element.Element? assignedElement(analyzer_ast.SimpleIdentifier node) {
    analyzer_ast.AstNode target = node;
    final parent = node.parent;
    if (parent is analyzer_ast.PrefixedIdentifier && parent.identifier == node) {
      target = parent;
    } else if (parent is analyzer_ast.PropertyAccess && parent.propertyName == node) {
      target = parent;
    }
    final targetParent = target.parent;
    if (targetParent is analyzer_ast.AssignmentExpression && targetParent.leftHandSide == target) {
      return targetParent.writeElement ?? targetParent.readElement;
    }
    if (targetParent is analyzer_ast.PostfixExpression && targetParent.operand == target) {
      return targetParent.readElement ?? targetParent.writeElement;
    }
    if (targetParent is analyzer_ast.PrefixExpression && targetParent.operand == target) {
      return targetParent.readElement ?? targetParent.writeElement;
    }
    return null;
  }

  /// Whether an annotated declaration is marked as not to be obfuscated,
  /// either by an annotation or by specifying its [name] with the configuration.
  ///
  bool _isExcluded(
    analyzer_ast.AnnotatedNode node, {
    String? name,
  }) {
    final identifiers = _configuration.publicApiIdentifiers;
    for (final annotation in node.metadata) {
      final annotationName = annotation.name;
      final fullName = annotationName.name;
      final simpleName = annotationName is analyzer_ast.PrefixedIdentifier ? annotationName.identifier.name : fullName;
      if (identifiers.contains(fullName) || identifiers.contains(simpleName) || _excludedAnnotations.contains(simpleName)) {
        return true;
      }
    }
    return name != null && identifiers.contains(name);
  }

  /// Returns the analysis context of the [collection] which the [filePath] file belongs to.
  ///
  /// Files excluded from analysis (e.g., with the `analysis_options.yaml` configuration)
  /// are still resolved, since their references must be updated as well.
  ///
  static analyzer_context.AnalysisContext contextFor(
    analyzer_context_collection.AnalysisContextCollection collection,
    String filePath,
  ) {
    analyzer_context.AnalysisContext? result;
    for (final context in collection.contexts) {
      final rootPath = context.contextRoot.root.path;
      if (path.isWithin(rootPath, filePath) && (result == null || result.contextRoot.root.path.length < rootPath.length)) {
        result = context;
      }
    }
    if (result == null) {
      throw ConfigurationException('No analysis context found for "$filePath".');
    }
    return result;
  }

  /// Lists the Dart files of the copied [package], including its nested packages, excluding hidden directories.
  ///
  static List<String> listDartFiles(SourcePackage package) {
    final files = <String>[];
    void visit(dart_io.Directory directory, {required bool isLibrary}) {
      for (final entity in directory.listSync(followLinks: false)) {
        final name = path.basename(entity.path);
        // Hidden entries (e.g., `.dart_tool`) are skipped, unless they are a part of the `lib` sources.
        if (name.startsWith('.') && (!isLibrary || name == '.dart_tool')) continue;
        if (entity is dart_io.Directory) {
          visit(entity, isLibrary: isLibrary || name == 'lib');
        } else if (entity is dart_io.File && entity.path.endsWith('.dart')) {
          files.add(entity.path);
        }
      }
    }

    visit(package.copyDirectory, isLibrary: false);
    return files..sort();
  }

  /// Files which are not valid Dart code (e.g., templates), which are neither obfuscated nor merged.
  ///
  final invalidFiles = <String>{};

  /// Whether the [filePath] belongs to the `lib` directory of the copied [package] itself,
  /// rather than to another directory or to a nested package.
  ///
  static bool isLibraryFile(SourcePackage package, String filePath) {
    return path.isWithin(path.join(package.copyDirectory.path, 'lib'), filePath) &&
        !package.nestedPackageDirectories.any((directory) => path.isWithin(directory, filePath));
  }

  /// Collect and store source code information.
  ///
  Future<void> _collectSources() async {
    final errors = <String>[];
    for (final package in _configuration.packages) {
      for (final filePath in listDartFiles(package)) {
        try {
          dart_convert.utf8.decode(dart_io.File(filePath).readAsBytesSync());
        } on FormatException {
          throw ConfigurationException('"$filePath" is not a valid UTF-8 file, which is required for its analysis.');
        }
        final result = await contextFor(_configuration.analysisContextCollection, filePath).currentSession.getResolvedUnit(filePath);
        if (result is! analyzer_results.ResolvedUnitResult) {
          throw ConfigurationException('Unable to analyze "$filePath": ${result.runtimeType}.');
        }
        if (result.diagnostics.any((diagnostic) => diagnostic.diagnosticCode.type == analyzer_error.DiagnosticType.SYNTACTIC_ERROR)) {
          print('Warning: "$filePath" is not valid Dart code (e.g., a template), it is neither obfuscated nor merged.');
          invalidFiles.add(filePath);
          continue;
        }
        for (final diagnostic in result.diagnostics) {
          if (diagnostic.severity == analyzer_diagnostic.Severity.error) {
            final location = result.lineInfo.getLocation(diagnostic.offset);
            errors.add('$filePath:${location.lineNumber}:${location.columnNumber}: ${diagnostic.message}');
          }
        }
        objectCollectorSources.add(
          ObjectCollectorSource(
            file: dart_io.File(filePath),
            resolvedUnitResult: result,
            package: package,
            isDeclarable: isLibraryFile(package, filePath),
          ),
        );
        analyzer_token.Token? token = result.unit.beginToken;
        while (token != null && !token.isEof) {
          if (token.isIdentifier) usedIdentifiers.add(token.lexeme);
          token = token.next;
        }
      }
    }
    if (errors.isNotEmpty) {
      print(
        'Warning: the source code contains ${errors.length} analysis error(s), '
        'references around them may not be obfuscated correctly:',
      );
      for (final error in errors.take(10)) {
        print('  $error');
      }
      if (errors.length > 10) print('  ...');
    }
  }

  /// Collect the class-like declarations and the declarations which can be obfuscated.
  ///
  _Declarations _collectDeclarations() {
    final declarations = _Declarations();
    for (final source in objectCollectorSources) {
      source.resolvedUnitResult.unit.accept(
        _DeclarationVisitor(
          collector: this,
          source: source,
          declarations: declarations,
        ),
      );
      source.resolvedUnitResult.unit.accept(_DynamicAccessVisitor(declarations.dynamicMemberNames));
    }
    return declarations;
  }

  /// Names and static modifiers of the members declared by the [element].
  ///
  static Iterable<({String name, bool isStatic})> _declaredMembers(analyzer_element.InterfaceElement element) sync* {
    for (final field in element.fields) {
      if (!field.isSynthetic && field.name != null) yield (name: field.name!, isStatic: field.isStatic);
    }
    for (final accessor in [...element.getters, ...element.setters]) {
      if (!accessor.isSynthetic && accessor.name != null) yield (name: accessor.name!, isStatic: accessor.isStatic);
    }
    for (final method in element.methods) {
      if (method.name != null) yield (name: method.name!, isStatic: method.isStatic);
    }
  }

  /// Resolves a URI of a directive in the [source] to a file path, for the relative and first-party URIs.
  ///
  String? _resolveDirectiveUri(ObjectCollectorSource source, String? uri) {
    if (uri == null || uri.startsWith('dart:')) return null;
    if (uri.startsWith('package:')) {
      final segments = Uri.parse(uri).pathSegments;
      for (final package in _configuration.packages) {
        if (segments.isNotEmpty && package.name == segments.first) {
          return path.joinAll([package.copyDirectory.path, 'lib', ...segments.skip(1)]);
        }
      }
      return null;
    }
    return path.normalize(path.join(path.dirname(source.file.path), uri));
  }

  /// Groups of class-like elements with the same names, provided by the alternatives of conditional directives.
  ///
  List<List<analyzer_element.InterfaceElement>> _conditionalAlternatives() {
    final librariesByPath = {
      for (final source in objectCollectorSources)
        if (!source.resolvedUnitResult.unit.directives.any((directive) => directive is analyzer_ast.PartOfDirective))
          source.file.path: source.resolvedUnitResult.libraryElement,
    };
    final groups = <List<analyzer_element.InterfaceElement>>[];
    for (final source in objectCollectorSources) {
      for (final directive in source.resolvedUnitResult.unit.directives.whereType<analyzer_ast.NamespaceDirective>()) {
        if (directive.configurations.isEmpty) continue;
        final libraries = <Uri, analyzer_element.LibraryElement>{};
        void add(analyzer_element.LibraryElement? library) {
          if (library != null) libraries[library.uri] = library;
        }

        add(switch (directive) {
          analyzer_ast.ImportDirective(:final libraryImport) => libraryImport?.importedLibrary,
          analyzer_ast.ExportDirective(:final libraryExport) => libraryExport?.exportedLibrary,
        });
        add(librariesByPath[_resolveDirectiveUri(source, directive.uri.stringValue)]);
        for (final configuration in directive.configurations) {
          final resolvedUri = configuration.resolvedUri;
          add(
            resolvedUri is analyzer_element.DirectiveUriWithLibrary
                ? resolvedUri.library
                : librariesByPath[_resolveDirectiveUri(source, configuration.uri.stringValue)],
          );
        }
        if (libraries.length < 2) continue;
        final elementsByName = <String, List<analyzer_element.InterfaceElement>>{};
        for (final library in libraries.values) {
          for (final entry in library.exportNamespace.definedNames2.entries) {
            final element = entry.value;
            if (element is analyzer_element.InterfaceElement) {
              elementsByName.putIfAbsent(entry.key, () => []).add(element);
            }
          }
        }
        groups.addAll(elementsByName.values.where((elements) => elements.length > 1));
      }
    }
    return groups;
  }

  /// Groups the fields into families of overriding members, and selects the symbols to be obfuscated.
  ///
  void _selectSymbols(_Declarations declarations) {
    final families = _UnionFind();
    final nonRenamableMembers = <String>{};
    void addMember(analyzer_element.InterfaceElement element, String name) {
      final key = memberKey(element, name);
      families.add(key);
      if (!declarations.fields.containsKey(key)) nonRenamableMembers.add(key);
    }

    // Fields accessed dynamically can't be renamed, as the accesses can't be matched to their declarations.
    for (final entry in declarations.fields.entries) {
      if (declarations.dynamicMemberNames.contains(entry.value.name)) nonRenamableMembers.add(entry.key);
    }
    for (final element in declarations.interfaces) {
      for (final member in _declaredMembers(element)) {
        addMember(element, member.name);
        // All of the private members with the same name in a library are renamed together, as they determine
        // whether a private field can be promoted (e.g., a getter of an unrelated class prevents it).
        if (member.name.startsWith('_')) {
          families.union(memberKey(element, member.name), '${element.library.uri}#private:${member.name}');
        }
      }
      // Instance members with the same name, declared by the class or any of its supertypes, are related.
      // This includes the members inherited from one supertype, implementing the members of another one.
      final declarersByName = <String, List<analyzer_element.InterfaceElement>>{};
      for (final declarer in [element, for (final supertype in element.allSupertypes) supertype.element]) {
        for (final member in _declaredMembers(declarer)) {
          if (member.isStatic) continue;
          final declarers = declarersByName.putIfAbsent(member.name, () => []);
          if (!declarers.contains(declarer)) declarers.add(declarer);
        }
      }
      for (final entry in declarersByName.entries) {
        // Private members are only related to the members declared in the same library.
        final groups = entry.key.startsWith('_')
            ? [
                for (final uri in {for (final declarer in entry.value) declarer.library.uri})
                  [
                    for (final declarer in entry.value)
                      if (declarer.library.uri == uri) declarer,
                  ],
              ]
            : [entry.value];
        for (final group in groups) {
          for (final declarer in group) {
            addMember(declarer, entry.key);
            families.union(memberKey(group.first, entry.key), memberKey(declarer, entry.key));
          }
        }
      }
    }
    // Classes with the same name, declared by the alternatives of conditional imports or exports
    // (e.g., `if (dart.library.io)`), must keep matching names, along with their members.
    final classFamilies = _UnionFind();
    final nonRenamableClasses = <String>{};
    for (final group in _conditionalAlternatives()) {
      final first = group.first;
      for (final element in group) {
        classFamilies.union(classKey(first), classKey(element));
        if (!declarations.classes.containsKey(classKey(element))) nonRenamableClasses.add(classKey(element));
        for (final member in _declaredMembers(element)) {
          addMember(first, member.name);
          addMember(element, member.name);
          families.union(memberKey(first, member.name), memberKey(element, member.name));
        }
      }
    }
    final nonRenamableFamilies = {for (final key in nonRenamableMembers) families.find(key)};
    final nonRenamableClassFamilies = {for (final key in nonRenamableClasses) classFamilies.find(key)};

    final classSymbols = <String, ObfuscatedSymbol>{};
    for (final entry in declarations.classes.entries) {
      final family = classFamilies.find(entry.key);
      if (nonRenamableClassFamilies.contains(family)) continue;
      final symbol = classSymbols.putIfAbsent(family, () {
        final symbol = ObfuscatedSymbol(
          key: family,
          name: entry.value,
          kind: ObfuscatedSymbolKind.classDeclaration,
          parentName: null,
        );
        symbols.add(symbol);
        return symbol;
      });
      _symbolsByKey[entry.key] = symbol;
    }
    final familySymbols = <String, ObfuscatedSymbol>{};
    for (final entry in declarations.fields.entries) {
      final family = families.find(entry.key);
      if (nonRenamableFamilies.contains(family)) continue;
      final symbol = familySymbols.putIfAbsent(family, () {
        final symbol = ObfuscatedSymbol(
          key: family,
          name: entry.value.name,
          kind: ObfuscatedSymbolKind.field,
          parentName: entry.value.parentName,
        );
        symbols.add(symbol);
        return symbol;
      });
      _symbolsByKey[entry.key] = symbol;
    }
  }

  /// Records the positions of all of the declarations and references of the selected symbols.
  ///
  void _collectOccurrences() {
    for (final source in objectCollectorSources) {
      source.resolvedUnitResult.unit.accept(
        _OccurrenceVisitor(
          collector: this,
          filePath: source.file.path,
        ),
      );
    }
    // Symbols without a recorded declaration can't be renamed consistently.
    symbols.removeWhere((symbol) => !symbol.occurrences.any((occurrence) => occurrence.isDeclaration));
    _symbolsByKey.removeWhere((key, symbol) => !symbols.contains(symbol));
  }

  /// Collects the declarations to be obfuscated, along with their references.
  ///
  Future<void> processUnits() async {
    objectCollectorSources.clear();
    usedIdentifiers.clear();
    symbols.clear();
    _symbolsByKey.clear();
    await _collectSources();
    _selectSymbols(_collectDeclarations());
    _collectOccurrences();
    if (symbols.isEmpty) {
      print('No declarations to obfuscate were found.');
    }
    await _configuration.analysisContextCollection.dispose();
  }
}

/// Declarations collected from the source files.
///
class _Declarations {
  /// All of the class-like elements declared in the source files.
  ///
  final interfaces = <analyzer_element.InterfaceElement>[];

  /// Classes which can be obfuscated, mapped by their keys to their names.
  ///
  final classes = <String, String>{};

  /// Fields which can be obfuscated, mapped by their member keys.
  ///
  final fields = <String, ({String name, String parentName})>{};

  /// Names of the members accessed dynamically (e.g., on a `dynamic` receiver), which can't be resolved.
  ///
  final dynamicMemberNames = <String>{};
}

/// Disjoint-set structure used for grouping overriding members.
///
class _UnionFind {
  final _parents = <String, String>{};

  void add(String key) => _parents.putIfAbsent(key, () => key);

  String find(String key) {
    add(key);
    var root = key;
    while (_parents[root] != root) {
      root = _parents[root]!;
    }
    var current = key;
    while (_parents[current] != root) {
      final next = _parents[current]!;
      _parents[current] = root;
      current = next;
    }
    return root;
  }

  void union(String a, String b) {
    final rootA = find(a), rootB = find(b);
    if (rootA != rootB) _parents[rootB] = rootA;
  }
}

/// Collects the class-like declarations and the declarations which can be obfuscated.
///
class _DeclarationVisitor extends analyzer_visitor.RecursiveAstVisitor<void> {
  _DeclarationVisitor({
    required this.collector,
    required this.source,
    required this.declarations,
  });

  final ObjectCollector collector;

  final ObjectCollectorSource source;

  final _Declarations declarations;

  void _addInterface(analyzer_element.InterfaceElement? element) {
    if (element != null) declarations.interfaces.add(element);
  }

  void _addClass(
    analyzer_ast.AnnotatedNode node,
    analyzer_element.InterfaceElement? element,
    String name,
  ) {
    _addInterface(element);
    if (element is analyzer_element.ClassElement && source.isDeclarable && !collector._isExcluded(node, name: name)) {
      declarations.classes[ObjectCollector.classKey(element)] = name;
    }
  }

  @override
  void visitClassDeclaration(analyzer_ast.ClassDeclaration node) {
    _addClass(node, node.declaredFragment?.element, node.name.lexeme);
    super.visitClassDeclaration(node);
  }

  @override
  void visitClassTypeAlias(analyzer_ast.ClassTypeAlias node) {
    _addClass(node, node.declaredFragment?.element, node.name.lexeme);
    super.visitClassTypeAlias(node);
  }

  @override
  void visitMixinDeclaration(analyzer_ast.MixinDeclaration node) {
    _addInterface(node.declaredFragment?.element);
    super.visitMixinDeclaration(node);
  }

  @override
  void visitEnumDeclaration(analyzer_ast.EnumDeclaration node) {
    _addInterface(node.declaredFragment?.element);
    super.visitEnumDeclaration(node);
  }

  @override
  void visitExtensionTypeDeclaration(analyzer_ast.ExtensionTypeDeclaration node) {
    _addInterface(node.declaredFragment?.element);
    super.visitExtensionTypeDeclaration(node);
  }

  @override
  void visitFieldDeclaration(analyzer_ast.FieldDeclaration node) {
    super.visitFieldDeclaration(node);
    if (!source.isDeclarable || node.externalKeyword != null || collector._isExcluded(node)) return;
    final parentDeclaration = node.thisOrAncestorOfType<analyzer_ast.CompilationUnitMember>();
    if (parentDeclaration is! analyzer_ast.ClassDeclaration &&
        parentDeclaration is! analyzer_ast.MixinDeclaration &&
        parentDeclaration is! analyzer_ast.EnumDeclaration) {
      return;
    }
    if (collector._isExcluded(parentDeclaration!)) return;
    final parentName = (parentDeclaration as analyzer_ast.NamedCompilationUnitMember).name.lexeme;
    if (collector._configuration.publicApiIdentifiers.contains(parentName)) return;
    for (final variable in node.fields.variables) {
      final element = variable.declaredFragment?.element;
      final name = variable.name.lexeme;
      if (element is! analyzer_element.FieldElement || collector._isExcluded(variable, name: name)) continue;
      final enclosingElement = element.enclosingElement;
      if (enclosingElement is! analyzer_element.InterfaceElement) continue;
      declarations.fields[ObjectCollector.memberKey(enclosingElement, name)] = (name: name, parentName: parentName);
    }
  }
}

/// Collects the names of the members accessed on receivers with the `dynamic` or an unresolved type.
///
class _DynamicAccessVisitor extends analyzer_visitor.RecursiveAstVisitor<void> {
  _DynamicAccessVisitor(this.names);

  final Set<String> names;

  void _record(analyzer_ast.SimpleIdentifier name, analyzer_ast.Expression? target) {
    if (target == null) return;
    if ((name.element ?? ObjectCollector.assignedElement(name)) != null) return;
    final type = target.staticType;
    if (type == null || type is analyzer_type.DynamicType || type is analyzer_type.InvalidType) names.add(name.name);
  }

  @override
  void visitPropertyAccess(analyzer_ast.PropertyAccess node) {
    _record(node.propertyName, node.realTarget);
    super.visitPropertyAccess(node);
  }

  @override
  void visitPrefixedIdentifier(analyzer_ast.PrefixedIdentifier node) {
    if (node.prefix.element is! analyzer_element.PrefixElement) _record(node.identifier, node.prefix);
    super.visitPrefixedIdentifier(node);
  }

  @override
  void visitMethodInvocation(analyzer_ast.MethodInvocation node) {
    _record(node.methodName, node.realTarget);
    super.visitMethodInvocation(node);
  }

  @override
  void visitNamedExpression(analyzer_ast.NamedExpression node) {
    // A named argument of a dynamic invocation (e.g., of a `Function` value) can't be matched to its parameter,
    // which may be an initializing formal of a field (e.g., `builders['user']!(id: 7)` for `User.new`).
    final label = node.name.label;
    if (label.element == null && node.parent is analyzer_ast.ArgumentList) names.add(label.name);
    super.visitNamedExpression(node);
  }
}

/// Records the positions of all of the declarations and references of the selected symbols.
///
class _OccurrenceVisitor extends analyzer_visitor.RecursiveAstVisitor<void> {
  _OccurrenceVisitor({
    required this.collector,
    required this.filePath,
  });

  final ObjectCollector collector;

  final String filePath;

  void _record(
    analyzer_element.Element? element,
    analyzer_token.Token? token, {
    bool isDeclaration = false,
  }) {
    final symbol = collector.symbolFor(element);
    // The lexeme check guards against identifiers which resolve to a symbol under a different name.
    if (symbol == null || token == null || token.lexeme != symbol.name) return;
    symbol.addOccurrence(
      ObjectOccurrence(
        filePath: filePath,
        offset: token.offset,
        length: token.length,
        isDeclaration: isDeclaration,
      ),
    );
  }

  @override
  void visitClassDeclaration(analyzer_ast.ClassDeclaration node) {
    _record(node.declaredFragment?.element, node.name, isDeclaration: true);
    super.visitClassDeclaration(node);
  }

  @override
  void visitClassTypeAlias(analyzer_ast.ClassTypeAlias node) {
    _record(node.declaredFragment?.element, node.name, isDeclaration: true);
    super.visitClassTypeAlias(node);
  }

  @override
  void visitVariableDeclaration(analyzer_ast.VariableDeclaration node) {
    _record(
      node.declaredFragment?.element,
      node.name,
      isDeclaration: node.parent?.parent is analyzer_ast.FieldDeclaration,
    );
    super.visitVariableDeclaration(node);
  }

  @override
  void visitFieldFormalParameter(analyzer_ast.FieldFormalParameter node) {
    _record(node.declaredFragment?.element, node.name);
    super.visitFieldFormalParameter(node);
  }

  @override
  void visitSuperFormalParameter(analyzer_ast.SuperFormalParameter node) {
    _record(node.declaredFragment?.element, node.name);
    super.visitSuperFormalParameter(node);
  }

  @override
  void visitSimpleFormalParameter(analyzer_ast.SimpleFormalParameter node) {
    _record(node.declaredFragment?.element, node.name);
    super.visitSimpleFormalParameter(node);
  }

  @override
  void visitSimpleIdentifier(analyzer_ast.SimpleIdentifier node) {
    var element = node.element ?? ObjectCollector.assignedElement(node);
    if (element is analyzer_element.ConstructorElement) {
      // Only references to the class name itself, not to the named constructors.
      element = node.name == element.enclosingElement.name ? element.enclosingElement : null;
    }
    _record(element, node.token);
    super.visitSimpleIdentifier(node);
  }

  @override
  void visitNamedType(analyzer_ast.NamedType node) {
    _record(node.element, node.name);
    super.visitNamedType(node);
  }

  @override
  void visitPatternField(analyzer_ast.PatternField node) {
    final name = node.name;
    if (name != null) {
      final nameToken = name.name;
      if (nameToken != null) {
        _record(node.element, nameToken);
      } else {
        // Shorthand field (e.g., `Point(:final x)`), the new name is inserted before the colon.
        final symbol = collector.symbolFor(node.element);
        symbol?.addOccurrence(
          ObjectOccurrence(
            filePath: filePath,
            offset: name.colon.offset,
            length: 0,
            isDeclaration: false,
          ),
        );
      }
    }
    super.visitPatternField(node);
  }
}

import 'dart:io' as io;

import 'package:analyzer/dart/analysis/analysis_context.dart';
import 'package:analyzer/dart/analysis/context_builder.dart';
import 'package:analyzer/dart/analysis/context_locator.dart';
import 'package:analyzer/dart/analysis/context_root.dart';
import 'package:analyzer/dart/analysis/results.dart';
import 'package:analyzer/dart/analysis/session.dart';
import 'package:analyzer/dart/element/element.dart';
import 'package:analyzer/dart/element/type.dart';
import 'package:analyzer/dart/element/visitor.dart';
import 'package:analyzer/file_system/file_system.dart';
import 'package:gviz/gviz.dart';
import 'package:logging/logging.dart';
import 'package:path/path.dart' as path;

/// A utility class to generate a graph of the type hierarchy across a set of dart source files.
///
/// - [buildTypeGraph] can be used to create a generic graph of all types.
/// - [createGvizGraph] and [writeGraphToFile] can be used to output the file in
/// [Graphviz](https://graphviz.org/) format.
class TypeGraphBuilder extends GeneralizingElementVisitor<void> {
  /// The paths that will be included in the generated graph.
  final List<String> paths;

  /// The name of the graph in the output file.
  late final String graphName;

  final Map<InterfaceType, List<InterfaceType>> _graph = {};
  final List<File> _files = [];

  late final ContextRoot _root;
  late final AnalysisContext _context = ContextBuilder().createContext(contextRoot: _root);
  late final AnalysisSession _session = _context.currentSession;

  final Logger _logger = Logger('Type Graph');

  /// Create a new [TypeGraphBuilder].
  TypeGraphBuilder(this.paths, {String? name}) {
    final roots = ContextLocator().locateRoots(includedPaths: paths);

    if (roots.isEmpty) {
      throw Exception('Unable to locate context root for paths');
    }

    _logger.fine('Found ${roots.length} roots, using first root');
    _root = roots.first;

    graphName =
        name ?? _root.included.map((res) => res.path).map(path.basenameWithoutExtension).join(', ');
  }

  /// Create a type graph for the specified [paths] and output it in
  /// [Graphviz](https://graphviz.org/) format to [file].
  Future<void> writeGraphToFile(io.File file) async {
    final graph = await createGvizGraph();

    _logger.info('Writing graph to file ${file.path}...');

    final sink = file.openWrite();
    graph.write(sink);
    await sink.flush();
    await sink.close();

    _logger.info('Done writing graph to file ${file.path}');
  }

  /// Create a type graph for the specified [paths] in [Graphviz](https://graphviz.org/) format.
  Future<Gviz> createGvizGraph() async {
    final data = await buildTypeGraph();
    final display = data.map((type, parents) {
      final typeName = type.getDisplayString(withNullability: false);
      final parentNames = parents
          .map(
            (type) => type.getDisplayString(withNullability: false),
          )
          .toList();

      return MapEntry(typeName, parentNames);
    });

    final graph = Gviz(name: graphName);

    for (final node in display.keys) {
      graph.addNode(node);
    }

    for (final edges in display.entries) {
      final end = edges.key;
      for (final start in edges.value) {
        graph.addEdge(start, end);
      }
    }

    return graph;
  }

  /// Create a type graph for the specified [paths].
  Future<Map<InterfaceType, List<InterfaceType>>> buildTypeGraph() async {
    await _locateFiles();

    _graph.clear();
    await Future.wait(_files.map(_processFile));

    _logger.info('Done building graph with ${_graph.length} types found');
    return _graph;
  }

  Future<void> _processFile(File file) async {
    final result = await _session.getUnitElement(file.path);
    if (result is! UnitElementResult) {
      throw Exception('Invalid analysis result for file ${file.path}');
    }

    _logger.fine('Processing file ${file.path}');

    for (final element in result.element.children) {
      element.accept(this);
    }
  }

  Future<void> _locateFiles() async {
    _files.clear();

    _logger.fine('Locating files to be analysed');

    final folders = <Folder>[];

    for (final path in paths) {
      final resource = _session.resourceProvider.getResource(path);

      if (resource is File) {
        if (resource.path.endsWith('.dart')) {
          _files.add(resource);
        }
      } else if (resource is Folder) {
        folders.add(resource);
      } else {
        throw Exception('Unknown resource type ${resource.runtimeType}');
      }
    }

    while (folders.isNotEmpty) {
      final folder = folders.removeLast();
      final resources = folder.getChildren();

      for (final resource in resources) {
        if (resource is File) {
          if (resource.path.endsWith('.dart')) {
            _files.add(resource);
          }
        } else if (resource is Folder) {
          folders.add(resource);
        } else {
          throw Exception('Unknown resource type ${resource.runtimeType}');
        }
      }
    }

    _logger.info('Found ${_files.length} dart files to analyze');
  }

  @override
  void visitElement(Element element) {
    if (element is InterfaceElement) {
      _logger.finer('Found element $element');

      final type = element.thisType;

      final superTypes = [
        if (type.superclass != null) type.superclass!,
        ...type.interfaces,
        ...type.mixins,
        ...type.superclassConstraints,
      ].map((type) => type.element.thisType).toList();

      if (superTypes.length > 1) {
        superTypes.removeWhere((type) => type.isDartCoreObject);
      }

      _graph[type] = superTypes;
    }
  }
}

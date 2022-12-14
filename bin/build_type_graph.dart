import 'dart:io';

import 'package:args/args.dart';
import 'package:logging/logging.dart';
import 'package:path/path.dart' as path;
import 'package:type_graph/src/type_graph.dart';

void main(List<String> args) async {
  final parser = ArgParser(allowTrailingOptions: true)
    ..addFlag(
      'help',
      abbr: 'h',
      defaultsTo: false,
      help: 'Display this help menu and exit',
    )
    ..addOption(
      'output',
      abbr: 'o',
      defaultsTo: 'output.gv',
      help: 'The file to output the graph data to',
    )
    ..addFlag(
      'verbose',
      abbr: 'v',
      defaultsTo: false,
      help: 'Whether to be verbose',
    );

  final results = parser.parse(args);

  if (results['help'] as bool) {
    print('''    Type graph builder

Build a graph of type inheritances in your Dart app.

Usage:
  build_type_graph [options] file1 file2 ...

The specified files can be either individual files or
directories, in which case they are traversed recursively
to find source files.

Options:''');
    print(parser.usage);
    return;
  }

  Logger.root.level = Level.INFO;
  if (results['verbose'] as bool) {
    Logger.root.level = Level.ALL;
  }

  Logger.root.onRecord.listen((record) => print(record.message));

  final files = [
    for (final file in results.rest) path.canonicalize(file),
  ];

  final graphBuilder = TypeGraphBuilder(files);

  await graphBuilder.writeGraphToFile(File(results['output']));
}

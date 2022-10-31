import 'dart:io';

import 'package:type_graph/type_graph.dart';

void main() async {
  final paths = [
    '/path/to/dart/file.dart',
    '/path/to/other/dart/file.dart',
  ];

  final graphBuilder = TypeGraphBuilder(paths);

  await graphBuilder.writeGraphToFile(File('output.gz'));
}

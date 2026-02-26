import 'package:flutter/material.dart';

/// Placeholder screen for Content Library. Does not affect app start or main route.
class ContentLibraryScreen extends StatelessWidget {
  const ContentLibraryScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Content Library')),
      body: const Center(child: Text('Content Library')),
    );
  }
}

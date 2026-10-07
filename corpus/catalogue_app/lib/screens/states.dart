import 'package:flutter/material.dart';

import '../components/status_view.dart';

enum LoadState { empty, loading, error }

/// Level 3: empty, loading (a shimmer that never settles) and error states.
class StatesScreen extends StatelessWidget {
  const StatesScreen({super.key, required this.state});

  final LoadState state;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Activity')),
      body: switch (state) {
        LoadState.empty => const StatusView(
          icon: Icons.inbox_outlined,
          title: 'No activity yet',
          message: 'Trades and transfers will show up here.',
        ),
        LoadState.loading => Shimmer(child: Column(children: List<Widget>.generate(6, (int i) => const SkeletonRow()))),
        LoadState.error => const StatusView(
          icon: Icons.cloud_off_outlined,
          title: 'Something went wrong',
          message: 'Check your connection and try again.',
          action: 'Retry',
        ),
      },
    );
  }
}

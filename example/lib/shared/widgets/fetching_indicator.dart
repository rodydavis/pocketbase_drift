import 'package:flutter/material.dart';

/// A subtle linear progress bar that pulses at the top of a screen when background sync / network fetch is active.
class FetchingIndicator extends StatelessWidget {
  const FetchingIndicator({
    super.key,
    required this.isFetching,
    this.hasError = false,
  });

  final bool isFetching;
  final bool hasError;

  @override
  Widget build(BuildContext context) {
    if (hasError) {
      return Container(
        height: 3,
        color: Theme.of(context).colorScheme.error,
      );
    }
    if (!isFetching) return const SizedBox(height: 3);

    return const SizedBox(
      height: 3,
      child: LinearProgressIndicator(minHeight: 3),
    );
  }
}

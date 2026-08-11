import 'package:flutter/material.dart';
import 'package:vialer/presentation/resources/localizations.dart';
import 'package:vialer/presentation/util/context_extensions.dart';

class Heading extends StatelessWidget {
  const Heading({super.key});

  @override
  Widget build(BuildContext context) {
    return Semantics(
      header: true,
      child: Column(
        children: [
          Padding(
            padding: const EdgeInsets.symmetric(
              vertical: 10,
              horizontal: 20,
            ),
            child: Center(
              child: Text(
                context.msg.main.outgoingCLI.prompt.title,
                style: Theme.of(context).textTheme.titleLarge,
                textAlign: TextAlign.center,
              ),
            ),
          ),
          Divider(
            color: context.colors.grey5,
          ),
        ],
      ),
    );
  }
}

class Subheading extends StatelessWidget {
  const Subheading(this.text, {super.key});

  final String text;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(top: 12, bottom: 4),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Semantics(
            header: true,
            child: Text(text, style: Theme.of(context).textTheme.titleSmall),
          ),
          const SizedBox(height: 4),
        ],
      ),
    );
  }
}

import 'package:flutter/material.dart';

import 'package:vialer/presentation/resources/theme.dart';

class Background extends StatelessWidget {
  const Background({
    required this.style,
    required this.child,
    super.key,
  });

  final Style style;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    return Stack(
      children: [
        switch (style) {
          Style.triangle => const _BackgroundTriangle(),
          Style.split => const _BackgroundSplit(),
          Style.cascading => const _BackgroundCascading(),
        },
        child,
      ],
    );
  }
}

class _BackgroundTriangle extends StatelessWidget {
  const _BackgroundTriangle();

  @override
  Widget build(BuildContext context) {
    return Stack(
      children: [
        _BackgroundShape(
          begin: const Alignment(0.5, 1.2),
          end: const Alignment(-.8, 0),
          startColor: context.brand.theme.colors.primaryLight,
          endColor: Colors.white,
        ),
        _BackgroundShape(
          begin: const Alignment(1.2, -1),
          end: const Alignment(-.5, .4),
          startColor: context.brand.theme.colors.primary,
        ),
      ],
    );
  }
}

class _BackgroundSplit extends StatelessWidget {
  const _BackgroundSplit();

  @override
  Widget build(BuildContext context) {
    return Stack(
      children: [
        _BackgroundShape(
          begin: const Alignment(0.5, 0.6),
          end: const Alignment(-.8, .2),
          startColor: context.brand.theme.colors.primaryLight,
          endColor: Colors.white,
        ),
        _BackgroundShape(
          begin: Alignment.topRight,
          end: const Alignment(-1, 2.2),
          startColor: context.brand.theme.colors.primary,
        ),
      ],
    );
  }
}

class _BackgroundCascading extends StatelessWidget {
  const _BackgroundCascading();

  @override
  Widget build(BuildContext context) {
    return Stack(
      children: [
        _BackgroundShape(
          begin: const Alignment(-1.2, -.2),
          end: const Alignment(.5, .3),
          startColor: context.brand.theme.colors.primaryLight,
          endColor: Colors.white,
        ),
        _BackgroundShape(
          begin: const Alignment(-1.7, -1.1),
          end: const Alignment(.4, -.5),
          startColor: context.brand.theme.colors.primary,
        ),
      ],
    );
  }
}

class _BackgroundShape extends StatelessWidget {
  const _BackgroundShape({
    required this.begin,
    required this.end,
    required this.startColor,
    this.endColor = Colors.transparent,
  });

  final Alignment begin;
  final Alignment end;
  final Color startColor;
  final Color endColor;

  @override
  Widget build(BuildContext context) {
    return Positioned.fill(
      child: Container(
        decoration: BoxDecoration(
          gradient: LinearGradient(
            stops: const [.5, .5],
            begin: begin,
            end: end,
            colors: [
              startColor,
              endColor,
            ],
          ),
        ),
      ),
    );
  }
}

enum Style {
  triangle,
  split,
  cascading,
}

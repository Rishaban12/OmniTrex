import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../providers.dart';
import '../theme.dart';

/// Two illustrated intro pages, then the app hub.
class OnboardingScreen extends ConsumerStatefulWidget {
  const OnboardingScreen({super.key});

  @override
  ConsumerState<OnboardingScreen> createState() => _OnboardingScreenState();
}

class _OnboardingScreenState extends ConsumerState<OnboardingScreen> {
  final _pages = PageController();
  int _index = 0;

  static const _content = [
    (
      image: 'lib/data/static/dailynotes.png',
      title: 'Plan ahead.\nGet things done.',
      body: '',
      accent: Palette.blue,
    ),
    (
      image: 'lib/data/static/expense.png',
      title: 'Know where\nyour money goes.',
      body: '',
      accent: Palette.coral,
    ),
  ];

  @override
  void dispose() {
    _pages.dispose();
    super.dispose();
  }

  void _next() {
    if (_index < _content.length - 1) {
      _pages.nextPage(duration: const Duration(milliseconds: 350), curve: Curves.easeOutCubic);
    } else {
      ref.read(settingsProvider.notifier).update((s) => s.copyWith(onboardingSeen: true));
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final dark = theme.brightness == Brightness.dark;
    return Scaffold(
      body: SafeArea(
        child: Column(children: [
          const SizedBox(height: 24),
          Expanded(
            child: PageView.builder(
              controller: _pages,
              itemCount: _content.length,
              onPageChanged: (i) => setState(() => _index = i),
              itemBuilder: (context, i) {
                final page = _content[i];
                return LayoutBuilder(
                  builder: (context, box) => Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 24),
                    child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                      Expanded(
                        child: Center(
                          child: Container(
                            decoration: BoxDecoration(
                              color: dark ? Colors.white : Colors.transparent,
                              borderRadius: BorderRadius.circular(32),
                            ),
                            clipBehavior: Clip.antiAlias,
                            child: Image.asset(page.image, fit: BoxFit.contain),
                          ),
                        ),
                      ),
                      const SizedBox(height: 16),
                      Text(page.title,
                          style: (box.maxHeight < 560
                                  ? theme.textTheme.displaySmall
                                  : theme.textTheme.displayMedium)
                              ?.copyWith(fontWeight: FontWeight.w800)),
                      if (page.body.isNotEmpty) ...[
                        const SizedBox(height: 12),
                        Text(page.body,
                            style: theme.textTheme.titleMedium
                                ?.copyWith(color: theme.colorScheme.onSurfaceVariant)),
                      ],
                    ]),
                  ),
                );
              },
            ),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(24, 24, 24, 24),
            child: Row(children: [
              for (var i = 0; i < _content.length; i++)
                AnimatedContainer(
                  duration: const Duration(milliseconds: 250),
                  margin: const EdgeInsets.only(right: 6),
                  width: i == _index ? 28 : 8,
                  height: 8,
                  decoration: BoxDecoration(
                    color: i == _index
                        ? _content[_index].accent
                        : theme.colorScheme.outlineVariant,
                    borderRadius: BorderRadius.circular(4),
                  ),
                ),
              const Spacer(),
              SizedBox(
                width: 64,
                height: 64,
                child: FilledButton(
                  onPressed: _next,
                  style: FilledButton.styleFrom(
                    padding: EdgeInsets.zero,
                    shape: const CircleBorder(),
                  ),
                  child: const Icon(Icons.arrow_forward_rounded, size: 28),
                ),
              ),
            ]),
          ),
        ]),
      ),
    );
  }
}

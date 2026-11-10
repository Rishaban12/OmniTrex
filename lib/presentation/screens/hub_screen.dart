import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../app.dart';
import '../providers.dart';
import '../theme.dart';
import 'dolist_screen.dart';
import 'mindnotes_screen.dart';
import 'setup_screen.dart';

/// Landing grid after the splash (and onboarding): pick an app.
class HubScreen extends StatelessWidget {
  const HubScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Scaffold(
      body: BlobBackground(
        child: SafeArea(
          // Scrolls so short screens (landscape, split-screen) never squash
          // or overflow the tiles.
          child: ListView(
            padding: const EdgeInsets.fromLTRB(20, 8, 20, 20),
            children: [
              // Brand: logo + OmniTrex, letters centred on the logo's ring.
              Row(
                children: [
                  Image.asset('lib/data/static/logo.png', width: 36, height: 36, cacheWidth: 144),
                  const SizedBox(width: 3),
                  const Padding(
                    padding: EdgeInsets.only(top: 5),
                    child: Wordmark('Omni', 'Trex', fontSize: 18, gradient: Wordmark.blueGradient),
                  ),
                  const Spacer(),
                  const _ThemeToggle(),
                ],
              ),
              const SizedBox(height: 24),
              FittedBox(
                fit: BoxFit.scaleDown,
                alignment: Alignment.centerLeft,
                child: Text('What\'s next?', maxLines: 1, style: theme.textTheme.displayMedium),
              ),
              const SizedBox(height: 28),
              LayoutBuilder(
                // Two per row on phones, all three in one row on wide screens.
                builder: (context, box) => GridView.count(
                  crossAxisCount: box.maxWidth > 600 ? 3 : 2,
                  shrinkWrap: true,
                  physics: const NeverScrollableScrollPhysics(),
                  mainAxisSpacing: 14,
                  crossAxisSpacing: 14,
                  childAspectRatio: box.maxWidth > 600 ? 0.8 : 0.72,
                  children: [
                    _AppTile(
                      name: 'DoList',
                      image: 'lib/data/static/dailynotes.png',
                      accent: Palette.blue,
                      onTap: () => Navigator.push(context, MaterialPageRoute(builder: (_) => const DoListScreen())),
                    ),
                    _AppTile(
                      name: 'PocketPlan',
                      image: 'lib/data/static/expense.png',
                      accent: Palette.yellow,
                      onTap: () => Navigator.push(context, MaterialPageRoute(builder: (_) => const PocketPlanEntry())),
                    ),
                    _AppTile(
                      name: 'MindNotes',
                      image: 'lib/data/static/MindNotes.png',
                      accent: Palette.purple,
                      onTap: () => Navigator.push(context, MaterialPageRoute(builder: (_) => const MindNotesScreen())),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// Light ↔ dark switch for the whole app. Sun in light mode, moon in dark.
class _ThemeToggle extends ConsumerWidget {
  const _ThemeToggle();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final dark = ref.watch(settingsProvider.select((s) => s.themeMode)) == ThemeMode.dark;
    // Plain tap target: no hover / press highlight, no tooltip.
    return MouseRegion(
      cursor: SystemMouseCursors.click,
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: () => ref
            .read(settingsProvider.notifier)
            .update((s) => s.copyWith(themeMode: dark ? ThemeMode.light : ThemeMode.dark)),
        child: Semantics(
          button: true,
          label: dark ? 'Switch to light mode' : 'Switch to dark mode',
          child: Padding(
            padding: const EdgeInsets.all(11),
            child: AnimatedSwitcher(
              duration: const Duration(milliseconds: 250),
              transitionBuilder: (child, anim) => RotationTransition(
                turns: anim,
                child: FadeTransition(opacity: anim, child: child),
              ),
              child: Icon(
                dark ? Icons.dark_mode_rounded : Icons.light_mode_rounded,
                key: ValueKey(dark),
                color: dark ? Palette.blue : Palette.orange,
                size: 26,
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _AppTile extends StatelessWidget {
  const _AppTile({required this.name, required this.image, required this.accent, required this.onTap});
  final String name, image;
  final Color accent;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Material(
      color: Palette.soft(accent, theme.brightness),
      borderRadius: BorderRadius.circular(28),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.all(14),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(
                child: Container(
                  width: double.infinity,
                  decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(20)),
                  clipBehavior: Clip.antiAlias,
                  child: Image.asset(image, fit: BoxFit.cover, alignment: const Alignment(0, -0.1)),
                ),
              ),
              const SizedBox(height: 12),
              // One line always (shrinks on very narrow screens), so every
              // tile's picture gets the same height.
              FittedBox(
                fit: BoxFit.scaleDown,
                alignment: Alignment.centerLeft,
                child: Text(
                  name,
                  maxLines: 1,
                  style: theme.textTheme.titleLarge?.copyWith(fontWeight: FontWeight.w800),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// PocketPlan: budget setup the first time, the expense tracker after.
class PocketPlanEntry extends ConsumerWidget {
  const PocketPlanEntry({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final setupDone = ref.watch(settingsProvider.select((s) => s.setupDone));
    return setupDone ? const HomeShell() : const SetupScreen();
  }
}

import 'package:flutter/material.dart';

import 'theme.dart';

/// Sticky-note palette for DoList: pastel paper + a stronger "tape" accent.
class NoteStyle {
  const NoteStyle(this.paper, this.tape);
  final Color paper;
  final Color tape;

  static const all = [
    NoteStyle(Palette.yellowSoft, Palette.yellow),
    NoteStyle(Palette.blueSoft, Palette.blue),
    NoteStyle(Palette.coralSoft, Palette.coral),
    NoteStyle(Palette.greenSoft, Palette.green),
    NoteStyle(Color(0xFFEADCFB), Color(0xFF9B6BE8)),
  ];

  static NoteStyle of(int index) => all[index.abs() % all.length];
}

/// Cheerful line for the progress header.
String doListCheer(int done, int total) {
  if (total == 0) return 'Fresh page — what\'s the plan?';
  if (done == 0) return 'Let\'s get the first one done!';
  if (done == total) return 'All done — amazing work! 🎉';
  final left = total - done;
  if (done / total >= 0.5) return 'Over halfway — $left to go! 💪';
  return 'Nice start — keep it rolling! ✨';
}

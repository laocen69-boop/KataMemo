library;

import 'package:flutter/material.dart';

const Color kRatingKnow = Color(0xFF22A06B);

const Color kRatingFuzzy = Color(0xFFE8920C);

const Color kRatingForget = Color(0xFFD9483B);

const Color kRatingEasy = Color(0xFF2F7FD8);

const List<({String label, Color color})> kRatingLegend = [
  (label: '轻松', color: kRatingEasy),
  (label: '记得', color: kRatingKnow),
  (label: '模糊', color: kRatingFuzzy),
  (label: '困难', color: kRatingForget),
];

Color ratingColor(int r) => r >= 3
    ? kRatingEasy
    : (r >= 2 ? kRatingKnow : (r == 1 ? kRatingFuzzy : kRatingForget));

String ratingName(int r) =>
    r >= 3 ? '轻松' : (r >= 2 ? '认识' : (r == 1 ? '模糊' : '困难'));

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import '../main.dart';
import '../theme/m3_expressive_theme.dart';
import 'app_motion.dart';
import '../utils/responsive_scale.dart';

class MinimalNewsPill extends StatelessWidget {
  const MinimalNewsPill({super.key});

  static const List<Map<String, String>> _fallbackNews = [
    {
      'title': 'Utopia Campus News & Updates',
      'description': 'Stay connected with campus events, announcements, and academic updates right from your home screen.',
    },
    {
      'title': 'Keep Your Attendance on Track',
      'description': 'Target 75%+ attendance across all subjects to stay exam eligible.',
    },
  ];

  double _calculatePillWidth(String title, [ResponsiveScale? rs]) {
    final fontSize = rs != null ? rs.font(11.5, min: 10.0, max: 13.5) : 11.5;
    final maxW = rs != null ? rs.s(210.0, min: 170.0, max: 280.0) : 210.0;
    final textPainter = TextPainter(
      text: TextSpan(
        text: title,
        style: GoogleFonts.robotoFlex(
          fontSize: fontSize,
          fontWeight: FontWeight.w700,
          letterSpacing: 0.1,
        ),
      ),
      maxLines: 1,
      textDirection: TextDirection.ltr,
    )..layout(maxWidth: maxW);
    final extra = rs != null ? rs.s(46.0, min: 38.0, max: 54.0) : 46.0;
    final minLimit = rs != null ? rs.s(80.0, min: 70.0, max: 100.0) : 80.0;
    final maxLimit = rs != null ? rs.s(260.0, min: 210.0, max: 320.0) : 250.0;
    return (textPainter.width + extra).clamp(minLimit, maxLimit);
  }

  void _showNewsDetails(BuildContext context, List<Map<String, String>> items, int index) {
    if (items.isEmpty) return;
    final item = items[index % items.length];
    final isDark = appThemeNotifier.value.isDark;

    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.transparent,
      isScrollControlled: true,
      builder: (context) {
        return Container(
          decoration: BoxDecoration(
            color: U.surfaceContainerHigh,
            borderRadius: const BorderRadius.vertical(top: Radius.circular(28)),
            border: Border.all(color: U.outlineVariant.withValues(alpha: 0.4)),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withValues(alpha: isDark ? 0.4 : 0.1),
                blurRadius: 20,
                offset: const Offset(0, -4),
              ),
            ],
          ),
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Center(
                child: Container(
                  width: 36,
                  height: 4,
                  decoration: BoxDecoration(
                    color: U.outlineVariant,
                    borderRadius: M3Shapes.fullRadius,
                  ),
                ),
              ),
              const SizedBox(height: 20),
              Row(
                children: [
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                    decoration: BoxDecoration(
                      color: U.primary.withValues(alpha: 0.12),
                      borderRadius: M3Shapes.smallRadius,
                    ),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(Icons.newspaper_rounded, size: 12, color: U.primary),
                        const SizedBox(width: 5),
                        Text(
                          'CAMPUS NEWS',
                          style: GoogleFonts.robotoFlex(
                            fontSize: 9.5,
                            fontWeight: FontWeight.w800,
                            letterSpacing: 1.2,
                            color: U.primary,
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 14),
              Text(
                item['title'] ?? 'News Update',
                style: GoogleFonts.newsreader(
                  fontSize: 22,
                  fontWeight: FontWeight.bold,
                  fontStyle: FontStyle.italic,
                  color: U.text,
                  height: 1.25,
                ),
              ),
              if ((item['description'] ?? '').isNotEmpty) ...[
                const SizedBox(height: 12),
                Text(
                  item['description']!,
                  style: GoogleFonts.robotoFlex(
                    fontSize: 14,
                    color: U.sub,
                    height: 1.5,
                  ),
                ),
              ],
              const SizedBox(height: 24),
              SizedBox(
                width: double.infinity,
                child: TextButton(
                  onPressed: () => Navigator.pop(context),
                  style: TextButton.styleFrom(
                    padding: const EdgeInsets.symmetric(vertical: 14),
                    backgroundColor: U.primary.withValues(alpha: 0.12),
                    shape: RoundedRectangleBorder(
                      borderRadius: M3Shapes.fullRadius,
                    ),
                  ),
                  child: Text(
                    'Close',
                    style: GoogleFonts.robotoFlex(
                      fontSize: 14,
                      fontWeight: FontWeight.w700,
                      color: U.primary,
                    ),
                  ),
                ),
              ),
            ],
          ),
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    final pillColor = U.primary;

    return StreamBuilder<DocumentSnapshot<Map<String, dynamic>>>(
      stream: FirebaseFirestore.instance
          .collection('config')
          .doc('app_config')
          .snapshots(),
      builder: (context, snapshot) {
        List<Map<String, String>> newsItems = [];

        if (snapshot.hasData && snapshot.data != null && snapshot.data!.exists) {
          final data = snapshot.data!.data();
          if (data != null) {
            final isEnabled = data['news_enabled'] as bool? ?? true;
            if (isEnabled) {
              final title = (data['news_title'] as String? ?? '').trim();
              final desc = (data['news_description'] as String? ?? '').trim();
              if (title.isNotEmpty) {
                newsItems.add({'title': title, 'description': desc});
              }

              final rawList = data['news_items'] as List?;
              if (rawList != null) {
                for (final item in rawList) {
                  if (item is Map) {
                    final t = (item['title'] as String? ?? item['heading'] as String? ?? '').trim();
                    final d = (item['description'] as String? ?? '').trim();
                    if (t.isNotEmpty && !newsItems.any((e) => e['title'] == t)) {
                      newsItems.add({'title': t, 'description': d});
                    }
                  } else if (item is String && item.trim().isNotEmpty) {
                    final t = item.trim();
                    if (!newsItems.any((e) => e['title'] == t)) {
                      newsItems.add({'title': t, 'description': ''});
                    }
                  }
                }
              }
            }
          }
        }

        if (newsItems.isEmpty) {
          newsItems = _fallbackNews;
        }

        final activeItem = newsItems.first;
        final activeTitle = activeItem['title'] ?? '';
        final rs = ResponsiveScale.of(context);
        final pillWidth = _calculatePillWidth(activeTitle, rs);

        return M3Pressable(
          onTap: () {
            _showNewsDetails(context, newsItems, 0);
          },
          scaleFactor: 0.94,
          borderRadius: M3Shapes.fullRadius,
          child: Container(
            width: pillWidth,
            padding: EdgeInsets.symmetric(
              horizontal: rs.s(16, min: 12, max: 20),
              vertical: rs.s(10, min: 8, max: 13),
            ),
            decoration: BoxDecoration(
              color: U.surfaceContainerHigh,
              borderRadius: M3Shapes.fullRadius,
              border: Border.all(
                color: U.outlineVariant.withValues(alpha: 0.35),
                width: 0.8,
              ),
            ),
            child: Row(
              children: [
                Stack(
                  alignment: Alignment.topRight,
                  children: [
                    Icon(
                      Icons.newspaper_rounded,
                      size: rs.s(15, min: 13, max: 18),
                      color: pillColor,
                    ),
                    Container(
                      width: rs.s(5, min: 4, max: 7),
                      height: rs.s(5, min: 4, max: 7),
                      decoration: const BoxDecoration(
                        color: Colors.redAccent,
                        shape: BoxShape.circle,
                      ),
                    ),
                  ],
                ),
                SizedBox(width: rs.s(8, min: 6, max: 10)),
                Expanded(
                  child: Text(
                    activeTitle,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: GoogleFonts.robotoFlex(
                      fontSize: rs.font(12, min: 10.5, max: 14),
                      fontWeight: FontWeight.w700,
                      color: U.text,
                      letterSpacing: 0.1,
                    ),
                  ),
                ),
              ],
            ),
          ),
        );
      },
    );
  }
}

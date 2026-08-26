import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../../../providers/delve_theme_provider.dart';
import '../../../providers/delve_deck_provider.dart';
import '../../../providers/delve_inventory_provider.dart';
import '../../../providers/delve_session_provider.dart';
import '../../app_shell.dart';
import 'theme_selector.dart';

class ProfileScreen extends StatelessWidget {
  const ProfileScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final theme = context.watch<DelveThemeProvider>().currentTheme;
    final deckProvider = context.watch<DeckProvider>();
    final inventoryProvider = context.watch<InventoryProvider>();

    return SafeArea(
      child: SingleChildScrollView(
        padding: const EdgeInsets.only(bottom: 120),
        child: TweenAnimationBuilder<double>(
          tween: Tween(begin: 0.0, end: 1.0),
          duration: const Duration(milliseconds: 700),
          curve: Curves.easeOutCubic,
          builder: (context, value, child) {
            return Transform.translate(
              offset: Offset(0, 40 * (1 - value)),
              child: Opacity(
                opacity: value,
                child: child,
              ),
            );
          },
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Padding(
                padding: const EdgeInsets.all(24.0),
                child: Text(
                  'your aura',
                  style: TextStyle(
                    fontFamily: 'OrangeAvenue',
                    color: theme.text,
                    fontSize: 48,
                    letterSpacing: -0.4,
                    fontFeatures: const [
                      FontFeature.enable('liga'),
                      FontFeature.enable('dlig'),
                      FontFeature.enable('swsh'),
                    ],
                  ),
                ),
              ),
              
              // Progress Stats
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 24.0),
                child: Row(
                  children: [
                    Expanded(
                      child: _StatCard(
                        label: 'Decks Completed',
                        value: '${deckProvider.completedDecksCount}',
                      ),
                    ),
                    const SizedBox(width: 16),
                    Expanded(
                      child: _StatCard(
                        label: 'Words Learned',
                        value: '${inventoryProvider.archive.length}',
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 16),

              // Current Deck Status
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 24.0),
                child: Row(
                  children: [
                    Expanded(
                      child: _StatCard(
                        label: 'In Inventory',
                        value: '${inventoryProvider.inventory.length}',
                      ),
                    ),
                    const SizedBox(width: 16),
                    Expanded(
                      child: _StatCard(
                        label: 'Current Deck',
                        value: deckProvider.activeDeck != null
                            ? 'Day ${deckProvider.activeDeck!.currentDay}'
                            : '—',
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 16),
              if (deckProvider.activeDeck != null)
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 24.0),
                  child: Row(
                    children: [
                      Expanded(
                        child: OutlinedButton.icon(
                          onPressed: () => _showConfirmDialog(
                            context,
                            title: 'Restart Day 1?',
                            content: 'Your progress in this deck will be reset to the beginning. Your inventory remains safe.',
                            confirmLabel: 'Restart',
                            onConfirm: () {
                              context.read<DeckProvider>().resetDeckToDayOne();
                              context.read<SessionProvider>().endSession();
                            },
                          ),
                          icon: Icon(Icons.refresh_rounded, size: 16, color: theme.textSecondary),
                          label: Text('Restart to Day 1', style: TextStyle(color: theme.textSecondary, fontSize: 13)),
                          style: OutlinedButton.styleFrom(
                            side: BorderSide(color: theme.divider),
                            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                            padding: const EdgeInsets.symmetric(vertical: 12),
                          ),
                        ),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: OutlinedButton.icon(
                          onPressed: () => _showConfirmDialog(
                            context,
                            title: 'Abandon Deck?',
                            content: 'All progress for this deck will be lost. Words will return to your inventory.',
                            confirmLabel: 'Abandon',
                            isDestructive: true,
                            onConfirm: () => context.read<DeckProvider>().abandonDeck(),
                          ),
                          icon: const Icon(Icons.delete_outline_rounded, size: 16, color: Colors.redAccent),
                          label: const Text('Abandon Deck', style: TextStyle(color: Colors.redAccent, fontSize: 13)),
                          style: OutlinedButton.styleFrom(
                            side: BorderSide(color: Colors.redAccent.withValues(alpha: 0.3)),
                            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                            padding: const EdgeInsets.symmetric(vertical: 12),
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              if (deckProvider.activeDeck != null)
                const SizedBox(height: 32),
              
              const SizedBox(height: 16),
              
              // Appearance Section (Minimized & Animated)
              const _AppearanceSection(),
              
              const SizedBox(height: 32),

              // Account info (Moved to bottom)
              const _AccountSection(),
              
              const SizedBox(height: 48),
            ],
          ),
        ),
      ),
    );
  }

  void _showConfirmDialog(
    BuildContext context, {
    required String title,
    required String content,
    required String confirmLabel,
    required VoidCallback onConfirm,
    bool isDestructive = false,
  }) {
    final theme = context.read<DelveThemeProvider>().currentTheme;

    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        backgroundColor: theme.cardBackground,
        surfaceTintColor: Colors.transparent,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(28)),
        title: Text(
          title,
          style: GoogleFonts.marcellus(
            color: isDestructive ? Colors.redAccent : theme.text,
            fontSize: 24,
            fontWeight: FontWeight.w600,
          ),
        ),
        content: Text(
          content,
          style: GoogleFonts.inter(
            color: theme.textSecondary,
            fontSize: 15,
            height: 1.5,
          ),
        ),
        actionsPadding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: Text(
              'Cancel',
              style: GoogleFonts.inter(
                color: theme.textSecondary,
                fontWeight: FontWeight.w500,
              ),
            ),
          ),
          const SizedBox(width: 8),
          ElevatedButton(
            onPressed: () {
              Navigator.pop(context);
              onConfirm();
            },
            style: ElevatedButton.styleFrom(
              backgroundColor: isDestructive ? Colors.redAccent : theme.accent,
              foregroundColor: theme.isDark || isDestructive ? Colors.white : Colors.black,
              elevation: 0,
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
              padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 12),
            ),
            child: Text(
              confirmLabel,
              style: GoogleFonts.inter(
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _AppearanceSection extends StatefulWidget {
  const _AppearanceSection();

  @override
  State<_AppearanceSection> createState() => _AppearanceSectionState();
}

class _AppearanceSectionState extends State<_AppearanceSection> with SingleTickerProviderStateMixin {
  bool _isExpanded = false;

  @override
  Widget build(BuildContext context) {
    final theme = context.watch<DelveThemeProvider>().currentTheme;

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 24.0),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          GestureDetector(
            onTap: () => setState(() => _isExpanded = !_isExpanded),
            child: AnimatedContainer(
              duration: const Duration(milliseconds: 500),
              curve: Curves.easeInOutCubic,
              padding: const EdgeInsets.all(20),
              decoration: BoxDecoration(
                color: theme.cardBackground,
                borderRadius: BorderRadius.circular(20),
                border: Border.all(
                  color: _isExpanded ? theme.accent.withValues(alpha: 0.5) : theme.divider,
                  width: _isExpanded ? 1.5 : 1.0,
                ),
                boxShadow: _isExpanded ? [
                  BoxShadow(
                    color: theme.accent.withValues(alpha: 0.1),
                    blurRadius: 20,
                    spreadRadius: 2,
                  )
                ] : [],
              ),
              child: Row(
                children: [
                  Container(
                    width: 40,
                    height: 40,
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      color: theme.accent.withValues(alpha: 0.1),
                    ),
                    child: Icon(Icons.palette_rounded, color: theme.accent, size: 20),
                  ),
                  const SizedBox(width: 16),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'APPEARANCE',
                          style: GoogleFonts.marcellus(
                            color: theme.text,
                            fontSize: 16,
                            fontWeight: FontWeight.w600,
                            letterSpacing: 1.0,
                          ),
                        ),
                        Text(
                          _isExpanded ? 'Choose your botanical aura' : 'Customize themes and mode',
                          style: GoogleFonts.inter(
                            color: theme.textSecondary,
                            fontSize: 12,
                          ),
                        ),
                      ],
                    ),
                  ),
                  AnimatedRotation(
                    turns: _isExpanded ? 0.5 : 0,
                    duration: const Duration(milliseconds: 400),
                    child: Icon(Icons.expand_more_rounded, color: theme.textSecondary),
                  ),
                ],
              ),
            ),
          ),
          ClipRect(
            child: AnimatedAlign(
              alignment: Alignment.topCenter,
              duration: const Duration(milliseconds: 600),
              curve: Curves.easeInOutCubic,
              heightFactor: _isExpanded ? 1.0 : 0.0,
              child: AnimatedOpacity(
                duration: const Duration(milliseconds: 400),
                opacity: _isExpanded ? 1.0 : 0.0,
                child: const Padding(
                  padding: EdgeInsets.only(top: 24.0),
                  child: ThemeSelector(),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _AccountSection extends StatelessWidget {
  const _AccountSection();

  @override
  Widget build(BuildContext context) {
    final theme = context.watch<DelveThemeProvider>().currentTheme;
    final user = FirebaseAuth.instance.currentUser;
    final displayName = user?.displayName ?? 'User';
    final email = user?.email ?? 'anonymous';

    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 24.0),
          child: Row(
            children: [
              CircleAvatar(
                radius: 28,
                backgroundColor: theme.accent.withValues(alpha: 0.15),
                child: Text(
                  displayName.isNotEmpty
                      ? displayName[0].toUpperCase()
                      : 'U',
                  style: TextStyle(color: theme.accent, fontSize: 24, fontWeight: FontWeight.w600),
                ),
              ),
              const SizedBox(width: 16),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      displayName,
                      style: TextStyle(color: theme.text, fontSize: 18, fontWeight: FontWeight.w600),
                      overflow: TextOverflow.ellipsis,
                    ),
                    const SizedBox(height: 6),
                    Row(
                      children: [
                        Icon(
                          Icons.cloud_done_rounded,
                          size: 14,
                          color: theme.accent,
                        ),
                        const SizedBox(width: 6),
                        Text(
                          'Cloud Sync Active',
                          style: TextStyle(
                            color: theme.accent,
                            fontSize: 11,
                            fontWeight: FontWeight.w500,
                            letterSpacing: 0.2,
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: 16),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 24.0),
          child: SizedBox(
            width: double.infinity,
            child: OutlinedButton.icon(
              onPressed: () async {
                context.read<DeckProvider>().clearUserData();
                context.read<InventoryProvider>().clearUserData();
                AppShell.resetSession();
                final prefs = await SharedPreferences.getInstance();
                await prefs.remove('app_open_count');
                await prefs.remove('last_seen_popup_event_id');
                await FirebaseAuth.instance.signOut();
              },
              icon: Icon(Icons.logout_rounded, size: 18, color: theme.textSecondary),
              label: Text('Sign Out', style: TextStyle(color: theme.textSecondary)),
              style: OutlinedButton.styleFrom(
                side: BorderSide(color: theme.divider),
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
                padding: const EdgeInsets.symmetric(vertical: 14),
              ),
            ),
          ),
        ),
      ],
    );
  }
}

class _StatCard extends StatelessWidget {
  final String label;
  final String value;

  const _StatCard({required this.label, required this.value});

  @override
  Widget build(BuildContext context) {
    final theme = context.watch<DelveThemeProvider>().currentTheme;

    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: theme.cardBackground,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: theme.divider),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            value,
            style: GoogleFonts.marcellus(
              color: theme.text,
              fontSize: 34,
              fontWeight: FontWeight.w500,
            ),
          ),
          const SizedBox(height: 6),
          Text(
            label.toUpperCase(),
            style: GoogleFonts.inter(
              color: theme.textSecondary,
              fontSize: 10,
              fontWeight: FontWeight.w700,
              letterSpacing: 1.0,
            ),
          ),
        ],
      ),
    );
  }
}

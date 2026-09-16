import 'dart:async';
import 'package:flutter/material.dart';
import '../widgets/utopia_loader.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:firebase_auth/firebase_auth.dart';
import '../main.dart';
import '../models/university_model.dart';
import '../services/university_service.dart';
import '../services/cache_service.dart';

class UniversitySelectionScreen extends StatefulWidget {
  const UniversitySelectionScreen({super.key});

  @override
  State<UniversitySelectionScreen> createState() => _UniversitySelectionScreenState();
}

class _UniversitySelectionScreenState extends State<UniversitySelectionScreen> {
  final UniversityService _universityService = UniversityService();
  final TextEditingController _searchController = TextEditingController();
  StreamSubscription<List<UniversityModel>>? _uniSubscription;

  List<UniversityModel> _allUniversities = [];
  List<UniversityModel> _filteredUniversities = [];
  bool _isLoading = true;

  @override
  void initState() {
    super.initState();
    _subscribeToUniversities();
    _searchController.addListener(_onSearchChanged);
  }

  @override
  void dispose() {
    _uniSubscription?.cancel();
    _searchController.dispose();
    super.dispose();
  }

  void _subscribeToUniversities() {
    _uniSubscription?.cancel();
    _uniSubscription = _universityService.streamUniversities().listen(
      (unis) {
        debugPrint('UniversitySelectionScreen: Stream received ${unis.length} universities: ${unis.map((u) => u.name).toList()}');
        if (mounted) {
          setState(() {
            _allUniversities = unis..sort((a, b) => a.name.compareTo(b.name));
            _filteredUniversities = _filterList(_searchController.text);
            _isLoading = false;
          });
        }
      },
      onError: (e, stack) {
        debugPrint('UniversitySelectionScreen: Stream error: $e\n$stack');
        if (mounted) {
          setState(() => _isLoading = false);
        }
      },
    );
  }

  List<UniversityModel> _filterList(String query) {
    final q = query.trim().toLowerCase();
    if (q.isEmpty) return _allUniversities;
    return _allUniversities.where((u) {
      return u.name.toLowerCase().contains(q) ||
             u.shortName.toLowerCase().contains(q) ||
             u.id.toLowerCase().contains(q);
    }).toList();
  }

  void _onSearchChanged() {
    setState(() {
      _filteredUniversities = _filterList(_searchController.text);
    });
  }

  Future<void> _selectUniversity(UniversityModel uni) async {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) {
      return;
    }

    try {
      showAppLoading();
      await _universityService.setUserSelectedUniversity(
        user.uid,
        uni.id,
        universityName: uni.name,
      );
      
      // Cache the selected university locally
      await CacheService().saveAppSetting('cached_university_id', uni.id);
      await CacheService().saveAppSetting('cached_university_name', uni.name);
      U.cachedUniversityId = uni.id;
      U.cachedUniversityName = uni.name;
      
      if (mounted) {
        // Force full app restart by navigating to root and letting AuthGate rebuild
        Navigator.of(context).pushAndRemoveUntil(
          MaterialPageRoute(builder: (_) => const AuthGate()),
          (route) => false,
        );
      }
    } catch (e) {
      // Handle error
    } finally {
      hideAppLoading();
    }
  }

  @override
  Widget build(BuildContext context) {
    final canPop = Navigator.canPop(context) && U.cachedUniversityId.isNotEmpty;

    return PopScope(
      canPop: canPop,
      child: Scaffold(
        backgroundColor: U.bg,
        appBar: AppBar(
          backgroundColor: U.bg,
          elevation: 0,
          automaticallyImplyLeading: canPop,
          title: Text(
            'Select University',
            style: GoogleFonts.outfit(
              color: U.text,
              fontWeight: FontWeight.w600,
              fontSize: 24,
            ),
          ),
          centerTitle: false,
          iconTheme: IconThemeData(color: U.text),
          actions: [
            IconButton(
              icon: Icon(Icons.refresh_rounded, color: U.dim),
              tooltip: 'Refresh list',
              onPressed: () {
                setState(() => _isLoading = true);
                _subscribeToUniversities();
              },
            ),
            const SizedBox(width: 8),
          ],
        ),
        body: Column(
          children: [
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 8),
              child: TextField(
                controller: _searchController,
                style: GoogleFonts.outfit(color: U.text),
                decoration: InputDecoration(
                  hintText: 'Search universities...',
                  hintStyle: GoogleFonts.outfit(color: U.sub, fontSize: 14),
                  prefixIcon: Icon(Icons.search_rounded, color: U.sub, size: 20),
                  suffixIcon: _searchController.text.isNotEmpty
                      ? IconButton(
                          icon: Icon(Icons.close_rounded, color: U.dim, size: 18),
                          onPressed: () {
                            _searchController.clear();
                          },
                        )
                      : null,
                  filled: true,
                  fillColor: U.surface,
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(20),
                    borderSide: BorderSide.none,
                  ),
                  contentPadding: const EdgeInsets.symmetric(vertical: 0),
                ),
              ),
            ),
            const SizedBox(height: 12),
            Expanded(
              child: _isLoading
                  ? const Center(
                      child: UtopiaLoader(scale: 0.7),
                    )
                  : RefreshIndicator(
                      onRefresh: () async => _subscribeToUniversities(),
                      color: U.primary,
                      backgroundColor: U.surface,
                      child: _allUniversities.isEmpty
                          ? ListView(
                              children: [
                                SizedBox(
                                  height: MediaQuery.of(context).size.height * 0.45,
                                  child: Center(
                                    child: Padding(
                                      padding: const EdgeInsets.symmetric(horizontal: 32),
                                      child: Column(
                                        mainAxisSize: MainAxisSize.min,
                                        children: [
                                          Icon(
                                            Icons.school_outlined,
                                            size: 56,
                                            color: U.dim.withValues(alpha: 0.6),
                                          ),
                                          const SizedBox(height: 16),
                                          Text(
                                            'No universities listed yet',
                                            style: GoogleFonts.outfit(
                                              color: U.text,
                                              fontSize: 18,
                                              fontWeight: FontWeight.w600,
                                            ),
                                          ),
                                          const SizedBox(height: 8),
                                          Text(
                                            'Universities added to the system will appear here. Pull down to refresh.',
                                            textAlign: TextAlign.center,
                                            style: GoogleFonts.outfit(
                                              color: U.sub,
                                              fontSize: 14,
                                            ),
                                          ),
                                        ],
                                      ),
                                    ),
                                  ),
                                ),
                              ],
                            )
                          : _filteredUniversities.isEmpty
                              ? ListView(
                                  children: [
                                    SizedBox(
                                      height: MediaQuery.of(context).size.height * 0.45,
                                      child: Center(
                                        child: Padding(
                                          padding: const EdgeInsets.symmetric(horizontal: 32),
                                          child: Column(
                                            mainAxisSize: MainAxisSize.min,
                                            children: [
                                              Icon(
                                                Icons.search_off_rounded,
                                                size: 48,
                                                color: U.dim.withValues(alpha: 0.6),
                                              ),
                                              const SizedBox(height: 14),
                                              Text(
                                                'No results for "${_searchController.text.trim()}"',
                                                textAlign: TextAlign.center,
                                                style: GoogleFonts.outfit(
                                                  color: U.sub,
                                                  fontSize: 15,
                                                  fontWeight: FontWeight.w500,
                                                ),
                                              ),
                                            ],
                                          ),
                                        ),
                                      ),
                                    ),
                                  ],
                                )
                              : ListView.builder(
                                  physics: const AlwaysScrollableScrollPhysics(
                                    parent: BouncingScrollPhysics(),
                                  ),
                                  padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 12),
                                  itemCount: _filteredUniversities.length,
                                  itemBuilder: (context, index) {
                                    final uni = _filteredUniversities[index];
                                    final isSelected = uni.id == U.cachedUniversityId;

                                    return Padding(
                                      padding: const EdgeInsets.only(bottom: 16),
                                      child: InkWell(
                                        onTap: () => _selectUniversity(uni),
                                        borderRadius: BorderRadius.circular(16),
                                        child: Container(
                                          padding: const EdgeInsets.all(20),
                                          decoration: BoxDecoration(
                                            color: isSelected
                                                ? U.primary.withValues(alpha: 0.08)
                                                : U.surface,
                                            borderRadius: BorderRadius.circular(16),
                                            border: Border.all(
                                              color: isSelected
                                                  ? U.primary.withValues(alpha: 0.5)
                                                  : U.border.withValues(alpha: 0.5),
                                              width: isSelected ? 1.5 : 1.0,
                                            ),
                                          ),
                                          child: Row(
                                            children: [
                                              Container(
                                                width: 48,
                                                height: 48,
                                                decoration: BoxDecoration(
                                                  color: isSelected
                                                      ? U.primary.withValues(alpha: 0.15)
                                                      : U.bg,
                                                  borderRadius: BorderRadius.circular(12),
                                                ),
                                                child: Center(
                                                  child: Text(
                                                    uni.shortName.isNotEmpty
                                                        ? uni.shortName.substring(0, uni.shortName.length > 2 ? 2 : uni.shortName.length)
                                                        : 'U',
                                                    style: GoogleFonts.outfit(
                                                      color: U.primary,
                                                      fontWeight: FontWeight.w700,
                                                      fontSize: 16,
                                                    ),
                                                  ),
                                                ),
                                              ),
                                              const SizedBox(width: 16),
                                              Expanded(
                                                child: Column(
                                                  crossAxisAlignment: CrossAxisAlignment.start,
                                                  children: [
                                                    Text(
                                                      uni.name,
                                                      style: GoogleFonts.outfit(
                                                        color: U.text,
                                                        fontSize: 15,
                                                        fontWeight: FontWeight.w600,
                                                      ),
                                                    ),
                                                    if (uni.shortName.isNotEmpty) ...[
                                                      const SizedBox(height: 4),
                                                      Text(
                                                        uni.shortName,
                                                        style: GoogleFonts.outfit(
                                                          color: U.sub,
                                                          fontSize: 12,
                                                          fontWeight: FontWeight.w500,
                                                        ),
                                                      ),
                                                    ],
                                                  ],
                                                ),
                                              ),
                                              Icon(
                                                isSelected
                                                    ? Icons.check_circle_rounded
                                                    : Icons.chevron_right_rounded,
                                                color: isSelected ? U.primary : U.dim,
                                                size: 22,
                                              ),
                                            ],
                                          ),
                                        ),
                                      ),
                                    );
                                  },
                                ),
                    ),
            ),
          ],
        ),
      ),
    );
  }
}

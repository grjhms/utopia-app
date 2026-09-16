import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import '../main.dart';
import '../models/drive_notebook_model.dart';
import '../services/google_drive_service.dart';
import '../widgets/utopia_loader.dart';

class DriveFolderBrowserScreen extends StatefulWidget {
  final DriveNotebook notebook;
  final String? initialSubfolderId;
  final String? subfolderName;

  const DriveFolderBrowserScreen({
    super.key,
    required this.notebook,
    this.initialSubfolderId,
    this.subfolderName,
  });

  @override
  State<DriveFolderBrowserScreen> createState() => _DriveFolderBrowserScreenState();
}

class _DriveFolderBrowserScreenState extends State<DriveFolderBrowserScreen> {
  final GoogleDriveService _driveService = GoogleDriveService.instance;
  bool _isLoading = true;
  String? _errorMessage;
  List<DriveFileItem> _items = [];

  String get _currentFolderId =>
      widget.initialSubfolderId ?? widget.notebook.folderId;

  String get _title =>
      widget.subfolderName ?? widget.notebook.name;

  @override
  void initState() {
    super.initState();
    _loadContents();
  }

  Future<void> _loadContents() async {
    setState(() {
      _isLoading = true;
      _errorMessage = null;
    });

    try {
      final result = await _driveService.listFolderContents(_currentFolderId);
      if (mounted) {
        setState(() {
          _items = result.items;
          _isLoading = false;
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _errorMessage = e.toString().replaceAll('Exception: ', '').replaceAll('StateError: ', '');
          _isLoading = false;
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: U.bg,
      appBar: AppBar(
        backgroundColor: U.surfaceContainer,
        elevation: 0,
        title: Text(
          _title,
          style: GoogleFonts.outfit(
            color: U.text,
            fontSize: 18,
            fontWeight: FontWeight.w600,
          ),
        ),
        leading: IconButton(
          icon: Icon(Icons.arrow_back_ios_new_rounded, color: U.text, size: 20),
          onPressed: () => Navigator.pop(context),
        ),
      ),
      body: _isLoading
          ? const Center(child: UtopiaLoader(scale: 0.7))
          : _errorMessage != null
              ? Center(
                  child: Padding(
                    padding: const EdgeInsets.all(24),
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(Icons.error_outline_rounded, color: U.red, size: 40),
                        const SizedBox(height: 12),
                        Text(
                          _errorMessage!,
                          style: GoogleFonts.outfit(color: U.sub, fontSize: 14),
                          textAlign: TextAlign.center,
                        ),
                        const SizedBox(height: 16),
                        FilledButton(
                          onPressed: _loadContents,
                          child: const Text('Retry'),
                        ),
                      ],
                    ),
                  ),
                )
              : _items.isEmpty
                  ? Center(
                      child: Text(
                        'This folder is empty',
                        style: GoogleFonts.outfit(color: U.sub, fontSize: 15),
                      ),
                    )
                  : ListView.builder(
                      itemCount: _items.length,
                      itemBuilder: (context, i) {
                        final item = _items[i];
                        return ListTile(
                          leading: Icon(
                            item.isFolder ? Icons.folder_rounded : Icons.insert_drive_file_outlined,
                            color: U.primary,
                          ),
                          title: Text(item.name, style: GoogleFonts.outfit(color: U.text)),
                        );
                      },
                    ),
    );
  }
}

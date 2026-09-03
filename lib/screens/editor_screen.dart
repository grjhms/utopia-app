import 'dart:async';

import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

import '../main.dart';
import '../services/file_upload_service.dart';
import '../services/supabase_notes_service.dart';
import '../services/supabase_global_service.dart';
import '../widgets/utopia_loading_overlay.dart';
import '../services/ai_service.dart';
import 'appflowy_note_screen.dart';

// ─────────────────────────────────────────────────────────────
//  Block data model
// ─────────────────────────────────────────────────────────────

enum BlockType { text, qa, code, latex, table, mermaid, file }

class EditorBlock {
  final String id;
  BlockType type;

  // Text block
  String title;
  String body;

  // Q&A block
  String question;
  String answer;

  // Code block
  String codeLanguage;
  String codeContent;

  // LaTeX block
  String latexContent;

  // Table block
  int tableRows;
  int tableCols;
  List<List<String>> tableData;

  // Mermaid block
  String mermaidDirection; // TD, LR, RL, BT
  String mermaidContent;

  // File block
  String fileDisplayName;
  String fileUrl;

  EditorBlock({
    String? id,
    required this.type,
    this.title = '',
    this.body = '',
    this.question = '',
    this.answer = '',
    this.codeLanguage = '',
    this.codeContent = '',
    this.latexContent = '',
    this.tableRows = 2,
    this.tableCols = 2,
    List<List<String>>? tableData,
    this.mermaidDirection = 'TD',
    this.mermaidContent = '',
    this.fileDisplayName = '',
    this.fileUrl = '',
  })  : id = id ?? UniqueKey().toString(),
        tableData = tableData ??
            List.generate(2, (_) => List.generate(2, (_) => ''));

  /// Serialize this block to its markdown representation.
  String toMarkdown() {
    switch (type) {
      case BlockType.text:
        final buf = StringBuffer();
        if (title.trim().isNotEmpty) {
          buf.writeln('## ${title.trim()}');
          buf.writeln();
        }
        if (body.trim().isNotEmpty) {
          buf.writeln(body.trim());
        }
        return buf.toString().trimRight();

      case BlockType.qa:
        final encodedAnswer = Uri.encodeComponent(answer.trim());
        return '${question.trim()} [^Answer^](qa://$encodedAnswer)';

      case BlockType.code:
        final lang = codeLanguage.trim();
        final titleStr = title.trim().isNotEmpty ? '**${title.trim()}**\n\n' : '';
        return '$titleStr```$lang\n${codeContent.trimRight()}\n```';

      case BlockType.latex:
        return '\$\$\n${latexContent.trim()}\n\$\$';

      case BlockType.table:
        if (tableData.isEmpty || tableData[0].isEmpty) return '';
        final buf = StringBuffer();
        if (title.trim().isNotEmpty) {
          buf.writeln('**${title.trim()}**');
          buf.writeln();
        }
        // Header row
        buf.writeln(
            '| ${tableData[0].map((c) => c.isEmpty ? ' ' : c).join(' | ')} |');
        buf.writeln(
            '| ${tableData[0].map((_) => '---').join(' | ')} |');
        // Data rows
        for (int r = 1; r < tableData.length; r++) {
          buf.writeln(
              '| ${tableData[r].map((c) => c.isEmpty ? ' ' : c).join(' | ')} |');
        }
        return buf.toString().trimRight();

      case BlockType.mermaid:
        final dir = mermaidDirection.trim().isEmpty ? 'TD' : mermaidDirection.trim();
        return '```mermaid\ngraph $dir\n${mermaidContent.trim()}\n```';

      case BlockType.file:
        if (fileUrl.isEmpty) return '';
        return '[${fileDisplayName.trim().isEmpty ? 'File' : fileDisplayName.trim()}](${fileUrl.trim()})';
    }
  }
}

// ─────────────────────────────────────────────────────────────
//  Markdown → Blocks parser
// ─────────────────────────────────────────────────────────────

List<EditorBlock> parseMarkdownToBlocks(String markdown) {
  final blocks = <EditorBlock>[];
  final lines = markdown.split('\n');
  int i = 0;

  // Track grouped sections
  bool inFilesSection = false;

  while (i < lines.length) {
    final line = lines[i];
    final t = line.trim();

    // Skip empty lines between blocks
    if (t.isEmpty) {
      i++;
      continue;
    }

    // Detect section headings for Q&A and Files
    if (t == '# Questions' || t == '## Questions') {
      inFilesSection = false;
      i++;
      continue;
    }
    if (t == '# Files' || t == '## Files') {
      inFilesSection = true;
      i++;
      continue;
    }
    // New heading resets section context
    if (t.startsWith('#') && !t.startsWith('##')) {
      inFilesSection = false;
    }

    // ── Q&A legacy block: **Q:** ... **A:** ...
    if (t.startsWith('**Q:**')) {
      final question = t.replaceFirst('**Q:**', '').trim();
      String answer = '';
      i++;
      // Skip blanks
      while (i < lines.length && lines[i].trim().isEmpty) {
        i++;
      }
      if (i < lines.length && lines[i].trim().startsWith('**A:**')) {
        answer = lines[i].trim().replaceFirst('**A:**', '').trim();
        i++;
      }
      blocks.add(EditorBlock(type: BlockType.qa, question: question, answer: answer));
      continue;
    }

    // ── Q&A new inline block: Question [^Answer^](qa://encoded_answer)
    if (t.contains('[^Answer^](qa://')) {
      final qaIndex = t.indexOf('[^Answer^](qa://');
      if (qaIndex != -1) {
        var q = t.substring(0, qaIndex).trim();
        final rest = t.substring(qaIndex + '[^Answer^](qa://'.length);
        final closingParen = rest.indexOf(')');
        if (closingParen != -1) {
          final encodedVal = rest.substring(0, closingParen).trim();
          final a = Uri.decodeComponent(encodedVal);
          
          // NON-DESTRUCTIVE COMBINATION:
          // If the preceding block is a plain text block without a title,
          // we merge its body into this question to keep the full multi-line question!
          if (blocks.isNotEmpty && blocks.last.type == BlockType.text && blocks.last.title.isEmpty) {
            final prevBody = blocks.last.body.trim();
            if (prevBody.isNotEmpty) {
              q = '$prevBody\n$q';
              blocks.removeLast(); // remove the merged text block
            }
          }
          
          blocks.add(EditorBlock(type: BlockType.qa, question: q, answer: a));
          i++;
          continue;
        }
      }
    }

    // ── File link: [name](url) inside Files section or standalone file URL
    if (t.startsWith('[')) {
      final match = RegExp(r'^\[(.+?)\]\((.+?)\)$').firstMatch(t);
      if (match != null) {
        final url = match.group(2) ?? '';
        final isFile = inFilesSection ||
            url.toLowerCase().contains('.pdf') ||
            url.toLowerCase().contains('.docx') ||
            url.toLowerCase().contains('.doc') ||
            url.toLowerCase().contains('.xls') ||
            url.toLowerCase().contains('.xlsx') ||
            url.toLowerCase().contains('.zip') ||
            url.toLowerCase().contains('.png') ||
            url.toLowerCase().contains('.jpg') ||
            url.toLowerCase().contains('.jpeg') ||
            url.toLowerCase().contains('.gif') ||
            url.contains('/uploads/') ||
            url.contains('cloudinary');
        if (isFile) {
          blocks.add(EditorBlock(
            type: BlockType.file,
            fileDisplayName: match.group(1) ?? '',
            fileUrl: url,
          ));
          i++;
          continue;
        }
      }
    }

    // ── LaTeX block: $$ ... $$
    if (t == r'$$') {
      final latexLines = <String>[];
      i++;
      while (i < lines.length && lines[i].trim() != r'$$') {
        latexLines.add(lines[i]);
        i++;
      }
      if (i < lines.length) i++; // skip closing $$
      blocks.add(EditorBlock(type: BlockType.latex, latexContent: latexLines.join('\n').trim()));
      continue;
    }

    // ── Single-line LaTeX: $$...$$ on one line
    if (t.startsWith(r'$$') && t.endsWith(r'$$') && t.length > 4) {
      blocks.add(EditorBlock(type: BlockType.latex, latexContent: t.substring(2, t.length - 2).trim()));
      i++;
      continue;
    }

    // ── Mermaid block
    if (t == '```mermaid') {
      i++;
      String direction = 'TD';
      final mermaidLines = <String>[];
      bool firstContentLine = true;
      while (i < lines.length && lines[i].trim() != '```') {
        if (firstContentLine && lines[i].trim().startsWith('graph ')) {
          direction = lines[i].trim().replaceFirst('graph ', '').trim();
          firstContentLine = false;
        } else {
          mermaidLines.add(lines[i]);
          firstContentLine = false;
        }
        i++;
      }
      if (i < lines.length) i++; // skip closing ```
      blocks.add(EditorBlock(
        type: BlockType.mermaid,
        mermaidDirection: direction,
        mermaidContent: mermaidLines.join('\n').trim(),
      ));
      continue;
    }

    // ── Code block
    if (t.startsWith('```')) {
      final language = t.substring(3).trim();
      final codeLines = <String>[];
      i++;
      while (i < lines.length && lines[i].trim() != '```') {
        codeLines.add(lines[i]);
        i++;
      }
      if (i < lines.length) i++; // skip closing ```
      String extractedTitle = '';
      if (blocks.isNotEmpty && blocks.last.type == BlockType.text && blocks.last.title.isEmpty) {
        final lastBody = blocks.last.body.trim();
        if (lastBody.startsWith('**') && lastBody.endsWith('**') && !lastBody.substring(2, lastBody.length-2).contains('\n')) {
          extractedTitle = lastBody.substring(2, lastBody.length-2).trim();
          blocks.removeLast();
        }
      }
      blocks.add(EditorBlock(
        type: BlockType.code,
        title: extractedTitle,
        codeLanguage: language,
        codeContent: codeLines.join('\n'),
      ));
      continue;
    }

    // ── Table block
    if (t.startsWith('|') && t.endsWith('|')) {
      final tableLines = <String>[];
      while (i < lines.length && lines[i].trim().startsWith('|') && lines[i].trim().endsWith('|')) {
        tableLines.add(lines[i].trim());
        i++;
      }
      // Parse table
      if (tableLines.length >= 2) {
        // Filter out separator row
        final dataLines = tableLines.where((l) => !RegExp(r'^\|[\s\-:|]+\|$').hasMatch(l)).toList();
        final parsedRows = dataLines.map((l) {
          return l
              .substring(1, l.length - 1) // strip outer |
              .split('|')
              .map((c) => c.trim())
              .toList();
        }).toList();
        if (parsedRows.isNotEmpty) {
          final cols = parsedRows[0].length;
          String extractedTitle = '';
          if (blocks.isNotEmpty && blocks.last.type == BlockType.text && blocks.last.title.isEmpty) {
            final lastBody = blocks.last.body.trim();
            if (lastBody.startsWith('**') && lastBody.endsWith('**') && !lastBody.substring(2, lastBody.length-2).contains('\n')) {
              extractedTitle = lastBody.substring(2, lastBody.length-2).trim();
              blocks.removeLast();
            }
          }
          blocks.add(EditorBlock(
            type: BlockType.table,
            title: extractedTitle,
            tableRows: parsedRows.length,
            tableCols: cols,
            tableData: parsedRows,
          ));
        }
      }
      continue;
    }

    // ── Text block: heading + body or just body
    if (t.startsWith('## ') || t.startsWith('# ')) {
      final headingMatch = RegExp(r'^#{1,2}\s+(.*)$').firstMatch(t);
      final title = headingMatch?.group(1) ?? t;
      i++;
      final bodyLines = <String>[];
      while (i < lines.length) {
        final next = lines[i].trim();
        // Stop at next block-level element
        if (next.startsWith('#') ||
            next.startsWith('```') ||
            next == r'$$' ||
            (next.startsWith(r'$$') && next.endsWith(r'$$') && next.length > 4) ||
            next.startsWith('**Q:**') ||
            next.contains('[^Answer^](qa://') ||
            (next.startsWith('|') && next.endsWith('|'))) {
          break;
        }
        bodyLines.add(lines[i]);
        i++;
      }
      // Trim trailing empty lines
      while (bodyLines.isNotEmpty && bodyLines.last.trim().isEmpty) {
        bodyLines.removeLast();
      }
      blocks.add(EditorBlock(
        type: BlockType.text,
        title: title,
        body: bodyLines.join('\n').trim(),
      ));
      continue;
    }

    // ── Plain text (no heading) — collect consecutive non-special lines into one text block
    {
      final bodyLines = <String>[];
      while (i < lines.length) {
        final next = lines[i].trim();
        if (next.startsWith('#') ||
            next.startsWith('```') ||
            next == r'$$' ||
            (next.startsWith(r'$$') && next.endsWith(r'$$') && next.length > 4) ||
            next.startsWith('**Q:**') ||
            next.contains('[^Answer^](qa://') ||
            (next.startsWith('[') && RegExp(r'^\[.+?\]\(.+?\)$').hasMatch(next) && inFilesSection) ||
            (next.startsWith('|') && next.endsWith('|'))) {
          break;
        }
        bodyLines.add(lines[i]);
        i++;
      }
      while (bodyLines.isNotEmpty && bodyLines.last.trim().isEmpty) {
        bodyLines.removeLast();
      }
      if (bodyLines.isNotEmpty) {
        blocks.add(EditorBlock(
          type: BlockType.text,
          body: bodyLines.join('\n').trim(),
        ));
      }
    }
  }

  return blocks;
}

/// Serialize a list of blocks back to markdown.
String serializeBlocksToMarkdown(List<EditorBlock> blocks) {
  final parts = <String>[];

  for (final block in blocks) {
    final md = block.toMarkdown();
    if (md.isNotEmpty) {
      parts.add(md);
    }
  }

  return '${parts.join('\n\n')}\n';
}

// ─────────────────────────────────────────────────────────────
//  Editor Screen
// ─────────────────────────────────────────────────────────────

class EditorScreen extends StatefulWidget {
  final String title;
  final String filePath;
  final String initialContent;
  final String folderPath;
  final List<Map<String, dynamic>> notesInFolder;
  final bool useGlobalRepo;

  const EditorScreen({
    super.key,
    required this.title,
    required this.filePath,
    required this.initialContent,
    this.folderPath = '',
    this.notesInFolder = const [],
    this.useGlobalRepo = false,
  });

  @override
  State<EditorScreen> createState() => _EditorScreenState();
}

class _EditorScreenState extends State<EditorScreen> {
  late List<EditorBlock> _blocks;
  bool _saving = false;
  bool _hasChanges = false;
  TextEditingController? _activeFormatController;
  UndoHistoryController? _activeUndoController;

  // Undo stack for block deletion
  final List<(int, EditorBlock)> _undoStack = [];

  @override
  void initState() {
    super.initState();
    if (widget.initialContent.trim().isEmpty) {
      _blocks = [EditorBlock(type: BlockType.text)];
    } else {
      _blocks = parseMarkdownToBlocks(widget.initialContent);
      if (_blocks.isEmpty) {
        _blocks = [EditorBlock(type: BlockType.text)];
      }
    }
  }

  void _markChanged() {
    if (!_hasChanges) setState(() => _hasChanges = true);
  }

  void _handleFocusChange(bool hasFocus, TextEditingController controller, UndoHistoryController undoController) {
    if (hasFocus) {
      if (_activeFormatController != controller) {
        setState(() {
          _activeFormatController = controller;
          _activeUndoController = undoController;
        });
      }
    } else {
      if (_activeFormatController == controller) {
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (mounted && _activeFormatController == controller) {
            setState(() {
              _activeFormatController = null;
              _activeUndoController = null;
            });
          }
        });
      }
    }
  }

  void _applyMarkdown(String prefix, String suffix) {
    if (_activeFormatController == null) return;
    final act = _activeFormatController!;
    final text = act.text;
    final selection = act.selection;
    if (!selection.isValid) return;

    final start = selection.start;
    final end = selection.end;
    final selectedText = text.substring(start, end);

    final newText = text.substring(0, start) + prefix + selectedText + suffix + text.substring(end);
    act.value = TextEditingValue(
      text: newText,
      selection: TextSelection.collapsed(offset: start + prefix.length + selectedText.length),
    );
    _markChanged();
  }

  // ── Save ──
  Future<void> _save() async {
    if (!_hasChanges) return;
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) return;

    final content = serializeBlocksToMarkdown(_blocks);

    setState(() => _saving = true);
    final success = await _performBackgroundSave(content, user);

    if (mounted) {
      if (success) {
        setState(() => _saving = false);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Saved successfully!', style: GoogleFonts.outfit(color: U.getContrastColor(U.green))),
            backgroundColor: U.green,
          ),
        );
        Navigator.pop(context, content);
      } else {
        setState(() => _saving = false);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Failed to save correctly.', style: GoogleFonts.outfit(color: U.getContrastColor(U.red))),
            backgroundColor: U.red,
          ),
        );
      }
    }
  }

  Future<bool> _performBackgroundSave(String content, User user) async {
    try {
      final useGlobal = widget.useGlobalRepo || widget.filePath.contains('/Community/');
      final uid = user.uid;
      final name = user.displayName ?? 'UTOPIA user';

      if (useGlobal) {
        await SupabaseGlobalService.instance.updateNote(
          widget.filePath,
          content,
          uid,
          name,
        );
      } else {
        await SupabaseNotesService().updateNote(
          widget.filePath,
          content,
          uid,
          name,
        );
      }
      return true;
    } catch (e) {
      debugPrint('EditorScreen: save failed: $e');
      return false;
    }
  }

  // ── Add block ──
  void _showAddBlockSheet() {
    showModalBottomSheet(
      context: context,
      backgroundColor: U.surface,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (ctx) => SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(20, 16, 20, 24),
          child: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Center(
                child: Container(
                  width: 36, height: 4,
                  decoration: BoxDecoration(
                    color: U.border,
                    borderRadius: BorderRadius.circular(2),
                  ),
                ),
              ),
              const SizedBox(height: 16),
              Text(
                'Add Block',
                style: GoogleFonts.outfit(
                  color: U.text,
                  fontSize: 17,
                  fontWeight: FontWeight.w700,
                ),
              ),
              const SizedBox(height: 16),
              _blockTypeItem(Icons.text_fields_outlined, 'Text', 'Title + description', BlockType.text, ctx),
              _blockTypeItem(Icons.quiz_outlined, 'Question & Answer', 'Q&A format', BlockType.qa, ctx),
              _blockTypeItem(Icons.code_outlined, 'Code Block', 'Syntax highlighted', BlockType.code, ctx),
              _blockTypeItem(Icons.functions_outlined, 'LaTeX', 'Math equations', BlockType.latex, ctx),
              _blockTypeItem(Icons.table_chart_outlined, 'Table', 'Rows & columns', BlockType.table, ctx),
              _blockTypeItem(Icons.account_tree_outlined, 'Flow Chart', 'Mermaid diagram', BlockType.mermaid, ctx),
              _blockTypeItem(Icons.upload_file_outlined, 'Upload File', 'PDF, docs (≤9 MB)', BlockType.file, ctx),
            ],
          ),
        ),
        ),
      ),
    );
  }

  Widget _blockTypeItem(IconData icon, String label, String sub, BlockType type, BuildContext ctx) {
    return InkWell(
      onTap: () {
        Navigator.pop(ctx);
        _addBlock(type);
      },
      borderRadius: BorderRadius.circular(12),
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 10, horizontal: 4),
        child: Row(
          children: [
            Container(
              width: 36, height: 36,
              decoration: BoxDecoration(
                color: U.primary.withValues(alpha: 0.08),
                borderRadius: BorderRadius.circular(10),
              ),
              child: Icon(icon, color: U.primary, size: 18),
            ),
            const SizedBox(width: 14),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(label, style: GoogleFonts.outfit(color: U.text, fontSize: 14, fontWeight: FontWeight.w600)),
                  Text(sub, style: GoogleFonts.outfit(color: U.dim, fontSize: 11)),
                ],
              ),
            ),
            Icon(Icons.add_rounded, color: U.dim, size: 18),
          ],
        ),
      ),
    );
  }

  void _addBlock(BlockType type) {
    if (type == BlockType.file) {
      _handleFileUpload();
      return;
    }
    setState(() {
      _blocks.add(EditorBlock(type: type));
      _hasChanges = true;
    });
  }

  // ── File upload ──
  Future<void> _handleFileUpload() async {
    final service = FileUploadService();
    try {
      final picked = await service.pickFile();
      if (picked == null) return;

      final (file, originalName) = picked;

      // Ask for display name
      final displayName = await _askDisplayName(originalName);
      if (displayName == null || displayName.trim().isEmpty) return;

      // Show uploading indicator
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Row(
            children: [
              SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2, color: U.getContrastColor(U.primary))),
              const SizedBox(width: 12),
              Text('Uploading $displayName...', style: GoogleFonts.outfit(color: U.getContrastColor(U.primary))),
            ],
          ),
          backgroundColor: U.primary,
          duration: const Duration(seconds: 30),
        ),
      );

      // Extract university ID from file path
      final universityId = widget.filePath.split('/').first;

      final downloadUrl = await service.uploadFile(
        file: file,
        originalFilename: originalName,
        universityId: universityId,
      );

      if (!mounted) return;
      ScaffoldMessenger.of(context).clearSnackBars();

      setState(() {
        _blocks.add(EditorBlock(
          type: BlockType.file,
          fileDisplayName: displayName,
          fileUrl: downloadUrl,
        ));
        _hasChanges = true;
      });

      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('File uploaded!', style: GoogleFonts.outfit(color: U.getContrastColor(U.green))),
          backgroundColor: U.green,
          duration: const Duration(seconds: 2),
        ),
      );
    } on FileUploadException catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).clearSnackBars();
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(e.message, style: GoogleFonts.outfit(color: U.getContrastColor(U.red))),
          backgroundColor: U.red,
        ),
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).clearSnackBars();
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Upload failed: $e', style: GoogleFonts.outfit(color: U.getContrastColor(U.red))),
          backgroundColor: U.red,
        ),
      );
    }
  }

  Future<String?> _askDisplayName(String defaultName) async {
    final controller = TextEditingController(text: defaultName.replaceAll(RegExp(r'\.[^.]+$'), ''));
    return showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: U.card,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: Text('File Name', style: GoogleFonts.outfit(color: U.text, fontWeight: FontWeight.w600)),
        content: TextField(
          controller: controller,
          autofocus: true,
          style: GoogleFonts.outfit(color: U.text, fontSize: 15),
          decoration: InputDecoration(
            hintText: 'Display name for this file',
            hintStyle: GoogleFonts.outfit(color: U.dim),
            filled: true,
            fillColor: U.bg,
            border: OutlineInputBorder(borderRadius: BorderRadius.circular(10), borderSide: BorderSide(color: U.border)),
            enabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(10), borderSide: BorderSide(color: U.border)),
            focusedBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(10), borderSide: BorderSide(color: U.primary)),
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: Text('Cancel', style: GoogleFonts.outfit(color: U.sub)),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, controller.text),
            style: FilledButton.styleFrom(
              backgroundColor: U.primary,
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
            ),
            child: Text('Set', style: GoogleFonts.outfit(fontWeight: FontWeight.w600)),
          ),
        ],
      ),
    );
  }

  // ── Delete block with undo ──
  void _deleteBlock(int index) {
    final removed = _blocks[index];
    final removedIndex = index;
    setState(() {
      _blocks.removeAt(index);
      _hasChanges = true;
    });
    final snackBarTextColor = U.getContrastColor(U.surface);
    final isSurfaceLight = ThemeData.estimateBrightnessForColor(U.surface) == Brightness.light;
    final isPrimaryLight = ThemeData.estimateBrightnessForColor(U.primary) == Brightness.light;
    final actionColor = (isSurfaceLight && isPrimaryLight) ? const Color(0xFF0C7A65) : U.primary;

    ScaffoldMessenger.of(context).clearSnackBars();
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text('Block deleted', style: GoogleFonts.outfit(color: snackBarTextColor)),
        backgroundColor: U.surface,
        action: SnackBarAction(
          label: 'Undo',
          textColor: actionColor,
          onPressed: () {
            if (_undoStack.isNotEmpty) {
              final (idx, block) = _undoStack.removeLast();
              setState(() {
                _blocks.insert(idx.clamp(0, _blocks.length), block);
              });
            }
          },
        ),
        duration: const Duration(seconds: 4),
      ),
    );
  }

  // ── Build block card ──
  Widget _buildBlockCard(int index) {
    final block = _blocks[index];
    return Container(
      key: ValueKey(block.id),
      margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
      decoration: BoxDecoration(
        color: U.card,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: U.border, width: 0.5),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // ── Block header with drag handle, type label, delete ──
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
            decoration: BoxDecoration(
              color: U.surface,
              borderRadius: const BorderRadius.vertical(top: Radius.circular(16)),
            ),
            child: Row(
              children: [
                ReorderableDragStartListener(
                  index: index,
                  child: Icon(Icons.drag_indicator_outlined, color: U.dim, size: 18),
                ),
                const SizedBox(width: 8),
                Icon(_iconForType(block.type), color: U.primary, size: 16),
                const SizedBox(width: 6),
                Text(
                  _labelForBlock(index, block),
                  style: GoogleFonts.outfit(color: U.sub, fontSize: 11, fontWeight: FontWeight.w600, letterSpacing: 0.5),
                ),
                const Spacer(),
                GestureDetector(
                  onTap: () => _deleteBlock(index),
                  child: Padding(
                    padding: const EdgeInsets.all(4),
                    child: Icon(Icons.close_rounded, color: U.dim, size: 16),
                  ),
                ),
              ],
            ),
          ),
          // ── Block body ──
          Padding(
            padding: const EdgeInsets.fromLTRB(14, 10, 14, 14),
            child: _buildBlockBody(block),
          ),
        ],
      ),
    );
  }

  IconData _iconForType(BlockType type) {
    switch (type) {
      case BlockType.text: return Icons.text_fields_outlined;
      case BlockType.qa: return Icons.quiz_outlined;
      case BlockType.code: return Icons.code_outlined;
      case BlockType.latex: return Icons.functions_outlined;
      case BlockType.table: return Icons.table_chart_outlined;
      case BlockType.mermaid: return Icons.account_tree_outlined;
      case BlockType.file: return Icons.attach_file_outlined;
    }
  }

  String _labelForType(BlockType type) {
    switch (type) {
      case BlockType.text: return 'TEXT';
      case BlockType.qa: return 'Q & A';
      case BlockType.code: return 'CODE';
      case BlockType.latex: return 'LATEX';
      case BlockType.table: return 'TABLE';
      case BlockType.mermaid: return 'FLOW CHART';
      case BlockType.file: return 'FILE';
    }
  }

  String _labelForBlock(int index, EditorBlock block) {
    if (block.type == BlockType.qa) {
      int qaCount = 1;
      for (int i = 0; i < index; i++) {
        if (_blocks[i].type == BlockType.qa) {
          qaCount++;
        }
      }
      return 'QUESTION #$qaCount';
    }
    return _labelForType(block.type);
  }

  Widget _buildBlockBody(EditorBlock block) {
    switch (block.type) {
      case BlockType.text:
        return _TextBlockBody(block: block, onChanged: _markChanged, onFocus: _handleFocusChange);
      case BlockType.qa:
        return _QABlockBody(block: block, onChanged: _markChanged, onFocus: _handleFocusChange);
      case BlockType.code:
        return _CodeBlockBody(block: block, onChanged: _markChanged);
      case BlockType.latex:
        return _LatexBlockBody(block: block, onChanged: _markChanged);
      case BlockType.table:
        return _TableBlockBody(block: block, onChanged: () { _markChanged(); setState(() {}); });
      case BlockType.mermaid:
        return _MermaidBlockBody(block: block, onChanged: _markChanged);
      case BlockType.file:
        return _FileBlockBody(block: block, onRenamed: () => setState(() => _hasChanges = true));
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: U.bg,
      appBar: AppBar(
        backgroundColor: U.surface,
        foregroundColor: U.text,
        leading: IconButton(
          icon: const Icon(Icons.arrow_back),
          onPressed: () {
            if (_hasChanges) {
              showDialog(
                context: context,
                builder: (_) => AlertDialog(
                  backgroundColor: U.card,
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
                  title: Text('Unsaved changes', style: GoogleFonts.outfit(color: U.text, fontWeight: FontWeight.w600)),
                  content: Text('Leave without saving?', style: GoogleFonts.outfit(color: U.sub)),
                  actions: [
                    TextButton(
                      onPressed: () => Navigator.pop(context),
                      child: Text('Stay', style: GoogleFonts.outfit(color: U.primary)),
                    ),
                    TextButton(
                      onPressed: () {
                        Navigator.pop(context);
                        Navigator.pop(context);
                      },
                      child: Text('Leave', style: GoogleFonts.outfit(color: U.red)),
                    ),
                  ],
                ),
              );
            } else {
              Navigator.pop(context);
            }
          },
        ),
        title: Text(
          widget.title,
          style: GoogleFonts.outfit(color: U.text, fontWeight: FontWeight.w600, fontSize: 16),
        ),
        actions: [
          if (_hasChanges)
            Padding(
              padding: const EdgeInsets.only(right: 8),
              child: FilledButton.icon(
                onPressed: _saving ? null : _save,
                icon: const Icon(Icons.check_rounded, size: 18),
                label: Text('Save', style: GoogleFonts.outfit()),
                style: FilledButton.styleFrom(
                  backgroundColor: U.green,
                  foregroundColor: U.bg,
                ),
              ),
            ),
        ],
      ),
      body: Stack(
        children: [
          GestureDetector(
            behavior: HitTestBehavior.translucent,
            onTap: () => FocusScope.of(context).unfocus(),
            child: Column(
              children: [
                Expanded(
                  child: _blocks.isEmpty
                      ? Center(
                          child: Column(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Icon(Icons.edit_note_outlined, color: U.dim, size: 48),
                              const SizedBox(height: 12),
                              Text('No blocks yet', style: GoogleFonts.outfit(color: U.dim, fontSize: 14)),
                              const SizedBox(height: 8),
                              Text('Tap + to add content', style: GoogleFonts.outfit(color: U.dim, fontSize: 12)),
                            ],
                          ),
                        )
                      : ReorderableListView.builder(
                          padding: const EdgeInsets.only(top: 12, bottom: 100),
                          itemCount: _blocks.length,
                          onReorder: (oldIndex, newIndex) {
                            setState(() {
                              if (newIndex > oldIndex) newIndex--;
                              final block = _blocks.removeAt(oldIndex);
                              _blocks.insert(newIndex, block);
                              _hasChanges = true;
                            });
                          },
                          proxyDecorator: (child, index, animation) {
                            return AnimatedBuilder(
                              animation: animation,
                              builder: (ctx, child) => Material(
                                color: Colors.transparent,
                                elevation: 6,
                                shadowColor: Colors.black45,
                                borderRadius: BorderRadius.circular(16),
                                child: child,
                              ),
                              child: child,
                            );
                          },
                          itemBuilder: (context, index) => _buildBlockCard(index),
                        ),
                ),
                if (_activeFormatController != null) _buildMarkdownToolbar(),
              ],
            ),
          ),
          if (_saving) const UtopiaLoadingOverlay(),
        ],
      ),
      floatingActionButton: _activeFormatController != null
          ? null
          : FloatingActionButton(
              onPressed: _showAddBlockSheet,
              backgroundColor: U.primary,
              foregroundColor: U.getContrastColor(U.primary),
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
              child: const Icon(Icons.add_rounded),
            ),
    );
  }

  Widget _buildMarkdownToolbar() {
    return Container(
      height: 48,
      decoration: BoxDecoration(
        color: U.surface,
        border: Border(top: BorderSide(color: U.border, width: 0.5)),
      ),
      child: ListView(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.symmetric(horizontal: 8),
        children: [
          _toolbarButton(Icons.undo_rounded, () => _activeUndoController?.undo(), tooltip: 'Undo'),
          _toolbarButton(Icons.redo_rounded, () => _activeUndoController?.redo(), tooltip: 'Redo'),
          Container(width: 1, height: 24, color: U.border, margin: const EdgeInsets.symmetric(horizontal: 4)),
          _toolbarButton(Icons.format_bold, () => _applyMarkdown('**', '**')),
          _toolbarButton(Icons.format_italic, () => _applyMarkdown('*', '*')),
          _toolbarButton(Icons.link, () => _applyMarkdown('[', '](url)')),
          _toolbarButton(Icons.highlight, () => _applyMarkdown('==', '==')),
          _toolbarButton(Icons.format_strikethrough, () => _applyMarkdown('~~', '~~')),
          _toolbarButton(Icons.functions, () => _applyMarkdown(r'$', r'$')), // single $ for inline latex
          Container(width: 1, height: 24, color: U.border, margin: const EdgeInsets.symmetric(horizontal: 4)),
          _toolbarTextButton('H1', () => _applyMarkdown('## ', '')),
          _toolbarTextButton('H2', () => _applyMarkdown('### ', '')),
          _toolbarTextButton('H3', () => _applyMarkdown('#### ', '')),
        ],
      ),
    );
  }

  Widget _toolbarTextButton(String label, VoidCallback onPressed) {
    return InkWell(
      onTap: onPressed,
      borderRadius: BorderRadius.circular(8),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 8),
        alignment: Alignment.center,
        child: Text(
          label,
          style: GoogleFonts.outfit(
            color: U.text,
            fontWeight: FontWeight.w700,
            fontSize: 13,
          ),
        ),
      ),
    );
  }

  Widget _toolbarButton(IconData icon, VoidCallback onPressed, {String tooltip = 'Format'}) {
    return IconButton(
      icon: Icon(icon, color: U.text, size: 20),
      onPressed: onPressed,
      tooltip: tooltip,
      splashRadius: 20,
    );
  }
}

// ─────────────────────────────────────────────────────────────
//  Block Body Widgets
// ─────────────────────────────────────────────────────────────

class MarkdownTextEditingController extends TextEditingController {
  MarkdownTextEditingController({super.text});

  @override
  TextSpan buildTextSpan({required BuildContext context, TextStyle? style, required bool withComposing}) {
    final TextStyle defaultStyle = style ?? const TextStyle();
    final List<TextSpan> spans = [];

    final RegExp exp = RegExp(
      r'(\*\*[^*]+\*\*)|' // 1. bold
      r'(\*[^*]+\*)|'     // 2. italic
      r'(==[^=]+==)|'     // 3. highlight
      r'(~~[^~]+~~)|'     // 4. strikethrough
      r'(\[[^\]]+\]\([^)]+\))|' // 5. link
      r'(\$[^\$]+\$)|'     // 6. single latex
      r'(^#{2,4}\s[^\n]*)', // 7. Headings
      multiLine: true,
    );

    int start = 0;
    for (final match in exp.allMatches(text)) {
      if (match.start > start) {
        spans.add(TextSpan(text: text.substring(start, match.start), style: defaultStyle));
      }

      final String matchText = match.group(0)!;
      final bool isActive = selection.isValid && selection.baseOffset >= match.start && selection.baseOffset <= match.end;

      final Color markerColor = U.dim.withValues(alpha: 0.5);
      final TextStyle visibleMarker = defaultStyle.copyWith(color: markerColor);
      final TextStyle hiddenMarker = defaultStyle.copyWith(color: Colors.transparent, fontSize: 0.01);
      final TextStyle tagStyle = isActive ? visibleMarker : hiddenMarker;

      if (match.group(1) != null) { // Bold
        spans.add(TextSpan(children: [
          TextSpan(text: '**', style: tagStyle),
          TextSpan(text: matchText.substring(2, matchText.length - 2), style: defaultStyle.copyWith(fontWeight: FontWeight.w800)),
          TextSpan(text: '**', style: tagStyle),
        ]));
      } else if (match.group(2) != null) { // Italic
        spans.add(TextSpan(children: [
          TextSpan(text: '*', style: tagStyle),
          TextSpan(text: matchText.substring(1, matchText.length - 1), style: defaultStyle.copyWith(fontStyle: FontStyle.italic)),
          TextSpan(text: '*', style: tagStyle),
        ]));
      } else if (match.group(3) != null) { // Highlight
        spans.add(TextSpan(children: [
          TextSpan(text: '==', style: tagStyle),
          TextSpan(text: matchText.substring(2, matchText.length - 2), style: defaultStyle.copyWith(backgroundColor: Colors.amber.withValues(alpha: 0.2))),
          TextSpan(text: '==', style: tagStyle),
        ]));
      } else if (match.group(4) != null) { // Strikethrough
        spans.add(TextSpan(children: [
          TextSpan(text: '~~', style: tagStyle),
          TextSpan(text: matchText.substring(2, matchText.length - 2), style: defaultStyle.copyWith(decoration: TextDecoration.lineThrough)),
          TextSpan(text: '~~', style: tagStyle),
        ]));
      } else if (match.group(5) != null) { // Link
        final int cbClose = matchText.indexOf(']');
        final int pbOpen = matchText.indexOf('(');
        if (cbClose > 1 && pbOpen == cbClose + 1) {
          spans.add(TextSpan(children: [
            TextSpan(text: '[', style: tagStyle),
            TextSpan(text: matchText.substring(1, cbClose), style: defaultStyle.copyWith(color: U.primary, decoration: TextDecoration.underline)),
            TextSpan(text: ']', style: tagStyle),
            TextSpan(text: matchText.substring(pbOpen), style: isActive ? visibleMarker.copyWith(fontSize: (defaultStyle.fontSize ?? 14) * 0.8) : hiddenMarker),
          ]));
        } else {
          spans.add(TextSpan(text: matchText, style: defaultStyle));
        }
      } else if (match.group(6) != null) { // Latex
        spans.add(TextSpan(children: [
          TextSpan(text: r'$', style: tagStyle),
          TextSpan(text: matchText.substring(1, matchText.length - 1), style: defaultStyle.copyWith(fontFamily: 'Courier', color: U.green)),
          TextSpan(text: r'$', style: tagStyle),
        ]));
      } else if (match.group(7) != null) { // Headings (##, ###, ####)
        final int hashCount = matchText.indexOf(' ');
        final String hashTags = matchText.substring(0, hashCount + 1);
        final String content = matchText.substring(hashCount + 1);
        
        double fontSize = defaultStyle.fontSize ?? 14;
        if (hashCount == 2) {
          fontSize *= 1.4; // H2 (Shown as H1)
        } else if (hashCount == 3) {
          fontSize *= 1.2; // H3 (Shown as H2)
        } else if (hashCount == 4) {
          fontSize *= 1.1; // H4 (Shown as H3)
        }

        spans.add(TextSpan(children: [
          TextSpan(text: hashTags, style: tagStyle.copyWith(fontSize: fontSize)),
          TextSpan(text: content, style: defaultStyle.copyWith(fontWeight: FontWeight.w700, fontSize: fontSize)),
        ]));
      } else {
        spans.add(TextSpan(text: matchText, style: defaultStyle));
      }
      start = match.end;
    }

    if (start < text.length) {
      spans.add(TextSpan(text: text.substring(start), style: defaultStyle));
    }

    return TextSpan(style: style, children: spans);
  }
}

/// Shared input decoration for block fields.
InputDecoration _blockInputDecor(String hint, {bool dense = false}) {
  return InputDecoration(
    hintText: hint,
    hintStyle: GoogleFonts.outfit(color: U.dim, fontSize: 13),
    filled: true,
    fillColor: U.bg,
    isDense: dense,
    contentPadding: EdgeInsets.symmetric(horizontal: 12, vertical: dense ? 8 : 12),
    border: OutlineInputBorder(borderRadius: BorderRadius.circular(10), borderSide: BorderSide(color: U.border)),
    enabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(10), borderSide: BorderSide(color: U.border)),
    focusedBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(10), borderSide: BorderSide(color: U.primary, width: 1.2)),
  );
}

// ── Text Block ──
class _TextBlockBody extends StatefulWidget {
  final EditorBlock block;
  final VoidCallback onChanged;
  final void Function(bool, TextEditingController, UndoHistoryController)? onFocus;
  const _TextBlockBody({required this.block, required this.onChanged, this.onFocus});

  @override
  State<_TextBlockBody> createState() => _TextBlockBodyState();
}

class _TextBlockBodyState extends State<_TextBlockBody> {
  late TextEditingController _titleController;
  late TextEditingController _bodyController;
  late UndoHistoryController _titleUndoController;
  late UndoHistoryController _bodyUndoController;
  late FocusNode _titleFocus;
  late FocusNode _bodyFocus;

  @override
  void initState() {
    super.initState();
    _titleController = TextEditingController(text: widget.block.title);
    _bodyController = MarkdownTextEditingController(text: widget.block.body);
    _titleUndoController = UndoHistoryController();
    _bodyUndoController = UndoHistoryController();
    _titleFocus = FocusNode()..addListener(_handleTitleFocus);
    _bodyFocus = FocusNode()..addListener(_handleBodyFocus);
  }

  void _handleTitleFocus() => widget.onFocus?.call(_titleFocus.hasFocus, _titleController, _titleUndoController);
  void _handleBodyFocus() => widget.onFocus?.call(_bodyFocus.hasFocus, _bodyController, _bodyUndoController);

  @override
  void didUpdateWidget(covariant _TextBlockBody oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.block != widget.block) {
      if (_titleController.text != widget.block.title) {
        _titleController.text = widget.block.title;
      }
      if (_bodyController.text != widget.block.body) {
        _bodyController.text = widget.block.body;
      }
    }
  }

  @override
  void dispose() {
    _titleFocus.removeListener(_handleTitleFocus);
    _bodyFocus.removeListener(_handleBodyFocus);
    _titleController.dispose();
    _bodyController.dispose();
    _titleUndoController.dispose();
    _bodyUndoController.dispose();
    _titleFocus.dispose();
    _bodyFocus.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        TextField(
          controller: _titleController,
          undoController: _titleUndoController,
          focusNode: _titleFocus,
          onChanged: (v) { widget.block.title = v; widget.onChanged(); },
          style: GoogleFonts.outfit(color: U.text, fontSize: 15, fontWeight: FontWeight.w600),
          decoration: _blockInputDecor('Title (heading)', dense: true),
        ),
        const SizedBox(height: 8),
        TextField(
          controller: _bodyController,
          undoController: _bodyUndoController,
          focusNode: _bodyFocus,
          onChanged: (v) { widget.block.body = v; widget.onChanged(); },
          maxLines: null,
          minLines: 3,
          style: GoogleFonts.outfit(color: U.text, fontSize: 14, height: 1.5),
          decoration: _blockInputDecor('Write your content here...'),
        ),
      ],
    );
  }
}

// ── Q&A Block ──
class _QABlockBody extends StatefulWidget {
  final EditorBlock block;
  final VoidCallback onChanged;
  final void Function(bool, TextEditingController, UndoHistoryController)? onFocus;
  const _QABlockBody({required this.block, required this.onChanged, this.onFocus});

  @override
  State<_QABlockBody> createState() => _QABlockBodyState();
}

class _QABlockBodyState extends State<_QABlockBody> {
  late TextEditingController _qController;
  late TextEditingController _aController;
  late UndoHistoryController _qUndoController;
  late UndoHistoryController _aUndoController;
  late FocusNode _qFocus;
  late FocusNode _aFocus;
  bool _isGenerating = false;

  @override
  void initState() {
    super.initState();
    _qController = MarkdownTextEditingController(text: widget.block.question);
    _aController = MarkdownTextEditingController(text: widget.block.answer);
    _qUndoController = UndoHistoryController();
    _aUndoController = UndoHistoryController();
    _qFocus = FocusNode()..addListener(_handleQFocus);
    _aFocus = FocusNode()..addListener(_handleAFocus);
  }

  void _handleQFocus() => widget.onFocus?.call(_qFocus.hasFocus, _qController, _qUndoController);
  void _handleAFocus() => widget.onFocus?.call(_aFocus.hasFocus, _aController, _aUndoController);

  @override
  void didUpdateWidget(covariant _QABlockBody oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.block != widget.block) {
      if (_qController.text != widget.block.question) {
        _qController.text = widget.block.question;
      }
      if (_aController.text != widget.block.answer) {
        _aController.text = widget.block.answer;
      }
    }
  }

  @override
  void dispose() {
    _qFocus.removeListener(_handleQFocus);
    _aFocus.removeListener(_handleAFocus);
    _qController.dispose();
    _aController.dispose();
    _qUndoController.dispose();
    _aUndoController.dispose();
    _qFocus.dispose();
    _aFocus.dispose();
    super.dispose();
  }

  Future<void> _letLunaAnswer() async {
    final question = _qController.text.trim();
    if (question.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            'Please type a question first, bro! 🧠',
            style: GoogleFonts.outfit(color: U.getContrastColor(U.red)),
          ),
          backgroundColor: U.red,
        ),
      );
      return;
    }

    setState(() => _isGenerating = true);

    try {
      final prompt = 'Answer this academic question in neat, simple language (8M style direct answer, no fluff, concise ELIF5-style explanation, clear formatting): $question';
      final response = await AIService.sendMessage(userMessage: prompt);

      if (mounted) {
        setState(() {
          _aController.text = response;
          widget.block.answer = response;
          _isGenerating = false;
        });
        widget.onChanged();
      }
    } catch (e) {
      if (mounted) {
        setState(() => _isGenerating = false);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              'Failed to fetch answer from Luna: $e',
              style: GoogleFonts.outfit(color: U.getContrastColor(U.red)),
            ),
            backgroundColor: U.red,
          ),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        TextField(
          controller: _qController,
          undoController: _qUndoController,
          focusNode: _qFocus,
          onChanged: (v) { widget.block.question = v; widget.onChanged(); },
          maxLines: null,
          style: GoogleFonts.outfit(color: U.text, fontSize: 14, fontWeight: FontWeight.w600),
          decoration: _blockInputDecor('Question'),
        ),
        const SizedBox(height: 8),
        Stack(
          alignment: Alignment.center,
          children: [
            TextField(
              controller: _aController,
              undoController: _aUndoController,
              focusNode: _aFocus,
              onChanged: (v) { widget.block.answer = v; widget.onChanged(); },
              maxLines: null,
              minLines: 3,
              style: GoogleFonts.outfit(
                color: _isGenerating ? U.text.withValues(alpha: 0.4) : U.text,
                fontSize: 14,
                height: 1.5,
              ),
              decoration: _blockInputDecor(
                _isGenerating ? 'Luna is thinking... 🔮' : 'Answer',
              ),
              enabled: !_isGenerating,
            ),
            if (_isGenerating)
              Positioned(
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                  decoration: BoxDecoration(
                    color: U.surface.withValues(alpha: 0.8),
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      SizedBox(
                        width: 14,
                        height: 14,
                        child: CircularProgressIndicator(
                          strokeWidth: 1.8,
                          color: U.primary,
                        ),
                      ),
                      const SizedBox(width: 10),
                      Text(
                        'Luna is answering...',
                        style: GoogleFonts.outfit(
                          color: U.primary,
                          fontSize: 12.5,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
          ],
        ),
        const SizedBox(height: 10),
        Align(
          alignment: Alignment.centerRight,
          child: AnimatedOpacity(
            duration: const Duration(milliseconds: 200),
            opacity: _isGenerating ? 0.6 : 1.0,
            child: InkWell(
              onTap: _isGenerating ? null : _letLunaAnswer,
              borderRadius: BorderRadius.circular(10),
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 7),
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    colors: [
                      U.primary,
                      U.primary.withValues(alpha: 0.8),
                    ],
                  ),
                  borderRadius: BorderRadius.circular(10),
                  boxShadow: [
                    BoxShadow(
                      color: U.primary.withValues(alpha: 0.25),
                      blurRadius: 8,
                      offset: const Offset(0, 2),
                    ),
                  ],
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const Icon(
                      Icons.auto_awesome_rounded,
                      color: Colors.white,
                      size: 14,
                    ),
                    const SizedBox(width: 6),
                    Text(
                      'Let Luna Answer',
                      style: GoogleFonts.outfit(
                        color: Colors.white,
                        fontSize: 12,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ],
    );
  }
}

// ── Code Block ──
class _CodeBlockBody extends StatefulWidget {
  final EditorBlock block;
  final VoidCallback onChanged;
  const _CodeBlockBody({required this.block, required this.onChanged});

  @override
  State<_CodeBlockBody> createState() => _CodeBlockBodyState();
}

class _CodeBlockBodyState extends State<_CodeBlockBody> {
  late TextEditingController _titleController;
  late TextEditingController _codeController;

  static const _languages = [
    '', 'c', 'cpp', 'java', 'python', 'javascript', 'typescript',
    'dart', 'go', 'rust', 'sql', 'bash', 'html', 'css', 'json', 'yaml', 'xml',
  ];

  @override
  void initState() {
    super.initState();
    _titleController = TextEditingController(text: widget.block.title);
    _codeController = TextEditingController(text: widget.block.codeContent);
  }

  @override
  void dispose() {
    _titleController.dispose();
    _codeController.dispose();
    super.dispose();
  }

  @override
  void didUpdateWidget(covariant _CodeBlockBody oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.block != widget.block) {
      _titleController.text = widget.block.title;
      _codeController.text = widget.block.codeContent;
    }
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        TextField(
          controller: _titleController,
          onChanged: (v) { widget.block.title = v; widget.onChanged(); },
          style: GoogleFonts.outfit(color: U.text, fontSize: 14, fontWeight: FontWeight.w600),
          decoration: _blockInputDecor('Title (optional)', dense: true),
        ),
        const SizedBox(height: 8),
        // Language selector
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 12),
          decoration: BoxDecoration(
            color: U.bg,
            borderRadius: BorderRadius.circular(10),
            border: Border.all(color: U.border),
          ),
          child: DropdownButtonHideUnderline(
            child: DropdownButton<String>(
              value: _languages.contains(widget.block.codeLanguage.toLowerCase())
                  ? widget.block.codeLanguage.toLowerCase()
                  : '',
              isExpanded: true,
              dropdownColor: U.card,
              style: GoogleFonts.outfit(color: U.text, fontSize: 13),
              icon: Icon(Icons.keyboard_arrow_down_rounded, color: U.dim, size: 18),
              items: _languages.map((lang) => DropdownMenuItem(
                value: lang,
                child: Text(
                  lang.isEmpty ? 'Auto-detect' : lang,
                  style: GoogleFonts.outfit(color: lang.isEmpty ? U.dim : U.text, fontSize: 13),
                ),
              )).toList(),
              onChanged: (v) {
                setState(() {
                  widget.block.codeLanguage = v ?? '';
                });
                widget.onChanged();
              },
            ),
          ),
        ),
        const SizedBox(height: 8),
        TextField(
          controller: _codeController,
          onChanged: (v) { widget.block.codeContent = v; widget.onChanged(); },
          maxLines: null,
          minLines: 4,
          style: GoogleFonts.sourceCodePro(color: U.text, fontSize: 13, height: 1.6),
          decoration: _blockInputDecor('Paste or type code here...'),
        ),
      ],
    );
  }
}

// ── LaTeX Block ──
class _LatexBlockBody extends StatefulWidget {
  final EditorBlock block;
  final VoidCallback onChanged;
  const _LatexBlockBody({required this.block, required this.onChanged});

  @override
  State<_LatexBlockBody> createState() => _LatexBlockBodyState();
}

class _LatexBlockBodyState extends State<_LatexBlockBody> {
  late TextEditingController _latexController;

  @override
  void initState() {
    super.initState();
    _latexController = TextEditingController(text: widget.block.latexContent);
  }

  @override
  void dispose() {
    _latexController.dispose();
    super.dispose();
  }

  @override
  void didUpdateWidget(covariant _LatexBlockBody oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.block != widget.block) {
      _latexController.text = widget.block.latexContent;
    }
  }

  @override
  Widget build(BuildContext context) {
    return TextField(
      controller: _latexController,
      onChanged: (v) { widget.block.latexContent = v; widget.onChanged(); },
      maxLines: null,
      minLines: 2,
      style: GoogleFonts.sourceCodePro(color: U.text, fontSize: 13, height: 1.6),
      decoration: _blockInputDecor(r'LaTeX expression, e.g. \frac{a}{b}'),
    );
  }
}

// ── Table Block ──
class _TableBlockBody extends StatefulWidget {
  final EditorBlock block;
  final VoidCallback onChanged;
  const _TableBlockBody({required this.block, required this.onChanged});

  @override
  State<_TableBlockBody> createState() => _TableBlockBodyState();
}

class _TableBlockBodyState extends State<_TableBlockBody> {
  late TextEditingController _titleController;
  late List<List<TextEditingController>> _cellControllers;

  @override
  void initState() {
    super.initState();
    _titleController = TextEditingController(text: widget.block.title);
    _initCellControllers();
  }

  void _initCellControllers() {
    _cellControllers = [];
    for (int r = 0; r < widget.block.tableData.length; r++) {
      final row = <TextEditingController>[];
      for (int c = 0; c < widget.block.tableData[r].length; c++) {
        row.add(TextEditingController(text: widget.block.tableData[r][c]));
      }
      _cellControllers.add(row);
    }
  }

  void _disposeCellControllers() {
    for (final row in _cellControllers) {
      for (final controller in row) {
        controller.dispose();
      }
    }
  }

  @override
  void dispose() {
    _titleController.dispose();
    _disposeCellControllers();
    super.dispose();
  }

  @override
  void didUpdateWidget(covariant _TableBlockBody oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.block != widget.block) {
      _titleController.text = widget.block.title;
      _disposeCellControllers();
      _initCellControllers();
    }
  }

  void _addRow() {
    setState(() {
      widget.block.tableRows++;
      widget.block.tableData.add(List.generate(widget.block.tableCols, (_) => ''));
      _cellControllers.add(List.generate(widget.block.tableCols, (_) => TextEditingController()));
    });
    widget.onChanged();
  }

  void _addCol() {
    setState(() {
      widget.block.tableCols++;
      for (int r = 0; r < widget.block.tableData.length; r++) {
        widget.block.tableData[r].add('');
        _cellControllers[r].add(TextEditingController());
      }
    });
    widget.onChanged();
  }

  void _removeRow() {
    if (widget.block.tableRows <= 1) return;
    setState(() {
      widget.block.tableRows--;
      widget.block.tableData.removeLast();
      final removed = _cellControllers.removeLast();
      for (final ctrl in removed) {
        ctrl.dispose();
      }
    });
    widget.onChanged();
  }

  void _removeCol() {
    if (widget.block.tableCols <= 1) return;
    setState(() {
      widget.block.tableCols--;
      for (int r = 0; r < widget.block.tableData.length; r++) {
        if (widget.block.tableData[r].isNotEmpty) widget.block.tableData[r].removeLast();
        if (_cellControllers[r].isNotEmpty) {
          final removed = _cellControllers[r].removeLast();
          removed.dispose();
        }
      }
    });
    widget.onChanged();
  }

  @override
  Widget build(BuildContext context) {
    final data = widget.block.tableData;
    return Column(
      children: [
        TextField(
          controller: _titleController,
          onChanged: (v) { widget.block.title = v; widget.onChanged(); },
          style: GoogleFonts.outfit(color: U.text, fontSize: 14, fontWeight: FontWeight.w600),
          decoration: _blockInputDecor('Title (optional)', dense: true),
        ),
        const SizedBox(height: 12),
        // Controls
        Row(
          children: [
            _tableCtrl(Icons.add, 'Row', _addRow),
            const SizedBox(width: 8),
            _tableCtrl(Icons.remove, 'Row', _removeRow),
            const SizedBox(width: 16),
            _tableCtrl(Icons.add, 'Col', _addCol),
            const SizedBox(width: 8),
            _tableCtrl(Icons.remove, 'Col', _removeCol),
            const Spacer(),
            Text(
              '${widget.block.tableRows}×${widget.block.tableCols}',
              style: GoogleFonts.outfit(color: U.dim, fontSize: 11),
            ),
          ],
        ),
        const SizedBox(height: 10),
        // Table grid
        SingleChildScrollView(
          scrollDirection: Axis.horizontal,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: List.generate(data.length, (r) {
              return Row(
                children: List.generate(data[r].length, (c) {
                  final isHeader = r == 0;
                  return Container(
                    width: 100,
                    margin: const EdgeInsets.all(1),
                    child: TextField(
                      controller: _cellControllers[r][c],
                      onChanged: (v) {
                        data[r][c] = v;
                        widget.onChanged();
                      },
                      style: GoogleFonts.outfit(
                        color: U.text,
                        fontSize: 12,
                        fontWeight: isHeader ? FontWeight.w700 : FontWeight.w400,
                      ),
                      decoration: InputDecoration(
                        hintText: isHeader ? 'Header' : '',
                        hintStyle: GoogleFonts.outfit(color: U.dim, fontSize: 11),
                        filled: true,
                        fillColor: isHeader ? U.primary.withValues(alpha: 0.06) : U.bg,
                        isDense: true,
                        contentPadding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
                        border: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(6),
                          borderSide: BorderSide(color: U.border, width: 0.5),
                        ),
                        enabledBorder: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(6),
                          borderSide: BorderSide(color: U.border, width: 0.5),
                        ),
                        focusedBorder: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(6),
                          borderSide: BorderSide(color: U.primary),
                        ),
                      ),
                    ),
                  );
                }),
              );
            }),
          ),
        ),
      ],
    );
  }

  Widget _tableCtrl(IconData icon, String label, VoidCallback onTap) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
        decoration: BoxDecoration(
          color: U.bg,
          borderRadius: BorderRadius.circular(8),
          border: Border.all(color: U.border),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, color: U.sub, size: 14),
            const SizedBox(width: 4),
            Text(label, style: GoogleFonts.outfit(color: U.sub, fontSize: 11)),
          ],
        ),
      ),
    );
  }
}

// ── Mermaid Block ──
class _MermaidBlockBody extends StatefulWidget {
  final EditorBlock block;
  final VoidCallback onChanged;
  const _MermaidBlockBody({required this.block, required this.onChanged});

  @override
  State<_MermaidBlockBody> createState() => _MermaidBlockBodyState();
}

class _MermaidBlockBodyState extends State<_MermaidBlockBody> {
  late TextEditingController _mermaidController;

  static const _directions = [
    ('TD', 'Top → Down'),
    ('LR', 'Left → Right'),
    ('BT', 'Bottom → Top'),
    ('RL', 'Right → Left'),
  ];

  @override
  void initState() {
    super.initState();
    _mermaidController = TextEditingController(text: widget.block.mermaidContent);
  }

  @override
  void dispose() {
    _mermaidController.dispose();
    super.dispose();
  }

  @override
  void didUpdateWidget(covariant _MermaidBlockBody oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.block != widget.block) {
      _mermaidController.text = widget.block.mermaidContent;
    }
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // Direction selector
        Wrap(
          spacing: 8,
          children: _directions.map((d) {
            final isSelected = widget.block.mermaidDirection == d.$1;
            return GestureDetector(
              onTap: () {
                setState(() {
                  widget.block.mermaidDirection = d.$1;
                });
                widget.onChanged();
              },
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
                decoration: BoxDecoration(
                  color: isSelected ? U.primary.withValues(alpha: 0.12) : U.bg,
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(color: isSelected ? U.primary : U.border),
                ),
                child: Text(
                  d.$2,
                  style: GoogleFonts.outfit(
                    color: isSelected ? U.primary : U.sub,
                    fontSize: 11,
                    fontWeight: isSelected ? FontWeight.w600 : FontWeight.w400,
                  ),
                ),
              ),
            );
          }).toList(),
        ),
        const SizedBox(height: 10),
        TextField(
          controller: _mermaidController,
          onChanged: (v) { widget.block.mermaidContent = v; widget.onChanged(); },
          maxLines: null,
          minLines: 3,
          style: GoogleFonts.sourceCodePro(color: U.text, fontSize: 13, height: 1.6),
          decoration: _blockInputDecor('    A --> B\n    B --> C'),
        ),
      ],
    );
  }
}

// ── File Block (display only, already uploaded) ──
class _FileBlockBody extends StatelessWidget {
  final EditorBlock block;
  final VoidCallback? onRenamed;
  const _FileBlockBody({required this.block, this.onRenamed});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: U.bg,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: U.green.withValues(alpha: 0.3)),
      ),
      child: Row(
        children: [
          Container(
            width: 34, height: 34,
            decoration: BoxDecoration(
              color: U.green.withValues(alpha: 0.1),
              borderRadius: BorderRadius.circular(8),
            ),
            child: Icon(Icons.check_circle_outline, color: U.green, size: 18),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: GestureDetector(
              onTap: () async {
                final controller = TextEditingController(
                  text: block.fileDisplayName.isEmpty ? 'File' : block.fileDisplayName,
                );
                final newName = await showDialog<String>(
                  context: context,
                  builder: (ctx) => AlertDialog(
                    backgroundColor: U.card,
                    title: Text('Rename Link', style: GoogleFonts.outfit(color: U.text, fontWeight: FontWeight.w600)),
                    content: TextField(
                      controller: controller,
                      style: GoogleFonts.outfit(color: U.text),
                      autofocus: true,
                      decoration: InputDecoration(
                        hintText: 'Display name',
                        hintStyle: GoogleFonts.outfit(color: U.sub),
                        filled: true,
                        fillColor: U.bg,
                        border: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(12),
                          borderSide: BorderSide(color: U.border),
                        ),
                      ),
                    ),
                    actions: [
                      TextButton(
                        onPressed: () => Navigator.pop(ctx),
                        child: Text('Cancel', style: GoogleFonts.outfit(color: U.sub)),
                      ),
                      FilledButton(
                        onPressed: () => Navigator.pop(ctx, controller.text.trim()),
                        style: FilledButton.styleFrom(backgroundColor: U.primary),
                        child: Text('Rename', style: GoogleFonts.outfit(color: U.bg)),
                      ),
                    ],
                  ),
                );
                if (newName != null && newName.isNotEmpty && newName != block.fileDisplayName) {
                  block.fileDisplayName = newName;
                  onRenamed?.call();
                }
              },
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Expanded(
                        child: Text(
                          block.fileDisplayName.isEmpty ? 'File' : block.fileDisplayName,
                          style: GoogleFonts.outfit(color: U.text, fontSize: 13, fontWeight: FontWeight.w600),
                        ),
                      ),
                      Icon(Icons.edit_outlined, color: U.dim, size: 14),
                    ],
                  ),
                  const SizedBox(height: 2),
                  Text(
                    'Uploaded — tap to rename link',
                    style: GoogleFonts.outfit(color: U.green, fontSize: 11),
                  ),
                ],
              ),
            ),
          ),
          Icon(Icons.link_rounded, color: U.dim, size: 16),
        ],
      ),
    );
  }
}

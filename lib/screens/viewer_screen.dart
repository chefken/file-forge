import 'dart:io';
import 'dart:typed_data';
import 'package:archive/archive_io.dart';
import 'package:flutter/material.dart';
import 'package:file_picker/file_picker.dart';
import 'package:flutter_pdfview/flutter_pdfview.dart';
import 'package:xml/xml.dart';
import '../widgets/section_header.dart';

class ViewerScreen extends StatefulWidget {
  const ViewerScreen({super.key});

  @override
  State<ViewerScreen> createState() => _ViewerScreenState();
}

class _ViewerScreenState extends State<ViewerScreen>
    with SingleTickerProviderStateMixin {
  static const Color _red = Color(0xFFE8192C);

  late TabController _tabController;

  // PDF state
  File? _pdfFile;
  int _totalPages = 0;
  int _currentPage = 1;
  bool _pdfLoading = false;

  // DOCX state
  List<_DocxBlock> _docxBlocks = [];
  String? _docxName;
  bool _docxLoading = false;
  String _docxError = '';

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 2, vsync: this);
  }

  @override
  void dispose() {
    _tabController.dispose();
    super.dispose();
  }

  // ── PICK PDF ────────────────────────────────────────────
  Future<void> _pickPdf() async {
    final result = await FilePicker.platform.pickFiles(
      type: FileType.custom,
      allowedExtensions: ['pdf'],
    );
    if (result == null || result.files.single.path == null) return;
    setState(() {
      _pdfFile = File(result.files.single.path!);
      _totalPages = 0;
      _currentPage = 1;
      _pdfLoading = true;
    });
  }

  // ── PICK DOCX ───────────────────────────────────────────
  Future<void> _pickDocx() async {
    final result = await FilePicker.platform.pickFiles(
      type: FileType.custom,
      allowedExtensions: ['docx', 'doc'],
    );
    if (result == null || result.files.single.path == null) return;
    final file = File(result.files.single.path!);
    setState(() {
      _docxLoading = true;
      _docxError = '';
      _docxBlocks = [];
      _docxName = result.files.single.name;
    });

    try {
      final blocks = await _parseDocx(file);
      setState(() { _docxBlocks = blocks; _docxLoading = false; });
    } catch (e) {
      setState(() {
        _docxError = 'Could not read this file: $e';
        _docxLoading = false;
      });
    }
  }

  // ── PARSE DOCX OFFLINE ──────────────────────────────────
  // Extracts text content from word/document.xml inside the .docx zip
  Future<List<_DocxBlock>> _parseDocx(File file) async {
    final bytes = await file.readAsBytes();
    final archive = ZipDecoder().decodeBytes(bytes);

    // Find document.xml
    ArchiveFile? docXml;
    for (final f in archive) {
      if (f.name == 'word/document.xml') {
        docXml = f;
        break;
      }
    }
    if (docXml == null) throw Exception('Not a valid DOCX file');

    final xmlStr = String.fromCharCodes(
        Uint8List.fromList(docXml.content as List<int>));
    final document = XmlDocument.parse(xmlStr);

    final blocks = <_DocxBlock>[];

    // Walk all paragraphs <w:p>
    final paragraphs = document.findAllElements('w:p');
    for (final para in paragraphs) {
      // Check heading style
      final styleEl = para.findElements('w:pStyle').firstOrNull;
      final styleId = styleEl?.getAttribute('w:val') ?? '';

      // Collect all text runs <w:r><w:t>
      final runs = para.findAllElements('w:r');
      final buffer = StringBuffer();
      bool isBold = false;

      for (final run in runs) {
        // Check bold <w:b/>
        final rpr = run.findElements('w:rPr').firstOrNull;
        if (rpr != null) {
          isBold = rpr.findElements('w:b').isNotEmpty;
        }
        for (final t in run.findElements('w:t')) {
          buffer.write(t.innerText);
        }
      }

      final text = buffer.toString().trim();
      if (text.isEmpty) {
        blocks.add(const _DocxBlock('', _BlockType.spacer));
        continue;
      }

      _BlockType type = _BlockType.body;
      if (styleId.toLowerCase().contains('heading1') ||
          styleId.toLowerCase() == 'title') {
        type = _BlockType.h1;
      } else if (styleId.toLowerCase().contains('heading2')) {
        type = _BlockType.h2;
      } else if (styleId.toLowerCase().contains('heading3')) {
        type = _BlockType.h3;
      } else if (isBold) {
        type = _BlockType.bold;
      }

      blocks.add(_DocxBlock(text, type));
    }

    return blocks;
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFF8F8F6),
      appBar: AppBar(
        backgroundColor: Colors.white,
        surfaceTintColor: Colors.transparent,
        title: Row(children: [
          Container(width: 4, height: 22, color: _red,
              margin: const EdgeInsets.only(right: 10)),
          const Text('VIEWER',
              style: TextStyle(
                fontWeight: FontWeight.w900,
                fontSize: 20,
                letterSpacing: 1.5,
              )),
        ]),
        bottom: TabBar(
          controller: _tabController,
          labelColor: _red,
          unselectedLabelColor: Colors.grey,
          indicatorColor: _red,
          indicatorWeight: 2.5,
          labelStyle: const TextStyle(fontWeight: FontWeight.w700, fontSize: 13),
          tabs: const [
            Tab(text: 'PDF'),
            Tab(text: 'DOCX'),
          ],
        ),
      ),
      body: TabBarView(
        controller: _tabController,
        children: [
          _PdfTab(
            pdfFile: _pdfFile,
            loading: _pdfLoading,
            totalPages: _totalPages,
            currentPage: _currentPage,
            onPick: _pickPdf,
            onPageChanged: (p, t) => setState(() {
              _currentPage = (p ?? 0) + 1;
              _totalPages = t ?? 0;
            }),
            onReady: (total) => setState(() {
              _totalPages = total;
              _pdfLoading = false;
            }),
          ),
          _DocxTab(
            blocks: _docxBlocks,
            loading: _docxLoading,
            error: _docxError,
            fileName: _docxName,
            onPick: _pickDocx,
          ),
        ],
      ),
    );
  }
}

// ── PDF TAB ────────────────────────────────────────────────
class _PdfTab extends StatelessWidget {
  final File? pdfFile;
  final bool loading;
  final int totalPages;
  final int currentPage;
  final VoidCallback onPick;
  final Function(int?, int?) onPageChanged;
  final Function(int) onReady;

  const _PdfTab({
    required this.pdfFile,
    required this.loading,
    required this.totalPages,
    required this.currentPage,
    required this.onPick,
    required this.onPageChanged,
    required this.onReady,
  });

  @override
  Widget build(BuildContext context) {
    if (pdfFile == null) {
      return _EmptyViewer(
        icon: Icons.picture_as_pdf_rounded,
        title: 'Open a PDF',
        subtitle: 'Browse and view PDF files stored on your device',
        buttonLabel: 'Choose PDF',
        onPick: onPick,
      );
    }

    return Stack(
      children: [
        PDFView(
          filePath: pdfFile!.path,
          enableSwipe: true,
          swipeHorizontal: false,
          autoSpacing: true,
          pageFling: true,
          backgroundColor: const Color(0xFFF0F0F0),
          onRender: (pages) => onReady(pages ?? 0),
          onPageChanged: (page, total) => onPageChanged(page, total),
        ),
        if (loading)
          const Center(
            child: CircularProgressIndicator(color: Color(0xFFE8192C))),
        if (totalPages > 0)
          Positioned(
            bottom: 20, right: 16,
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 7),
              decoration: BoxDecoration(
                color: Colors.black.withOpacity(0.7),
                borderRadius: BorderRadius.circular(20),
              ),
              child: Text('$currentPage / $totalPages',
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 12,
                    fontWeight: FontWeight.w600,
                  )),
            ),
          ),
        Positioned(
          bottom: 20, left: 16,
          child: FloatingActionButton.small(
            onPressed: onPick,
            backgroundColor: const Color(0xFFE8192C),
            child: const Icon(Icons.folder_open_rounded,
                color: Colors.white, size: 20),
          ),
        ),
      ],
    );
  }
}

// ── DOCX TAB ───────────────────────────────────────────────
class _DocxTab extends StatelessWidget {
  final List<_DocxBlock> blocks;
  final bool loading;
  final String error;
  final String? fileName;
  final VoidCallback onPick;

  const _DocxTab({
    required this.blocks,
    required this.loading,
    required this.error,
    required this.fileName,
    required this.onPick,
  });

  @override
  Widget build(BuildContext context) {
    if (loading) {
      return const Center(
        child: CircularProgressIndicator(color: Color(0xFFE8192C)));
    }

    if (error.isNotEmpty) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(32),
          child: Column(mainAxisSize: MainAxisSize.min, children: [
            const Icon(Icons.error_outline, color: Colors.red, size: 48),
            const SizedBox(height: 12),
            Text(error, textAlign: TextAlign.center,
                style: const TextStyle(color: Colors.grey)),
            const SizedBox(height: 20),
            ElevatedButton(
              onPressed: onPick,
              child: const Text('Try another file')),
          ]),
        ),
      );
    }

    if (blocks.isEmpty) {
      return _EmptyViewer(
        icon: Icons.description_rounded,
        title: 'Open a DOCX',
        subtitle: 'View Word documents directly inside the app — no conversion needed',
        buttonLabel: 'Choose DOCX',
        onPick: onPick,
      );
    }

    return Column(
      children: [
        // File header
        Container(
          color: Colors.white,
          padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
          child: Row(children: [
            Container(
              width: 36, height: 36,
              decoration: BoxDecoration(
                color: const Color(0xFF1976D2).withOpacity(0.1),
                borderRadius: BorderRadius.circular(8),
              ),
              child: const Icon(Icons.description_rounded,
                  color: Color(0xFF1976D2), size: 20),
            ),
            const SizedBox(width: 12),
            Expanded(child: Text(fileName ?? 'Document',
                style: const TextStyle(
                  fontWeight: FontWeight.w700, fontSize: 14),
                overflow: TextOverflow.ellipsis)),
            TextButton.icon(
              onPressed: onPick,
              icon: const Icon(Icons.folder_open_rounded, size: 16),
              label: const Text('Open'),
              style: TextButton.styleFrom(
                foregroundColor: const Color(0xFFE8192C),
                textStyle: const TextStyle(
                    fontSize: 12, fontWeight: FontWeight.w600),
              ),
            ),
          ]),
        ),
        const Divider(height: 1, color: Color(0xFFEEEEEE)),

        // Document content
        Expanded(
          child: ListView.builder(
            padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 20),
            itemCount: blocks.length,
            itemBuilder: (ctx, i) => _buildBlock(blocks[i]),
          ),
        ),
      ],
    );
  }

  Widget _buildBlock(_DocxBlock block) {
    switch (block.type) {
      case _BlockType.spacer:
        return const SizedBox(height: 8);
      case _BlockType.h1:
        return Padding(
          padding: const EdgeInsets.only(bottom: 12, top: 8),
          child: Text(block.text,
              style: const TextStyle(
                fontSize: 22, fontWeight: FontWeight.w800,
                color: Color(0xFF111111), height: 1.3,
              )),
        );
      case _BlockType.h2:
        return Padding(
          padding: const EdgeInsets.only(bottom: 10, top: 6),
          child: Text(block.text,
              style: const TextStyle(
                fontSize: 18, fontWeight: FontWeight.w700,
                color: Color(0xFF222222), height: 1.3,
              )),
        );
      case _BlockType.h3:
        return Padding(
          padding: const EdgeInsets.only(bottom: 8, top: 4),
          child: Text(block.text,
              style: const TextStyle(
                fontSize: 15, fontWeight: FontWeight.w700,
                color: Color(0xFF333333), height: 1.4,
              )),
        );
      case _BlockType.bold:
        return Padding(
          padding: const EdgeInsets.only(bottom: 6),
          child: Text(block.text,
              style: const TextStyle(
                fontSize: 14, fontWeight: FontWeight.w700,
                color: Color(0xFF111111), height: 1.6,
              )),
        );
      case _BlockType.body:
        return Padding(
          padding: const EdgeInsets.only(bottom: 6),
          child: Text(block.text,
              style: const TextStyle(
                fontSize: 14, fontWeight: FontWeight.w400,
                color: Color(0xFF333333), height: 1.75,
              )),
        );
    }
  }
}

// ── EMPTY VIEWER ───────────────────────────────────────────
class _EmptyViewer extends StatelessWidget {
  final IconData icon;
  final String title;
  final String subtitle;
  final String buttonLabel;
  final VoidCallback onPick;

  const _EmptyViewer({
    required this.icon,
    required this.title,
    required this.subtitle,
    required this.buttonLabel,
    required this.onPick,
  });

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(36),
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          Container(
            width: 88, height: 88,
            decoration: BoxDecoration(
              color: const Color(0xFFE8192C).withOpacity(0.08),
              borderRadius: BorderRadius.circular(24),
            ),
            child: Icon(icon,
                color: const Color(0xFFE8192C), size: 44),
          ),
          const SizedBox(height: 20),
          Text(title,
              style: const TextStyle(
                fontSize: 20, fontWeight: FontWeight.w800,
              )),
          const SizedBox(height: 8),
          Text(subtitle,
              textAlign: TextAlign.center,
              style: const TextStyle(
                color: Colors.grey, fontSize: 13, height: 1.6,
              )),
          const SizedBox(height: 28),
          SizedBox(
            width: 200,
            height: 48,
            child: ElevatedButton.icon(
              onPressed: onPick,
              icon: const Icon(Icons.folder_open_rounded),
              label: Text(buttonLabel,
                  style: const TextStyle(fontWeight: FontWeight.w700)),
            ),
          ),
        ]),
      ),
    );
  }
}

// ── DATA MODELS ────────────────────────────────────────────
enum _BlockType { h1, h2, h3, bold, body, spacer }

class _DocxBlock {
  final String text;
  final _BlockType type;
  const _DocxBlock(this.text, this.type);
}
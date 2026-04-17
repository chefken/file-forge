import 'dart:io';
import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import 'package:path_provider/path_provider.dart';
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;
import 'package:permission_handler/permission_handler.dart';
import 'package:image/image.dart' as img;
import 'package:path/path.dart' as p;
import '../widgets/image_card.dart';
import '../widgets/section_header.dart';
import '../widgets/converto_button.dart';
import 'editor_screen.dart';

class ConvertScreen extends StatefulWidget {
  const ConvertScreen({super.key});

  @override
  State<ConvertScreen> createState() => _ConvertScreenState();
}

class _ConvertScreenState extends State<ConvertScreen> {
  final ImagePicker _picker = ImagePicker();

  // Each item: {'file': File, 'edited': File?}
  List<Map<String, dynamic>> _images = [];
  bool _converting = false;

  static const Color _red = Color(0xFFE8192C);

  // ── PICK IMAGES ──────────────────────────────────────────
  Future<void> _pickImages() async {
    final status = await Permission.photos.request();
    if (!status.isGranted && !status.isLimited) {
      _showSnack('Gallery permission denied');
      return;
    }
    final picked = await _picker.pickMultiImage(imageQuality: 95);
    if (picked.isEmpty) return;
    setState(() {
      for (final x in picked) {
        _images.add({'file': File(x.path), 'edited': null});
      }
    });
  }

  // ── OPEN EDITOR ──────────────────────────────────────────
  Future<void> _editImage(int index) async {
    final source = (_images[index]['edited'] as File?) ?? (_images[index]['file'] as File);
    final result = await Navigator.push<File>(
      context,
      MaterialPageRoute(builder: (_) => EditorScreen(imageFile: source)),
    );
    if (result != null) {
      setState(() => _images[index]['edited'] = result);
    }
  }

  // ── REMOVE IMAGE ─────────────────────────────────────────
  void _removeImage(int index) {
    setState(() => _images.removeAt(index));
  }

  // ── REORDER ──────────────────────────────────────────────
  void _reorder(int oldIndex, int newIndex) {
    setState(() {
      if (newIndex > oldIndex) newIndex--;
      final item = _images.removeAt(oldIndex);
      _images.insert(newIndex, item);
    });
  }

  // ── CONVERT TO PDF ───────────────────────────────────────
  Future<void> _convertToPdf() async {
    if (_images.isEmpty) {
      _showSnack('Add at least one image first');
      return;
    }

    // Ask for filename
    final name = await _askFilename();
    if (name == null || name.trim().isEmpty) return;

    setState(() => _converting = true);

    try {
      final pdf = pw.Document();

      for (final item in _images) {
        final file = (item['edited'] as File?) ?? (item['file'] as File);
        final bytes = await file.readAsBytes();

        // Decode and encode via image package for consistency
        final decoded = img.decodeImage(bytes);
        if (decoded == null) continue;
        final pngBytes = img.encodePng(decoded);

        final pdfImage = pw.MemoryImage(pngBytes);

        pdf.addPage(
          pw.Page(
            pageFormat: PdfPageFormat.a4,
            margin: pw.EdgeInsets.zero,
            build: (ctx) => pw.Center(
              child: pw.Image(pdfImage, fit: pw.BoxFit.contain),
            ),
          ),
        );
      }

      // Save to app documents directory
      final dir = Directory('/storage/emulated/0/Download');
      final fileName = name.endsWith('.pdf') ? name : '$name.pdf';
      final outFile = File('${dir.path}/$fileName');
      await outFile.writeAsBytes(await pdf.save());

      if (!mounted) return;
      setState(() => _converting = false);

      _showSuccessSheet(outFile.path);
    } catch (e) {
      setState(() => _converting = false);
      _showSnack('Conversion failed: $e');
    }
  }

  // ── ASK FILENAME ─────────────────────────────────────────
  Future<String?> _askFilename() async {
    final ctrl = TextEditingController(
      text: 'document_${DateTime.now().millisecondsSinceEpoch}',
    );
    return showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        title: const Text('Name your PDF',
            style: TextStyle(fontWeight: FontWeight.w800, fontSize: 18)),
        content: TextField(
          controller: ctrl,
          autofocus: true,
          decoration: InputDecoration(
            hintText: 'Enter file name',
            suffixText: '.pdf',
            border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
            focusedBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(12),
              borderSide: const BorderSide(color: _red, width: 1.5),
            ),
            contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('Cancel', style: TextStyle(color: Colors.grey)),
          ),
          ElevatedButton(
            onPressed: () => Navigator.pop(ctx, ctrl.text.trim()),
            style: ElevatedButton.styleFrom(
              backgroundColor: _red,
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
            ),
            child: const Text('Save'),
          ),
        ],
      ),
    );
  }

  // ── SUCCESS BOTTOM SHEET ─────────────────────────────────
  void _showSuccessSheet(String path) {
    showModalBottomSheet(
      context: context,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      builder: (ctx) => Padding(
        padding: const EdgeInsets.all(28),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 60, height: 60,
              decoration: BoxDecoration(
                color: Colors.green.shade50,
                shape: BoxShape.circle,
              ),
              child: const Icon(Icons.check_circle_rounded,
                  color: Colors.green, size: 32),
            ),
            const SizedBox(height: 16),
            const Text('PDF Created!',
                style: TextStyle(fontSize: 20, fontWeight: FontWeight.w800)),
            const SizedBox(height: 6),
            Text(p.basename(path),
                style: const TextStyle(color: Colors.grey, fontSize: 13)),
            const SizedBox(height: 8),
            Text('Saved to app storage',
                style: TextStyle(color: Colors.grey.shade400, fontSize: 12)),
            const SizedBox(height: 24),
            Row(children: [
              Expanded(
                child: OutlinedButton(
                  onPressed: () {
                    Navigator.pop(ctx);
                    setState(() => _images.clear());
                  },
                  style: OutlinedButton.styleFrom(
                    shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(12)),
                    side: const BorderSide(color: Color(0xFFE0E0E0)),
                    padding: const EdgeInsets.symmetric(vertical: 14),
                  ),
                  child: const Text('Start Over',
                      style: TextStyle(color: Colors.black87,
                          fontWeight: FontWeight.w600)),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: ElevatedButton(
                  onPressed: () => Navigator.pop(ctx),
                  child: const Text('Done',
                      style: TextStyle(fontWeight: FontWeight.w700)),
                ),
              ),
            ]),
            const SizedBox(height: 8),
          ],
        ),
      ),
    );
  }

  void _showSnack(String msg) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(msg),
        behavior: SnackBarBehavior.floating,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFF8F8F6),
      body: SafeArea(
        child: CustomScrollView(
          slivers: [
            // ── APP BAR ──────────────────────────────────
            SliverAppBar(
              pinned: true,
              backgroundColor: Colors.white,
              surfaceTintColor: Colors.transparent,
              title: Row(children: [
                Container(
                  width: 4, height: 22,
                  color: _red,
                  margin: const EdgeInsets.only(right: 10),
                ),
                const Text('CONVERTO',
                    style: TextStyle(
                      fontWeight: FontWeight.w900,
                      fontSize: 20,
                      letterSpacing: 1.5,
                    )),
              ]),
              actions: [
                if (_images.isNotEmpty)
                  TextButton.icon(
                    onPressed: () => setState(() => _images.clear()),
                    icon: const Icon(Icons.clear_all, size: 18),
                    label: const Text('Clear'),
                    style: TextButton.styleFrom(foregroundColor: Colors.grey),
                  ),
              ],
            ),

            SliverPadding(
              padding: const EdgeInsets.fromLTRB(20, 20, 20, 100),
              sliver: SliverList(
                delegate: SliverChildListDelegate([

                  // ── HERO CARD ──────────────────────────
                  _HeroCard(onPick: _pickImages),
                  const SizedBox(height: 24),

                  // ── IMAGES SECTION ─────────────────────
                  if (_images.isNotEmpty) ...[
                    SectionHeader(
                      title: 'Selected Images',
                      subtitle: '${_images.length} image${_images.length > 1 ? "s" : ""} · drag to reorder',
                      action: TextButton.icon(
                        onPressed: _pickImages,
                        icon: const Icon(Icons.add, size: 16),
                        label: const Text('Add more'),
                        style: TextButton.styleFrom(
                          foregroundColor: _red,
                          textStyle: const TextStyle(
                              fontSize: 13, fontWeight: FontWeight.w600),
                        ),
                      ),
                    ),
                    const SizedBox(height: 12),

                    // REORDERABLE IMAGE LIST
                    ReorderableListView.builder(
                      shrinkWrap: true,
                      physics: const NeverScrollableScrollPhysics(),
                      itemCount: _images.length,
                      onReorder: _reorder,
                      proxyDecorator: (child, index, anim) => Material(
                        elevation: 8,
                        borderRadius: BorderRadius.circular(16),
                        child: child,
                      ),
                      itemBuilder: (ctx, i) {
                        final item = _images[i];
                        final file = (item['edited'] as File?) ??
                            (item['file'] as File);
                        return ImageCard(
                          key: ValueKey(item['file'].path + i.toString()),
                          file: file,
                          index: i,
                          isEdited: item['edited'] != null,
                          onEdit: () => _editImage(i),
                          onRemove: () => _removeImage(i),
                        );
                      },
                    ),
                    const SizedBox(height: 24),

                    // CONVERT BUTTON
                    ConvertoButton(
                      label: 'Convert to PDF',
                      icon: Icons.picture_as_pdf_rounded,
                      loading: _converting,
                      onPressed: _convertToPdf,
                    ),
                  ],

                  // ── EMPTY STATE ────────────────────────
                  if (_images.isEmpty)
                    const _EmptyTips(),
                ]),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// ── HERO CARD ──────────────────────────────────────────────
class _HeroCard extends StatelessWidget {
  final VoidCallback onPick;
  const _HeroCard({required this.onPick});

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onPick,
      child: Container(
        width: double.infinity,
        padding: const EdgeInsets.all(28),
        decoration: BoxDecoration(
          gradient: const LinearGradient(
            colors: [Color(0xFFE8192C), Color(0xFFFF4D5E)],
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
          ),
          borderRadius: BorderRadius.circular(24),
          boxShadow: [
            BoxShadow(
              color: const Color(0xFFE8192C).withOpacity(0.3),
              blurRadius: 20,
              offset: const Offset(0, 8),
            ),
          ],
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Container(
              width: 52, height: 52,
              decoration: BoxDecoration(
                color: Colors.white.withOpacity(0.2),
                borderRadius: BorderRadius.circular(14),
              ),
              child: const Icon(Icons.add_photo_alternate_rounded,
                  color: Colors.white, size: 28),
            ),
            const SizedBox(height: 18),
            const Text('Images → PDF',
                style: TextStyle(
                  color: Colors.white,
                  fontSize: 22,
                  fontWeight: FontWeight.w800,
                  letterSpacing: 0.3,
                )),
            const SizedBox(height: 6),
            Text('Select photos from gallery, edit them,\nthen convert to a single PDF',
                style: TextStyle(
                  color: Colors.white.withOpacity(0.8),
                  fontSize: 13,
                  height: 1.5,
                )),
            const SizedBox(height: 20),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 10),
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(50),
              ),
              child: const Text('Pick Photos',
                  style: TextStyle(
                    color: Color(0xFFE8192C),
                    fontWeight: FontWeight.w800,
                    fontSize: 13,
                  )),
            ),
          ],
        ),
      ),
    );
  }
}

// ── EMPTY TIPS ─────────────────────────────────────────────
class _EmptyTips extends StatelessWidget {
  const _EmptyTips();

  @override
  Widget build(BuildContext context) {
    final tips = [
      (Icons.photo_library_rounded, 'Select multiple images', 'Pick from gallery in one go'),
      (Icons.tune_rounded, 'Edit before converting', 'Crop, rotate, apply filters'),
      (Icons.swap_vert_rounded, 'Reorder images', 'Drag to arrange page order'),
      (Icons.picture_as_pdf_rounded, 'Export as PDF', 'Name and save to your device'),
    ];
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const SectionHeader(title: 'How it works', subtitle: ''),
        const SizedBox(height: 12),
        ...tips.map((t) => Container(
          margin: const EdgeInsets.only(bottom: 10),
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(16),
            border: Border.all(color: const Color(0xFFEEEEEE)),
          ),
          child: Row(children: [
            Container(
              width: 40, height: 40,
              decoration: BoxDecoration(
                color: const Color(0xFFE8192C).withOpacity(0.08),
                borderRadius: BorderRadius.circular(10),
              ),
              child: Icon(t.$1, color: const Color(0xFFE8192C), size: 20),
            ),
            const SizedBox(width: 14),
            Expanded(child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(t.$2, style: const TextStyle(
                    fontWeight: FontWeight.w700, fontSize: 14)),
                const SizedBox(height: 2),
                Text(t.$3, style: const TextStyle(
                    color: Colors.grey, fontSize: 12)),
              ],
            )),
          ]),
        )),
      ],
    );
  }
}
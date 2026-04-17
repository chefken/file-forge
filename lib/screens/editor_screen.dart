import 'dart:io';
import 'dart:typed_data';
import 'package:flutter/material.dart';
import 'package:image/image.dart' as img;
import 'package:image_cropper/image_cropper.dart';
import 'package:path_provider/path_provider.dart';
import 'package:path/path.dart' as p;

class EditorScreen extends StatefulWidget {
  final File imageFile;
  const EditorScreen({super.key, required this.imageFile});

  @override
  State<EditorScreen> createState() => _EditorScreenState();
}

class _EditorScreenState extends State<EditorScreen> {
  static const Color _red = Color(0xFFE8192C);

  late File _currentFile;
  img.Image? _baseImage;
  img.Image? _displayImage;
  Uint8List? _previewBytes;

  bool _loading = true;
  bool _processing = false;

  // Filter state
  int _selectedFilter = 0; // 0=original, 1=bw, 2=grayscale, 3=contrast
  int _rotationDeg = 0;

  final List<_Filter> _filters = const [
    _Filter('Original', Icons.image_rounded),
    _Filter('B&W', Icons.filter_b_and_w_rounded),
    _Filter('Grayscale', Icons.gradient_rounded),
    _Filter('Contrast', Icons.tonality_rounded),
  ];

  @override
  void initState() {
    super.initState();
    _currentFile = widget.imageFile;
    _loadImage();
  }

  // ── LOAD ────────────────────────────────────────────────
  Future<void> _loadImage() async {
    setState(() => _loading = true);
    final bytes = await _currentFile.readAsBytes();
    _baseImage = img.decodeImage(bytes);
    _displayImage = _baseImage?.clone();
    await _applyProcessing();
    setState(() => _loading = false);
  }

  // ── APPLY ROTATION + FILTER ──────────────────────────────
  Future<void> _applyProcessing() async {
    if (_baseImage == null) return;

    img.Image processed = _baseImage!.clone();

    // Apply rotation
    if (_rotationDeg != 0) {
      processed = img.copyRotate(processed, angle: _rotationDeg.toDouble());
    }

    // Apply filter
    switch (_selectedFilter) {
      case 1: // Black & White (threshold)
        processed = img.grayscale(processed);
        processed = img.adjustColor(processed, contrast: 1.6);
        break;
      case 2: // Grayscale
        processed = img.grayscale(processed);
        break;
      case 3: // High contrast
        processed = img.adjustColor(processed, contrast: 1.5, brightness: 0.05);
        break;
      default:
        break;
    }

    _displayImage = processed;
    _previewBytes = Uint8List.fromList(img.encodeJpg(processed, quality: 90));
  }

  // ── ROTATE ──────────────────────────────────────────────
  Future<void> _rotate(bool clockwise) async {
    setState(() => _processing = true);
    _rotationDeg = (_rotationDeg + (clockwise ? 90 : -90)) % 360;
    await _applyProcessing();
    setState(() => _processing = false);
  }

  // ── FILTER ──────────────────────────────────────────────
  Future<void> _setFilter(int index) async {
    if (_selectedFilter == index) return;
    setState(() { _selectedFilter = index; _processing = true; });
    await _applyProcessing();
    setState(() => _processing = false);
  }

  // ── CROP ────────────────────────────────────────────────
  Future<void> _crop() async {
    // Save current state to temp file for cropper
    final dir = await getApplicationDocumentsDirectory();
    final tmpPath = p.join(dir.path, 'crop_tmp_${DateTime.now().millisecondsSinceEpoch}.jpg');

    File tmpFile;
    if (_previewBytes != null) {
      tmpFile = await File(tmpPath).writeAsBytes(_previewBytes!);
    } else {
      tmpFile = _currentFile;
    }

    final cropped = await ImageCropper().cropImage(
      sourcePath: tmpFile.path,
      uiSettings: [
        AndroidUiSettings(
          toolbarTitle: 'Crop Image',
          toolbarColor: const Color(0xFFE8192C),
          toolbarWidgetColor: Colors.white,
          activeControlsWidgetColor: const Color(0xFFE8192C),
          initAspectRatio: CropAspectRatioPreset.original,
          lockAspectRatio: false,
        ),
      ],
    );

    if (cropped != null) {
      final bytes = await File(cropped.path).readAsBytes();
      _baseImage = img.decodeImage(bytes);
      _rotationDeg = 0;
      await _applyProcessing();
      setState(() {});
    }
  }

  // ── SAVE ────────────────────────────────────────────────
  Future<void> _save() async {
    if (_previewBytes == null && _displayImage == null) {
      Navigator.pop(context, _currentFile);
      return;
    }

    setState(() => _processing = true);
    try {
      final dir = await getApplicationDocumentsDirectory();
      final outPath = p.join(dir.path,
          'edited_${DateTime.now().millisecondsSinceEpoch}.jpg');
      final outFile = await File(outPath)
          .writeAsBytes(_previewBytes ?? Uint8List.fromList(
              img.encodeJpg(_displayImage!, quality: 95)));
      if (mounted) Navigator.pop(context, outFile);
    } catch (e) {
      setState(() => _processing = false);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Save failed: $e')));
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFF111111),
      appBar: AppBar(
        backgroundColor: const Color(0xFF1A1A1A),
        foregroundColor: Colors.white,
        surfaceTintColor: Colors.transparent,
        title: const Text('Edit Image',
            style: TextStyle(color: Colors.white,
                fontWeight: FontWeight.w700, fontSize: 17)),
        leading: IconButton(
          icon: const Icon(Icons.close, color: Colors.white),
          onPressed: () => Navigator.pop(context),
        ),
        actions: [
          TextButton(
            onPressed: _processing ? null : _save,
            child: const Text('Done',
                style: TextStyle(
                  color: Color(0xFFE8192C),
                  fontWeight: FontWeight.w800,
                  fontSize: 16,
                )),
          ),
        ],
      ),
      body: Column(
        children: [
          // ── IMAGE PREVIEW ──────────────────────────────
          Expanded(
            child: Center(
              child: _loading
                ? const CircularProgressIndicator(color: Color(0xFFE8192C))
                : _processing
                  ? Stack(alignment: Alignment.center, children: [
                      if (_previewBytes != null)
                        Image.memory(_previewBytes!,
                            fit: BoxFit.contain),
                      Container(color: Colors.black38),
                      const CircularProgressIndicator(
                          color: Color(0xFFE8192C)),
                    ])
                  : _previewBytes != null
                    ? Image.memory(_previewBytes!,
                        fit: BoxFit.contain,
                        gaplessPlayback: true)
                    : Image.file(_currentFile, fit: BoxFit.contain),
            ),
          ),

          // ── TOOLBAR ───────────────────────────────────
          Container(
            color: const Color(0xFF1A1A1A),
            child: Column(
              children: [
                // ROTATE BUTTONS
                Padding(
                  padding: const EdgeInsets.fromLTRB(16, 16, 16, 8),
                  child: Row(children: [
                    Expanded(child: _ToolButton(
                      icon: Icons.crop_rounded,
                      label: 'Crop',
                      onTap: _processing ? null : _crop,
                    )),
                    const SizedBox(width: 10),
                    Expanded(child: _ToolButton(
                      icon: Icons.rotate_left_rounded,
                      label: 'Rotate L',
                      onTap: _processing ? null : () => _rotate(false),
                    )),
                    const SizedBox(width: 10),
                    Expanded(child: _ToolButton(
                      icon: Icons.rotate_right_rounded,
                      label: 'Rotate R',
                      onTap: _processing ? null : () => _rotate(true),
                    )),
                  ]),
                ),

                // FILTER ROW
                Padding(
                  padding: const EdgeInsets.fromLTRB(16, 4, 16, 4),
                  child: Align(
                    alignment: Alignment.centerLeft,
                    child: Text('FILTERS',
                        style: TextStyle(
                          color: Colors.grey.shade500,
                          fontSize: 10,
                          fontWeight: FontWeight.w700,
                          letterSpacing: 1.5,
                        )),
                  ),
                ),
                SizedBox(
                  height: 72,
                  child: ListView.separated(
                    scrollDirection: Axis.horizontal,
                    padding: const EdgeInsets.fromLTRB(16, 4, 16, 12),
                    itemCount: _filters.length,
                    separatorBuilder: (_, __) => const SizedBox(width: 10),
                    itemBuilder: (ctx, i) {
                      final f = _filters[i];
                      final selected = _selectedFilter == i;
                      return GestureDetector(
                        onTap: _processing ? null : () => _setFilter(i),
                        child: AnimatedContainer(
                          duration: const Duration(milliseconds: 180),
                          padding: const EdgeInsets.symmetric(
                              horizontal: 16, vertical: 8),
                          decoration: BoxDecoration(
                            color: selected
                                ? _red
                                : Colors.white.withOpacity(0.08),
                            borderRadius: BorderRadius.circular(50),
                            border: Border.all(
                              color: selected
                                  ? _red
                                  : Colors.white.withOpacity(0.15),
                            ),
                          ),
                          child: Row(mainAxisSize: MainAxisSize.min, children: [
                            Icon(f.icon,
                                color: Colors.white, size: 16),
                            const SizedBox(width: 6),
                            Text(f.label,
                                style: const TextStyle(
                                  color: Colors.white,
                                  fontSize: 12,
                                  fontWeight: FontWeight.w600,
                                )),
                          ]),
                        ),
                      );
                    },
                  ),
                ),
                SizedBox(height: MediaQuery.of(context).padding.bottom),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _Filter {
  final String label;
  final IconData icon;
  const _Filter(this.label, this.icon);
}

class _ToolButton extends StatelessWidget {
  final IconData icon;
  final String label;
  final VoidCallback? onTap;
  const _ToolButton({required this.icon, required this.label, this.onTap});

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 10),
        decoration: BoxDecoration(
          color: Colors.white.withOpacity(0.08),
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: Colors.white.withOpacity(0.1)),
        ),
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          Icon(icon, color: Colors.white, size: 22),
          const SizedBox(height: 4),
          Text(label,
              style: TextStyle(
                color: Colors.grey.shade400,
                fontSize: 10,
                fontWeight: FontWeight.w600,
              )),
        ]),
      ),
    );
  }
}
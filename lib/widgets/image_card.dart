import 'dart:io';
import 'package:flutter/material.dart';

class ImageCard extends StatelessWidget {
  final File file;
  final int index;
  final bool isEdited;
  final VoidCallback onEdit;
  final VoidCallback onRemove;

  const ImageCard({
    super.key,
    required this.file,
    required this.index,
    required this.isEdited,
    required this.onEdit,
    required this.onRemove,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.only(bottom: 10),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: const Color(0xFFEEEEEE)),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.04),
            blurRadius: 8,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: Row(
        children: [
          // DRAG HANDLE
          const Padding(
            padding: EdgeInsets.symmetric(horizontal: 12),
            child: Icon(Icons.drag_handle_rounded,
                color: Color(0xFFCCCCCC), size: 22),
          ),

          // THUMBNAIL
          ClipRRect(
            borderRadius: BorderRadius.circular(10),
            child: Image.file(
              file,
              width: 64, height: 64,
              fit: BoxFit.cover,
            ),
          ),
          const SizedBox(width: 14),

          // INFO
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('Page ${index + 1}',
                    style: const TextStyle(
                      fontWeight: FontWeight.w700,
                      fontSize: 14,
                    )),
                const SizedBox(height: 3),
                if (isEdited)
                  Container(
                    padding: const EdgeInsets.symmetric(
                        horizontal: 8, vertical: 2),
                    decoration: BoxDecoration(
                      color: Colors.green.shade50,
                      borderRadius: BorderRadius.circular(4),
                    ),
                    child: const Text('Edited',
                        style: TextStyle(
                          color: Colors.green,
                          fontSize: 10,
                          fontWeight: FontWeight.w700,
                        )),
                  )
                else
                  Text(file.path.split('/').last,
                      style: const TextStyle(
                        color: Colors.grey, fontSize: 11,
                      ),
                      overflow: TextOverflow.ellipsis),
              ],
            ),
          ),

          // ACTIONS
          IconButton(
            icon: const Icon(Icons.tune_rounded,
                color: Color(0xFFE8192C), size: 20),
            onPressed: onEdit,
            tooltip: 'Edit',
          ),
          IconButton(
            icon: const Icon(Icons.close_rounded,
                color: Colors.grey, size: 20),
            onPressed: onRemove,
            tooltip: 'Remove',
          ),
          const SizedBox(width: 4),
        ],
      ),
    );
  }
}
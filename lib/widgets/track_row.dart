import 'package:flutter/material.dart';

class TrackRow extends StatelessWidget {
  final String title;
  final String artist;
  final String duration;
  final List<Color>? gradientColors;
  final String? imageUrl;
  final bool isFavorite;
  final VoidCallback? onTap;
  final VoidCallback? onPlayTap;
  final VoidCallback? onFavoriteTap;
  final VoidCallback? onEditTap;
  final VoidCallback? onDeleteTap;
  final VoidCallback? onDownloadTap;
  final VoidCallback? onUploadToDriveTap;
  final String? badge; // optional label like "✎ Local"
  final bool isLoading;

  const TrackRow({
    super.key,
    required this.title,
    required this.artist,
    required this.duration,
    this.gradientColors,
    this.imageUrl,
    this.isFavorite = false,
    this.onTap,
    this.onPlayTap,
    this.onFavoriteTap,
    this.onEditTap,
    this.onDeleteTap,
    this.onDownloadTap,
    this.onUploadToDriveTap,
    this.badge,
    this.isLoading = false,
  });

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(16),
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 8, horizontal: 4),
        child: Row(
          children: [
            ClipRRect(
              borderRadius: BorderRadius.circular(16),
              child: SizedBox(
                width: 56,
                height: 56,
                child: imageUrl != null && imageUrl!.isNotEmpty
                    ? Image.network(
                        imageUrl!,
                        fit: BoxFit.cover,
                        errorBuilder: (_, _, _) => Container(
                          decoration: BoxDecoration(
                            gradient: LinearGradient(
                              colors: gradientColors ??
                                  const [Color(0xFF0EA5E9), Color(0xFF8B5CF6)],
                            ),
                          ),
                          child: const Icon(Icons.music_note, color: Colors.white54),
                        ),
                      )
                    : Container(
                        decoration: BoxDecoration(
                          gradient: LinearGradient(
                            colors: gradientColors ??
                                const [Color(0xFF0EA5E9), Color(0xFF8B5CF6)],
                          ),
                        ),
                        child: const Icon(Icons.music_note_rounded, color: Colors.white38),
                      ),
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    title,
                    style: const TextStyle(
                      color: Colors.white,
                      fontSize: 15,
                      fontWeight: FontWeight.w700,
                    ),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                  const SizedBox(height: 2),
                  Row(
                    children: [
                      Flexible(
                        child: Text(
                          artist,
                          style: const TextStyle(color: Colors.white70, fontSize: 13),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                      if (badge != null) ...[
                        const SizedBox(width: 6),
                        Container(
                          padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                          decoration: BoxDecoration(
                            color: const Color(0xFF8B5CF6).withValues(alpha: 0.25),
                            borderRadius: BorderRadius.circular(6),
                            border: Border.all(color: const Color(0xFF8B5CF6).withValues(alpha: 0.5)),
                          ),
                          child: Text(
                            badge!,
                            style: const TextStyle(
                              color: Color(0xFFC4B5FD),
                              fontSize: 9,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                        ),
                      ],
                    ],
                  ),
                ],
              ),
            ),
            const SizedBox(width: 8),
            Text(
              duration,
              style: const TextStyle(color: Colors.white60, fontSize: 12),
            ),
            if (onFavoriteTap != null)
              IconButton(
                icon: Icon(
                  isFavorite ? Icons.favorite_rounded : Icons.favorite_border_rounded,
                  color: isFavorite ? const Color(0xFF8B5CF6) : Colors.white54,
                  size: 20,
                ),
                onPressed: onFavoriteTap,
              ),
            if (onEditTap != null || onDeleteTap != null || onDownloadTap != null || onUploadToDriveTap != null)
              PopupMenuButton<String>(
                icon: const Icon(Icons.more_vert_rounded, color: Colors.white60, size: 20),
                color: const Color(0xFF1E1035),
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
                onSelected: (val) {
                  if (val == 'edit') onEditTap?.call();
                  if (val == 'download') onDownloadTap?.call();
                  if (val == 'upload_drive') onUploadToDriveTap?.call();
                  if (val == 'delete') onDeleteTap?.call();
                },
                itemBuilder: (ctx) => [
                  if (onEditTap != null)
                    const PopupMenuItem(
                      value: 'edit',
                      child: Row(
                        children: [
                          Icon(Icons.edit_note_rounded, color: Color(0xFF8B5CF6), size: 20),
                          SizedBox(width: 10),
                          Text('Edit Lagu & Lirik', style: TextStyle(color: Colors.white, fontSize: 13)),
                        ],
                      ),
                    ),
                  if (onUploadToDriveTap != null)
                    const PopupMenuItem(
                      value: 'upload_drive',
                      child: Row(
                        children: [
                          Icon(Icons.cloud_upload_rounded, color: Color(0xFFD9F99D), size: 20),
                          SizedBox(width: 10),
                          Text('Upload ke Google Drive', style: TextStyle(color: Colors.white, fontSize: 13)),
                        ],
                      ),
                    ),
                  if (onDownloadTap != null)
                    const PopupMenuItem(
                      value: 'download',
                      child: Row(
                        children: [
                          Icon(Icons.cloud_download_rounded, color: Color(0xFF10B981), size: 20),
                          SizedBox(width: 10),
                          Text('Unduh Offline & Cloud', style: TextStyle(color: Colors.white, fontSize: 13)),
                        ],
                      ),
                    ),
                  if (onDeleteTap != null)
                    const PopupMenuItem(
                      value: 'delete',
                      child: Row(
                        children: [
                          Icon(Icons.delete_outline_rounded, color: Colors.redAccent, size: 20),
                          SizedBox(width: 10),
                          Text('Hapus Lagu', style: TextStyle(color: Colors.redAccent, fontSize: 13)),
                        ],
                      ),
                    ),
                ],
              ),
            GestureDetector(
              onTap: isLoading ? null : onPlayTap,
              child: Container(
                width: 38,
                height: 38,
                decoration: BoxDecoration(
                  color: isLoading
                      ? const Color(0xFF8B5CF6).withValues(alpha: 0.15)
                      : Colors.white.withValues(alpha: 0.08),
                  shape: BoxShape.circle,
                ),
                child: isLoading
                    ? const Padding(
                        padding: EdgeInsets.all(9.0),
                        child: CircularProgressIndicator(
                          strokeWidth: 2.2,
                          color: Color(0xFF8B5CF6),
                        ),
                      )
                    : const Icon(
                        Icons.play_arrow_rounded,
                        color: Colors.white,
                        size: 22,
                      ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}


import 'package:material_ui/material_ui.dart';
import 'package:flutter_svg/flutter_svg.dart';
import 'package:folio/api/entity/models.dart';
import 'package:folio/theme/folio_theme.dart';

/// 与作品详情页一致的评分胶囊。
class RatingChip extends StatelessWidget {
  const RatingChip({super.key, required this.rating});

  final WorkRating rating;

  @override
  Widget build(BuildContext context) {
    final logo = rating.logoAsset;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        color: const Color(0x0AFFFFFF),
        borderRadius: BorderRadius.circular(999),
        border: Border.all(color: FolioColors.lineStrong),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (logo != null) ...[
            _ProviderLogo(asset: logo),
            const SizedBox(width: 5),
          ] else
            Padding(
              padding: const EdgeInsets.only(right: 5),
              child: Text(
                rating.label,
                style: const TextStyle(fontSize: 12, color: FolioColors.inkMuted),
              ),
            ),
          Text(
            rating.display,
            style: const TextStyle(fontSize: 12, color: FolioColors.ink),
          ),
        ],
      ),
    );
  }
}

class _ProviderLogo extends StatelessWidget {
  const _ProviderLogo({required this.asset});

  final String asset;

  @override
  Widget build(BuildContext context) {
    if (asset.endsWith('.svg')) {
      return SvgPicture.asset(asset, height: 14);
    }
    return Image.asset(asset, height: 14);
  }
}

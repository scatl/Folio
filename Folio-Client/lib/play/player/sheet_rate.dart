part of '../player_page.dart';

extension _PlayerRateSheet on _PlayerPageState {
  String _rateLabel(double rate) {
    if (rate == rate.roundToDouble()) return '${rate.toInt()}×';
    return '$rate×';
  }

  Future<void> _applyPlaybackRate(double rate) async {
    if ((rate - _playbackRate).abs() < 0.01) return;
    _playbackRate = rate;
    _update(() {});
    if (!_boosting) await _player.setRate(rate);
  }

  Widget _buildRatePanel() {
    const rates = <double>[0.5, 0.75, 1, 1.5, 2, 3, 4];
    return ListView(
      padding: EdgeInsets.zero,
      children: [
        for (final rate in rates)
          _settingsTile(
            title: _rateLabel(rate),
            selected: (rate - _playbackRate).abs() < 0.01,
            onTap: () => _applyPlaybackRate(rate),
          ),
      ],
    );
  }

  Future<void> _showPlaybackRate() async {
    if (_embedSettingsInSidePanel) {
      _openSidePanelPage(_SplitKind.rate);
      return;
    }
    const rates = <double>[0.5, 0.75, 1, 1.5, 2, 3, 4];
    final selected = await _showSheet<double>(
      (context) => ListView(
        shrinkWrap: true,
        padding: EdgeInsets.zero,
        children: [
          const Padding(
            padding: EdgeInsets.fromLTRB(14, 12, 14, 4),
            child: Text('倍速', style: TextStyle(fontSize: 16, fontWeight: FontWeight.w600)),
          ),
          for (final rate in rates)
            _settingsTile(
              title: _rateLabel(rate),
              selected: (rate - _playbackRate).abs() < 0.01,
              onTap: () => Navigator.pop(context, rate),
            ),
        ],
      ),
    );
    if (selected == null || !mounted) return;
    await _applyPlaybackRate(selected);
  }
}

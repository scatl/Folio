part of '../player_page.dart';

extension _PlayerHardwareSheet on _PlayerPageState {
  Future<void> _applyHardwareDecode(bool enabled) async {
    if (enabled == _PlayerPageState._hardwareDecode) return;
    _PlayerPageState._hardwareDecode = enabled;
    final position = _scrubbing ? _seekPreview : _position;
    if (position > Duration.zero) _pendingResume = position;
    _update(() {});
    await _open();
  }

  Widget _buildDecodePanel() {
    final hw = _PlayerPageState._hardwareDecode;
    return ListView(
      padding: EdgeInsets.zero,
      children: [
        _settingsTile(
          title: '硬解',
          subtitle: '省电，高码率更流畅',
          leading: const Icon(Icons.memory),
          selected: hw,
          onTap: () => _applyHardwareDecode(true),
        ),
        _settingsTile(
          title: '软解',
          subtitle: '兼容性更好，更吃性能',
          leading: const Icon(Icons.memory_outlined),
          selected: !hw,
          onTap: () => _applyHardwareDecode(false),
        ),
      ],
    );
  }

  Future<void> _showHardwareDecode() async {
    if (_embedSettingsInSidePanel) {
      _openSidePanelPage(_SplitKind.decode);
      return;
    }
    final selected = await _showSheet(
      (context) {
        final hw = _PlayerPageState._hardwareDecode;
        return ListView(
          shrinkWrap: true,
          padding: EdgeInsets.zero,
          children: [
            const Padding(
              padding: EdgeInsets.fromLTRB(14, 12, 14, 4),
              child: Text('解码', style: TextStyle(fontSize: 16, fontWeight: FontWeight.w600)),
            ),
            _settingsTile(
              title: '硬解',
              subtitle: '省电，高码率更流畅',
              leading: const Icon(Icons.memory),
              selected: hw,
              onTap: () => Navigator.pop(context, true),
            ),
            _settingsTile(
              title: '软解',
              subtitle: '兼容性更好，更吃性能',
              leading: const Icon(Icons.memory_outlined),
              selected: !hw,
              onTap: () => Navigator.pop(context, false),
            ),
          ],
        );
      },
    );
    if (selected == null || !mounted) return;
    await _applyHardwareDecode(selected);
  }
}

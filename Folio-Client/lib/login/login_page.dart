import 'dart:math' as math;
import 'dart:ui';

import 'package:cached_network_image/cached_network_image.dart';
import 'package:material_ui/material_ui.dart';
import 'package:flutter/scheduler.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:folio/login/login_page_view_model.dart';
import 'package:folio/session/session_view_model.dart';
import 'package:folio/theme/folio_theme.dart';
import 'package:folio/widget/folio_widgets.dart';

part 'poster_stage.dart';

class LoginPage extends ConsumerStatefulWidget {
  const LoginPage({super.key});

  @override
  ConsumerState<LoginPage> createState() => _LoginPageState();
}

class _LoginPageState extends ConsumerState<LoginPage> with TickerProviderStateMixin {
  late final TextEditingController _server;
  late final TextEditingController _username;
  late final TextEditingController _password;
  late final AnimationController _enter;
  late final AnimationController _ambient;
  late final Animation<double> _veil;
  late final Animation<double> _eyebrow;
  late final Animation<double> _brand;
  late final Animation<double> _underline;
  late final Animation<double> _blurb;
  late final Animation<double> _fields;
  late final Animation<double> _action;
  bool _showPassword = false;

  @override
  void initState() {
    super.initState();
    final session = ref.read(sessionProvider);
    _server = TextEditingController(text: session.serverUrl);
    _username = TextEditingController(text: session.username);
    _password = TextEditingController();
    _enter = AnimationController(vsync: this, duration: const Duration(milliseconds: 1200));
    _ambient = AnimationController(vsync: this, duration: const Duration(milliseconds: 5200))
      ..repeat(reverse: true);
    _veil = _slot(0.0, 0.35, Curves.easeOut);
    _eyebrow = _slot(0.08, 0.42, Curves.easeOutCubic);
    _brand = _slot(0.14, 0.55, Curves.easeOutCubic);
    _underline = _slot(0.32, 0.72, Curves.easeOutCubic);
    _blurb = _slot(0.28, 0.62, Curves.easeOutCubic);
    _fields = _slot(0.38, 0.82, Curves.easeOutCubic);
    _action = _slot(0.52, 0.95, Curves.easeOutCubic);
    _enter.forward();
    Future.microtask(
      () => ref.read(loginPageProvider.notifier).loadPosters(_server.text),
    );
  }

  Animation<double> _slot(double begin, double end, Curve curve) {
    return CurvedAnimation(
      parent: _enter,
      curve: Interval(begin, end, curve: curve),
    );
  }

  @override
  void dispose() {
    _enter.dispose();
    _ambient.dispose();
    _server.dispose();
    _username.dispose();
    _password.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final ui = ref.watch(loginPageProvider);
    final canSubmit =
        _username.text.trim().isNotEmpty &&
        _password.text.isNotEmpty &&
        !ui.submitting;
    return FolioBackdrop(
      child: Scaffold(
        backgroundColor: Colors.transparent,
        resizeToAvoidBottomInset: false,
        body: Stack(
          children: [
            Positioned.fill(child: _PosterStage(urls: ui.posters)),
            Positioned.fill(
              child: AnimatedBuilder(
                animation: _veil,
                builder: (context, _) {
                  final t = _veil.value;
                  return ColoredBox(
                    color: Color.lerp(
                      const Color(0xFF080A0E),
                      const Color(0xEE080A0E),
                      t,
                    )!,
                  );
                },
              ),
            ),
            Positioned.fill(
              child: AnimatedBuilder(
                animation: _ambient,
                builder: (context, _) {
                  final pulse = 0.55 + 0.45 * _ambient.value;
                  return IgnorePointer(
                    child: DecoratedBox(
                      decoration: BoxDecoration(
                        gradient: RadialGradient(
                          center: const Alignment(-0.55, -0.72),
                          radius: 1.15,
                          colors: [
                            Color.fromRGBO(95, 179, 168, 0.14 * pulse),
                            Color.fromRGBO(212, 165, 116, 0.08 * pulse),
                            Colors.transparent,
                          ],
                          stops: const [0, 0.42, 1],
                        ),
                      ),
                    ),
                  );
                },
              ),
            ),
            SafeArea(
              child: _FormInset(
                child: ListView(
                  padding: const EdgeInsets.fromLTRB(24, 36, 24, 28),
                  children: [
                    _Reveal(
                      animation: _eyebrow,
                      child: const Text(
                        'SELF-HOSTED LIBRARY',
                        style: TextStyle(
                          color: FolioColors.teal,
                          letterSpacing: 2.2,
                          fontSize: 12,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                    ),
                    const SizedBox(height: 10),
                    _Reveal(
                      animation: _brand,
                      slide: 28,
                      child: Text('Folio', style: folioDisplay(size: 64)),
                    ),
                    AnimatedBuilder(
                      animation: _underline,
                      builder: (context, _) {
                        final t = Curves.easeOutCubic.transform(_underline.value);
                        return Padding(
                          padding: const EdgeInsets.only(top: 10),
                          child: Align(
                            alignment: Alignment.centerLeft,
                            child: SizedBox(
                              width: 72 * t,
                              height: 2,
                              child: const DecoratedBox(
                                decoration: BoxDecoration(
                                  borderRadius: BorderRadius.all(Radius.circular(99)),
                                  gradient: LinearGradient(
                                    colors: [FolioColors.copper, FolioColors.teal],
                                  ),
                                ),
                              ),
                            ),
                          ),
                        );
                      },
                    ),
                    const SizedBox(height: 12),
                    _Reveal(
                      animation: _blurb,
                      child: const Text(
                        '进入你的私人影库。海报、刮削与整理都在这里。',
                        style: TextStyle(
                          color: FolioColors.inkMuted,
                          height: 1.5,
                          fontSize: 16,
                        ),
                      ),
                    ),
                    const SizedBox(height: 28),
                    _Reveal(
                      animation: _fields,
                      slide: 22,
                      child: Column(
                        children: [
                          _Field(
                            label: '服务端地址',
                            child: TextField(
                              controller: _server,
                              keyboardType: TextInputType.url,
                              autocorrect: false,
                              textInputAction: TextInputAction.next,
                              decoration: _inputDecoration('例如 192.168.1.8:32700'),
                              onEditingComplete: () => ref
                                  .read(loginPageProvider.notifier)
                                  .loadPosters(_server.text),
                            ),
                          ),
                          const SizedBox(height: 14),
                          _Field(
                            label: '用户名',
                            child: TextField(
                              controller: _username,
                              autocorrect: false,
                              textInputAction: TextInputAction.next,
                              decoration: _inputDecoration(null),
                              onChanged: (_) => setState(() {}),
                            ),
                          ),
                          const SizedBox(height: 14),
                          _Field(
                            label: '密码',
                            child: TextField(
                              controller: _password,
                              obscureText: !_showPassword,
                              textInputAction: TextInputAction.done,
                              decoration: _inputDecoration(null).copyWith(
                                suffixIcon: TextButton(
                                  onPressed: () =>
                                      setState(() => _showPassword = !_showPassword),
                                  child: Text(_showPassword ? '隐藏' : '显示'),
                                ),
                              ),
                              onChanged: (_) => setState(() {}),
                              onSubmitted: (_) {
                                if (canSubmit) _submit();
                              },
                            ),
                          ),
                        ],
                      ),
                    ),
                    if (ui.error != null) ...[
                      const SizedBox(height: 12),
                      Text(
                        ui.error!,
                        style: const TextStyle(color: FolioColors.danger),
                      ),
                    ],
                    const SizedBox(height: 18),
                    _Reveal(
                      animation: _action,
                      slide: 16,
                      child: FilledButton(
                        onPressed: canSubmit ? _submit : null,
                        style: FilledButton.styleFrom(
                          backgroundColor: FolioColors.copper,
                          disabledBackgroundColor: const Color(0xFF3A332C),
                          foregroundColor: const Color(0xFF1A1208),
                          minimumSize: const Size.fromHeight(52),
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(14),
                          ),
                        ),
                        child: Text(
                          ui.submitting ? '正在进入…' : '进入影库',
                          style: const TextStyle(
                            fontWeight: FontWeight.w700,
                            fontSize: 16,
                          ),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  void _submit() {
    ref
        .read(loginPageProvider.notifier)
        .submit(
          server: _server.text,
          username: _username.text,
          password: _password.text,
        );
  }
}

class _Reveal extends StatelessWidget {
  const _Reveal({
    required this.animation,
    required this.child,
    this.slide = 18,
  });

  final Animation<double> animation;
  final Widget child;
  final double slide;

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: animation,
      builder: (context, child) {
        final t = animation.value;
        return Opacity(
          opacity: t.clamp(0.0, 1.0),
          child: Transform.translate(
            offset: Offset(0, slide * (1 - t)),
            child: child,
          ),
        );
      },
      child: child,
    );
  }
}

class _Field extends StatelessWidget {
  const _Field({required this.label, required this.child});

  final String label;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          label,
          style: const TextStyle(color: FolioColors.inkMuted, fontSize: 13),
        ),
        const SizedBox(height: 6),
        child,
      ],
    );
  }
}

InputDecoration _inputDecoration(String? hint) {
  return InputDecoration(
    hintText: hint,
    hintStyle: const TextStyle(color: FolioColors.inkFaint),
    filled: true,
    fillColor: const Color(0xF212151C),
    contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
    border: OutlineInputBorder(
      borderRadius: BorderRadius.circular(14),
      borderSide: const BorderSide(color: FolioColors.lineStrong),
    ),
    enabledBorder: OutlineInputBorder(
      borderRadius: BorderRadius.circular(14),
      borderSide: const BorderSide(color: FolioColors.lineStrong),
    ),
    focusedBorder: OutlineInputBorder(
      borderRadius: BorderRadius.circular(14),
      borderSide: const BorderSide(color: FolioColors.copper),
    ),
  );
}

class _FormInset extends StatelessWidget {
  const _FormInset({required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context) {
    final bottom = MediaQuery.viewInsetsOf(context).bottom;
    return Padding(
      padding: EdgeInsets.only(bottom: bottom),
      child: child,
    );
  }
}

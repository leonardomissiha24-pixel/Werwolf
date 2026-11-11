import 'package:flutter/services.dart';
import 'package:material_ui/material_ui.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../services/room_repository.dart';
import '../../theme.dart';
import '../widgets/atmosphere.dart';
import 'room_screen.dart';
import 'rules_screen.dart';

class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key, this.initError});
  final String? initError;

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  final _name = TextEditingController();
  bool _busy = false;

  @override
  void initState() {
    super.initState();
    SharedPreferences.getInstance().then((p) {
      final n = p.getString('name');
      if (n != null && mounted) _name.text = n;
    });
  }

  @override
  void dispose() {
    _name.dispose();
    super.dispose();
  }

  void _toast(String msg) =>
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(msg)));

  Future<String?> _validName() async {
    final n = _name.text.trim();
    if (n.isEmpty) {
      _toast('Wie lautet dein Name, Fremder?');
      return null;
    }
    (await SharedPreferences.getInstance()).setString('name', n);
    return n;
  }

  Future<void> _permissions() async {
    try {
      await [Permission.camera, Permission.microphone].request();
    } catch (_) {
      // Am PC fragt Windows selbst beim ersten Kamerazugriff.
    }
  }

  Future<void> _create() async {
    final n = await _validName();
    if (n == null) return;
    setState(() => _busy = true);
    try {
      await _permissions();
      final code = await RoomRepository.instance.createRoom(n);
      if (!mounted) return;
      await Navigator.of(context).push(_fade(RoomScreen(code: code)));
    } catch (e) {
      _toast('Fehler: $e');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _join() async {
    final n = await _validName();
    if (n == null || !mounted) return;
    final code = await showDialog<String>(context: context, builder: (_) => const _CodeDialog());
    if (code == null || code.isEmpty) return;
    setState(() => _busy = true);
    try {
      await _permissions();
      await RoomRepository.instance.joinRoom(code, n);
      if (!mounted) return;
      await Navigator.of(context).push(_fade(RoomScreen(code: code)));
    } catch (e) {
      _toast(e is RoomException ? e.message : 'Fehler: $e');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Route _fade(Widget page) => PageRouteBuilder(
        transitionDuration: const Duration(milliseconds: 900),
        pageBuilder: (_, _, _) => page,
        transitionsBuilder: (_, a, _, child) => FadeTransition(opacity: a, child: child),
      );

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context).textTheme;
    return Scaffold(
      resizeToAvoidBottomInset: true,
      body: Atmosphere(
        child: SafeArea(
          child: Center(
            child: SingleChildScrollView(
              padding: const EdgeInsets.symmetric(horizontal: 28, vertical: 24),
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 420),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    const SizedBox(height: 80),
                    Text('WERWOLF',
                        textAlign: TextAlign.center,
                        style: t.displayLarge?.copyWith(fontSize: 46, shadows: const [
                          Shadow(color: AppColors.blood, blurRadius: 24),
                        ])),
                    const SizedBox(height: 4),
                    const Text(
                      'B L U T M O N D',
                      textAlign: TextAlign.center,
                      style: TextStyle(
                          fontFamily: AppText.display,
                          color: AppColors.bloodBright,
                          letterSpacing: 6,
                          fontSize: 13),
                    ),
                    const SizedBox(height: 18),
                    const Center(child: BloodDivider(width: 220)),
                    const SizedBox(height: 14),
                    const Text(
                      'Nachts sind nicht alle Augen geschlossen.',
                      textAlign: TextAlign.center,
                      style: TextStyle(fontStyle: FontStyle.italic, color: AppColors.ash, fontSize: 18),
                    ),
                    const SizedBox(height: 44),
                    if (widget.initError != null)
                      Container(
                        padding: const EdgeInsets.all(12),
                        margin: const EdgeInsets.only(bottom: 18),
                        decoration: BoxDecoration(border: Border.all(color: AppColors.blood)),
                        child: Text(
                          'Keine Verbindung zum Server. Prüfe die Internetverbindung '
                          'bzw. die Firebase-Konfiguration.\n\n${widget.initError}',
                          style: const TextStyle(color: AppColors.ash),
                        ),
                      ),
                    TextField(
                      controller: _name,
                      maxLength: 16,
                      textCapitalization: TextCapitalization.words,
                      style: const TextStyle(fontSize: 20),
                      decoration: const InputDecoration(labelText: 'DEIN NAME', counterText: ''),
                    ),
                    const SizedBox(height: 20),
                    GothicButton(
                      label: 'Ein Dorf gründen',
                      icon: Icons.local_fire_department,
                      onPressed: _busy || widget.initError != null ? null : _create,
                    ),
                    const SizedBox(height: 12),
                    GothicButton(
                      label: 'Einem Dorf beitreten',
                      icon: Icons.door_front_door,
                      primary: false,
                      onPressed: _busy || widget.initError != null ? null : _join,
                    ),
                    const SizedBox(height: 12),
                    GothicButton(
                      label: 'Regeln & Gestalten',
                      icon: Icons.menu_book,
                      primary: false,
                      onPressed: () => Navigator.of(context)
                          .push(MaterialPageRoute(builder: (_) => const RulesScreen())),
                    ),
                    if (_busy)
                      const Padding(
                        padding: EdgeInsets.only(top: 24),
                        child: Center(
                          child: SizedBox(
                            width: 22,
                            height: 22,
                            child: CircularProgressIndicator(strokeWidth: 1.5, color: AppColors.bloodBright),
                          ),
                        ),
                      ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _CodeDialog extends StatefulWidget {
  const _CodeDialog();
  @override
  State<_CodeDialog> createState() => _CodeDialogState();
}

class _CodeDialogState extends State<_CodeDialog> {
  final _c = TextEditingController();

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('DORFCODE', style: TextStyle(fontFamily: AppText.display, letterSpacing: 3)),
      content: TextField(
        controller: _c,
        autofocus: true,
        maxLength: 5,
        textAlign: TextAlign.center,
        textCapitalization: TextCapitalization.characters,
        inputFormatters: [
          FilteringTextInputFormatter.allow(RegExp('[a-zA-Z0-9]')),
          TextInputFormatter.withFunction((o, n) => n.copyWith(text: n.text.toUpperCase())),
        ],
        style: const TextStyle(fontFamily: AppText.display, fontSize: 28, letterSpacing: 10),
        decoration: const InputDecoration(counterText: ''),
        onSubmitted: (v) => Navigator.of(context).pop(v.trim().toUpperCase()),
      ),
      actions: [
        TextButton(onPressed: () => Navigator.of(context).pop(), child: const Text('Abbrechen')),
        TextButton(
          onPressed: () => Navigator.of(context).pop(_c.text.trim().toUpperCase()),
          child: const Text('Eintreten', style: TextStyle(color: AppColors.bloodBright)),
        ),
      ],
    );
  }
}

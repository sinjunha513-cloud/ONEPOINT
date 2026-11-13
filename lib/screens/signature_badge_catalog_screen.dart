import 'dart:async';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';

import '../config/signature_badge_palette.dart';
import '../models/signature_badge.dart';
import '../services/signature_badge_service.dart';
import '../widget/lesson_badge_emblem.dart';

class SignatureBadgePickResult {
  const SignatureBadgePickResult(
    this.badge, {
    this.created = false,
    this.duplicateCreation = false,
  });

  final SignatureBadge badge;
  final bool created;
  final bool duplicateCreation;
}

class SignatureBadgeCatalogScreen extends StatefulWidget {
  const SignatureBadgeCatalogScreen({
    super.key,
    this.selectionMode = false,
    this.initialBadgeId,
    this.sport = '',
    this.auth,
    this.firestore,
    this.service,
  });

  final bool selectionMode;
  final String? initialBadgeId;
  final String sport;
  final FirebaseAuth? auth;
  final FirebaseFirestore? firestore;
  final SignatureBadgeService? service;

  @override
  State<SignatureBadgeCatalogScreen> createState() =>
      _SignatureBadgeCatalogScreenState();
}

class _SignatureBadgeCatalogScreenState
    extends State<SignatureBadgeCatalogScreen> {
  static const _background = Color(0xFF070D1B);
  static const _surface = Color(0xFF101A2C);
  static const _muted = Color(0xFFABB5C8);

  late final SignatureBadgeService _service;
  late Stream<List<SignatureBadge>> _catalog;
  final _searchController = TextEditingController();
  String _search = '';
  String? _selectedBadgeId;
  bool _busy = false;
  StreamSubscription<String?>? _selectionSubscription;

  @override
  void initState() {
    super.initState();
    _service = widget.service ??
        SignatureBadgeService(auth: widget.auth, firestore: widget.firestore);
    _catalog = _service.watchCatalog();
    _selectedBadgeId = widget.initialBadgeId;
    if (!widget.selectionMode) {
      _selectionSubscription =
          _service.watchCurrentSelection().listen((badgeId) {
        if (mounted) setState(() => _selectedBadgeId = badgeId);
      });
    }
  }

  @override
  void dispose() {
    _selectionSubscription?.cancel();
    _searchController.dispose();
    super.dispose();
  }

  Future<void> _createBadge() async {
    if (_busy) return;
    final name = await showDialog<String>(
      context: context,
      builder: (context) => const _CreateSignatureBadgeDialog(),
    );
    if (name == null || !mounted) return;
    setState(() => _busy = true);
    try {
      final result = await _service.createOrGet(name);
      if (!mounted) return;
      if (widget.selectionMode) {
        Navigator.pop(
          context,
          SignatureBadgePickResult(
            result.badge,
            created: result.created,
            duplicateCreation: !result.created,
          ),
        );
        return;
      }
      await _service.selectForCurrentCoach(result.badge);
      if (!mounted) return;
      setState(() => _selectedBadgeId = result.badge.id);
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
        content: Text(result.created
            ? '${result.badge.name} 뱃지를 만들고 내 시그니처로 등록했습니다.'
            : '이미 등록된 ${result.badge.name} 뱃지를 선택했습니다.'),
      ));
    } on ArgumentError catch (error) {
      _showError(error.message?.toString() ?? '뱃지 이름을 확인해 주세요.');
    } on StateError catch (error) {
      _showError(error.message.toString());
    } on FirebaseException catch (error) {
      _showError(_firebaseMessage(error));
    } catch (_) {
      _showError('시그니처 뱃지를 등록하지 못했습니다. 잠시 후 다시 시도해 주세요.');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _selectBadge(SignatureBadge badge) async {
    if (_busy) return;
    if (widget.selectionMode) {
      Navigator.pop(context, SignatureBadgePickResult(badge));
      return;
    }
    setState(() => _busy = true);
    try {
      await _service.selectForCurrentCoach(badge);
      if (!mounted) return;
      setState(() => _selectedBadgeId = badge.id);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('${badge.name} 뱃지를 내 시그니처로 등록했습니다.')),
      );
    } on StateError catch (error) {
      _showError(error.message.toString());
    } on FirebaseException catch (error) {
      _showError(_firebaseMessage(error));
    } catch (_) {
      _showError('뱃지를 선택하지 못했습니다. 잠시 후 다시 시도해 주세요.');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  void _showError(String message) {
    if (!mounted) return;
    ScaffoldMessenger.of(context)
        .showSnackBar(SnackBar(content: Text(message)));
  }

  String _firebaseMessage(FirebaseException error) => switch (error.code) {
        'permission-denied' => '시그니처 뱃지 등록 권한을 확인해 주세요.',
        'unavailable' ||
        'deadline-exceeded' ||
        'network-request-failed' =>
          '서버에 연결하지 못했습니다. 연결 상태를 확인해 주세요.',
        _ => '시그니처 뱃지를 처리하지 못했습니다. 잠시 후 다시 시도해 주세요.',
      };

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: _background,
      appBar: AppBar(
        backgroundColor: _background,
        title: Text(widget.selectionMode ? '시그니처 뱃지 선택' : '시그니처 뱃지 관리'),
      ),
      floatingActionButton: FloatingActionButton.extended(
        key: const ValueKey('create-signature-badge'),
        onPressed: _busy ? null : _createBadge,
        backgroundColor: const Color(0xFFC6FF00),
        foregroundColor: _background,
        icon: _busy
            ? const SizedBox.square(
                dimension: 18, child: CircularProgressIndicator(strokeWidth: 2))
            : const Icon(Icons.add_rounded),
        label: const Text('새로 만들기'),
      ),
      body: SafeArea(
        child: Column(
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 12, 20, 12),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    widget.selectionMode
                        ? '모든 코치가 함께 사용하는 뱃지입니다. 기존 뱃지를 선택하거나 한 단어로 새로 만드세요.'
                        : '등록된 뱃지는 모든 코치에게 공유됩니다. 같은 기술은 기존 뱃지를 선택해 주세요.',
                    style: const TextStyle(color: _muted, height: 1.5),
                  ),
                  const SizedBox(height: 14),
                  TextField(
                    key: const ValueKey('signature-badge-search'),
                    controller: _searchController,
                    onChanged: (value) =>
                        setState(() => _search = value.trim().toLowerCase()),
                    decoration: InputDecoration(
                      hintText: '뱃지 검색 (예: 드리블)',
                      prefixIcon: const Icon(Icons.search_rounded),
                      suffixIcon: _search.isEmpty
                          ? null
                          : IconButton(
                              tooltip: '검색어 지우기',
                              onPressed: () {
                                _searchController.clear();
                                setState(() => _search = '');
                              },
                              icon: const Icon(Icons.close_rounded),
                            ),
                      filled: true,
                      fillColor: _surface,
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(14),
                        borderSide: BorderSide.none,
                      ),
                    ),
                  ),
                ],
              ),
            ),
            Expanded(
              child: StreamBuilder<List<SignatureBadge>>(
                stream: _catalog,
                builder: (context, snapshot) {
                  if (snapshot.hasError) {
                    return _CatalogMessage(
                      icon: Icons.cloud_off_rounded,
                      title: '뱃지 목록을 불러오지 못했습니다.',
                      message: snapshot.error is FirebaseException
                          ? _firebaseMessage(
                              snapshot.error! as FirebaseException)
                          : '잠시 후 다시 시도해 주세요.',
                      onRetry: () => setState(() {
                        _catalog = _service.watchCatalog();
                      }),
                    );
                  }
                  if (!snapshot.hasData) {
                    return const Center(child: CircularProgressIndicator());
                  }
                  final badges = snapshot.data!
                      .where((badge) =>
                          _search.isEmpty ||
                          badge.name.toLowerCase().contains(_search))
                      .toList(growable: false);
                  if (badges.isEmpty) {
                    return _CatalogMessage(
                      icon: Icons.workspace_premium_outlined,
                      title: _search.isEmpty
                          ? '아직 등록된 뱃지가 없습니다.'
                          : '검색한 뱃지가 없습니다.',
                      message: _search.isEmpty
                          ? '새로 만들기를 눌러 첫 시그니처 뱃지를 등록해 보세요.'
                          : '같은 기술인지 다시 확인한 뒤, 없다면 새로 만들 수 있습니다.',
                    );
                  }
                  return LayoutBuilder(builder: (context, constraints) {
                    final columns = constraints.maxWidth >= 850
                        ? 4
                        : constraints.maxWidth >= 560
                            ? 3
                            : 2;
                    return GridView.builder(
                      padding: const EdgeInsets.fromLTRB(20, 4, 20, 100),
                      gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
                        crossAxisCount: columns,
                        crossAxisSpacing: 12,
                        mainAxisSpacing: 12,
                        childAspectRatio: .9,
                      ),
                      itemCount: badges.length,
                      itemBuilder: (context, index) {
                        final badge = badges[index];
                        return _SignatureBadgeCard(
                          badge: badge,
                          sport: widget.sport,
                          selected: badge.id == _selectedBadgeId,
                          busy: _busy,
                          onTap: () => _selectBadge(badge),
                        );
                      },
                    );
                  });
                },
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _SignatureBadgeCard extends StatelessWidget {
  const _SignatureBadgeCard({
    required this.badge,
    required this.sport,
    required this.selected,
    required this.busy,
    required this.onTap,
  });

  final SignatureBadge badge;
  final String sport;
  final bool selected;
  final bool busy;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final color = signatureBadgeColor(badge.colorIndex);
    return Material(
      color: const Color(0xFF101A2C),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(18),
        side: BorderSide(
          color: selected ? color : Colors.white10,
          width: selected ? 2 : 1,
        ),
      ),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        key: ValueKey('signature-badge-${badge.id}'),
        onTap: busy ? null : onTap,
        child: Padding(
          padding: const EdgeInsets.all(14),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              LessonBadgeEmblem(
                identity: badge.id,
                sport: sport,
                colorIndex: badge.colorIndex,
                size: 74,
              ),
              const SizedBox(height: 12),
              Text(
                badge.name,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(
                    color: Colors.white,
                    fontSize: 16,
                    fontWeight: FontWeight.w700),
              ),
              const SizedBox(height: 5),
              Text(
                selected ? '내 시그니처' : '선택하기',
                style: TextStyle(
                    color: selected ? color : const Color(0xFFABB5C8),
                    fontSize: 11,
                    fontWeight: selected ? FontWeight.w700 : FontWeight.w400),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _CreateSignatureBadgeDialog extends StatefulWidget {
  const _CreateSignatureBadgeDialog();

  @override
  State<_CreateSignatureBadgeDialog> createState() =>
      _CreateSignatureBadgeDialogState();
}

class _CreateSignatureBadgeDialogState
    extends State<_CreateSignatureBadgeDialog> {
  final _formKey = GlobalKey<FormState>();
  final _controller = TextEditingController();

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => AlertDialog(
        title: const Text('새 시그니처 뱃지'),
        content: Form(
          key: _formKey,
          child: TextFormField(
            key: const ValueKey('new-signature-badge-name'),
            controller: _controller,
            autofocus: true,
            maxLength: signatureBadgeNameMaxLength,
            textInputAction: TextInputAction.done,
            decoration: const InputDecoration(
              labelText: '기술 이름',
              hintText: '예: 드리블, 패스, Serve',
              helperText: '공백 없는 한 단어만 등록할 수 있습니다.',
              helperMaxLines: 2,
              border: OutlineInputBorder(),
            ),
            validator: (value) => signatureBadgeNameError(value ?? ''),
            onFieldSubmitted: (_) => _submit(),
          ),
        ),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(context), child: const Text('취소')),
          FilledButton(onPressed: _submit, child: const Text('등록')),
        ],
      );

  void _submit() {
    if (_formKey.currentState?.validate() != true) return;
    Navigator.pop(context, _controller.text.trim());
  }
}

class _CatalogMessage extends StatelessWidget {
  const _CatalogMessage({
    required this.icon,
    required this.title,
    required this.message,
    this.onRetry,
  });

  final IconData icon;
  final String title;
  final String message;
  final VoidCallback? onRetry;

  @override
  Widget build(BuildContext context) => Center(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(28),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(icon, size: 52, color: const Color(0xFFC6FF00)),
              const SizedBox(height: 16),
              Text(title,
                  textAlign: TextAlign.center,
                  style: const TextStyle(
                      color: Colors.white,
                      fontSize: 17,
                      fontWeight: FontWeight.w700)),
              const SizedBox(height: 8),
              Text(message,
                  textAlign: TextAlign.center,
                  style:
                      const TextStyle(color: Color(0xFFABB5C8), height: 1.5)),
              if (onRetry != null) ...[
                const SizedBox(height: 18),
                OutlinedButton(onPressed: onRetry, child: const Text('다시 시도')),
              ],
            ],
          ),
        ),
      );
}

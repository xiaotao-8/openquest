import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../../core/models/conversation.dart';
import '../../../core/models/group_chat_meta.dart';
import '../../../core/providers/assistant_provider.dart';
import '../../../core/services/chat/chat_service.dart';
import '../../../icons/lucide_adapter.dart';
import '../../../l10n/app_localizations.dart';
import '../../../shared/widgets/section_card.dart';
import '../../../theme/app_font_weights.dart';
import '../../model/widgets/model_select_sheet.dart';
import 'assistant_avatar.dart';

/// Create or edit a group chat, as a full settings-style page (same
/// design language as the app settings: black surface, grouped rounded
/// cards, iOS-style rows). The user names the group, picks which of
/// their own Bots join it, and chooses how models are assigned (each
/// Bot individually, or one model for the whole group). Groups are
/// never pre-created — this page is the only way one comes into
/// existence.
class CreateGroupDialog extends StatefulWidget {
  const CreateGroupDialog({super.key, this.existing});

  /// When non-null the page edits this group conversation instead of
  /// creating a new one.
  final Conversation? existing;

  static Future<String?> show(BuildContext context) {
    return Navigator.of(context).push<String>(
      MaterialPageRoute(builder: (_) => const CreateGroupDialog()),
    );
  }

  static Future<void> showEdit(
    BuildContext context,
    Conversation conversation,
  ) {
    return Navigator.of(context).push<void>(
      MaterialPageRoute(
        builder: (_) => CreateGroupDialog(existing: conversation),
      ),
    );
  }

  @override
  State<CreateGroupDialog> createState() => _CreateGroupDialogState();
}

class _CreateGroupDialogState extends State<CreateGroupDialog> {
  final _nameCtrl = TextEditingController();
  final Set<String> _selected = {};
  String? _error;
  bool _saving = false;

  String? _avatarPath;

  String _modelMode = GroupChatMeta.modelModeIndividual;
  ModelSelection? _unifiedModel;
  final Map<String, ModelSelection> _memberModels = {};

  bool get _isEdit => widget.existing != null;

  @override
  void initState() {
    super.initState();
    final existing = widget.existing;
    if (existing != null) {
      _nameCtrl.text = existing.title;
      final meta = GroupChatMeta.fromExtras(existing.extras);
      _selected.addAll(meta.memberIds);
      _avatarPath = meta.avatar;
      _modelMode = meta.modelMode;
      final unified = GroupChatMeta.parseModelRef(meta.unifiedModel);
      if (unified != null) {
        _unifiedModel = ModelSelection(unified.providerKey, unified.modelId);
      }
      for (final entry in meta.memberModels.entries) {
        final ref = GroupChatMeta.parseModelRef(entry.value);
        if (ref != null) {
          _memberModels[entry.key] = ModelSelection(
            ref.providerKey,
            ref.modelId,
          );
        }
      }
    }
  }

  @override
  void dispose() {
    _nameCtrl.dispose();
    super.dispose();
  }

  Future<void> _pickAvatar() async {
    final result = await FilePicker.platform.pickFiles(type: FileType.image);
    final path = result?.files.single.path;
    if (path == null || !mounted) return;
    setState(() => _avatarPath = path);
  }

  Future<void> _editName() async {
    final l10n = AppLocalizations.of(context)!;
    final ctrl = TextEditingController(text: _nameCtrl.text);
    final result = await showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(l10n.groupNameLabel),
        content: TextField(
          controller: ctrl,
          autofocus: true,
          decoration: InputDecoration(hintText: l10n.groupNameHint),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(),
            child: Text(l10n.homePageCancel),
          ),
          FilledButton(
            onPressed: () => Navigator.of(ctx).pop(ctrl.text),
            child: Text(l10n.groupSaveButton),
          ),
        ],
      ),
    );
    WidgetsBinding.instance.addPostFrameCallback((_) => ctrl.dispose());
    if (result == null || !mounted) return;
    setState(() {
      _nameCtrl.text = result;
      _error = null;
    });
  }

  Future<void> _newBot() async {
    final ap = context.read<AssistantProvider>();
    final id = await ap.addAssistant(context: context);
    if (!mounted) return;
    setState(() => _selected.add(id));
  }

  GroupChatMeta _buildMeta() {
    return GroupChatMeta(
      isGroup: true,
      memberIds: _selected.toList(),
      modelMode: _modelMode,
      unifiedModel: _unifiedModel == null
          ? null
          : GroupChatMeta.encodeModelRef(
              _unifiedModel!.providerKey,
              _unifiedModel!.modelId,
            ),
      avatar: _avatarPath,
      memberModels: {
        for (final e in _memberModels.entries)
          if (_selected.contains(e.key))
            e.key: GroupChatMeta.encodeModelRef(
              e.value.providerKey,
              e.value.modelId,
            ),
      },
    );
  }

  Future<void> _save() async {
    final l10n = AppLocalizations.of(context)!;
    final name = _nameCtrl.text.trim();
    if (name.isEmpty) {
      setState(() => _error = l10n.groupNameRequired);
      return;
    }
    if (_selected.isEmpty) {
      setState(() => _error = l10n.groupMembersRequired);
      return;
    }
    setState(() {
      _saving = true;
      _error = null;
    });
    final chatService = context.read<ChatService>();
    final meta = _buildMeta();
    if (_isEdit) {
      final id = widget.existing!.id;
      if (widget.existing!.title != name) {
        await chatService.renameConversation(id, name);
      }
      await chatService.updateConversationExtras(
        id,
        (extras) => meta.applyTo(extras),
      );
      if (!mounted) return;
      Navigator.of(context).pop();
      return;
    }
    final conversation = await chatService.createConversation(
      title: name,
      assistantId: null,
      activate: false,
    );
    await chatService.updateConversationExtras(
      conversation.id,
      (extras) => meta.applyTo(extras),
    );
    if (!mounted) return;
    Navigator.of(context).pop(conversation.id);
  }

  Future<void> _pickUnifiedModel() async {
    final sel = await showModelSelector(
      context,
      initialProviderKey: _unifiedModel?.providerKey,
      initialModelId: _unifiedModel?.modelId,
    );
    if (sel == null || sel.isInherit || !mounted) return;
    setState(() => _unifiedModel = sel);
  }

  Future<void> _pickMemberModel(String assistantId) async {
    final current = _memberModels[assistantId];
    final sel = await showModelSelector(
      context,
      initialProviderKey: current?.providerKey,
      initialModelId: current?.modelId,
      allowInherit: true,
      inheritLabel: AppLocalizations.of(context)!.groupModelUseOwn,
    );
    if (sel == null || !mounted) return;
    setState(() {
      if (sel.isInherit) {
        _memberModels.remove(assistantId);
      } else {
        _memberModels[assistantId] = sel;
      }
    });
  }

  /// One settings-style row: 36-wide leading slot, 15px medium label,
  /// optional 13px gray detail, check or chevron on the right — the same
  /// metrics as the settings page's nav rows.
  Widget _row({
    Widget? leading,
    IconData? icon,
    required String label,
    String? detail,
    bool checked = false,
    bool chevron = false,
    VoidCallback? onTap,
  }) {
    final cs = Theme.of(context).colorScheme;
    final base = cs.onSurface.withValues(alpha: 0.9);
    return InkWell(
      onTap: onTap,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 11),
        child: Row(
          children: [
            SizedBox(
              width: 36,
              child:
                  leading ??
                  (icon != null
                      ? Icon(icon, size: 20, color: base)
                      : const SizedBox.shrink()),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Text(
                label,
                style: TextStyle(
                  fontSize: 15,
                  color: base,
                  fontWeight: AppFontWeights.medium,
                ),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
            ),
            if (detail != null)
              Padding(
                padding: const EdgeInsets.only(right: 6),
                child: Text(
                  detail,
                  style: TextStyle(
                    fontSize: 13,
                    color: cs.onSurface.withValues(alpha: 0.6),
                  ),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
              ),
            if (checked)
              Icon(Lucide.Check, size: 18, color: base)
            else if (chevron)
              Icon(Lucide.ChevronRight, size: 16, color: base),
          ],
        ),
      ),
    );
  }

  Widget _divider(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Divider(
      height: 6,
      thickness: 0.6,
      indent: 54,
      endIndent: 12,
      color: cs.outlineVariant.withValues(alpha: 0.18),
    );
  }

  Widget _header(String text, {bool first = false}) {
    final cs = Theme.of(context).colorScheme;
    return Padding(
      padding: EdgeInsets.fromLTRB(12, first ? 2 : 12, 12, 6),
      child: Text(
        text,
        style: TextStyle(
          fontSize: 13,
          fontWeight: AppFontWeights.semibold,
          color: cs.onSurface.withValues(alpha: 0.8),
        ),
      ),
    );
  }

  String _memberModelDetail(String id, AppLocalizations l10n) {
    final own = _memberModels[id];
    if (own != null) return own.modelId;
    if (_modelMode == GroupChatMeta.modelModeUnified && _unifiedModel != null) {
      return _unifiedModel!.modelId;
    }
    return l10n.groupModelUseOwn;
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final cs = Theme.of(context).colorScheme;
    final ap = context.watch<AssistantProvider>();
    // Only Bots the user created themselves can join a group — the seeded
    // default assistant is the main-chat identity, not a team member. A
    // current member always stays listed so it can be managed/removed.
    final userCreatedIds = ap.userCreatedAssistants.map((a) => a.id).toSet();
    final assistants = [
      for (final a in ap.assistants)
        if (userCreatedIds.contains(a.id) || _selected.contains(a.id)) a,
    ];
    final byId = {for (final a in ap.assistants) a.id: a};
    final groupName = _nameCtrl.text.trim();
    return Scaffold(
      appBar: AppBar(
        leading: IconButton(
          icon: const Icon(Lucide.ArrowLeft, size: 22),
          tooltip: l10n.settingsPageBackButton,
          onPressed: () => Navigator.of(context).maybePop(),
        ),
        title: Text(_isEdit ? l10n.groupSettingsTitle : l10n.groupCreateTitle),
        actions: [
          TextButton(
            onPressed: _saving ? null : _save,
            child: Text(
              _isEdit ? l10n.groupSaveButton : l10n.groupCreateButton,
            ),
          ),
        ],
      ),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(16, 8, 16, 24),
        children: [
          _header(l10n.groupProfileSection, first: true),
          SectionCard(
            children: [
              _row(
                leading: GroupAvatar(
                  name: groupName.isEmpty ? '?' : groupName,
                  avatarPath: _avatarPath,
                  size: 30,
                ),
                label: l10n.groupAvatarLabel,
                detail: l10n.groupAvatarPick,
                chevron: true,
                onTap: _pickAvatar,
              ),
              if (_avatarPath != null) ...[
                _divider(context),
                _row(
                  label: l10n.groupAvatarClear,
                  onTap: () => setState(() => _avatarPath = null),
                ),
              ],
              _divider(context),
              _row(
                label: l10n.groupNameLabel,
                detail: groupName.isEmpty ? l10n.groupNameHint : groupName,
                chevron: true,
                onTap: _editName,
              ),
            ],
          ),
          _header(l10n.groupSelectMembers),
          SectionCard(
            children: [
              if (assistants.isEmpty)
                Padding(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 12,
                    vertical: 11,
                  ),
                  child: Text(
                    l10n.groupNoBots,
                    style: TextStyle(
                      fontSize: 14,
                      color: cs.onSurface.withValues(alpha: 0.6),
                    ),
                  ),
                )
              else
                for (var i = 0; i < assistants.length; i++) ...[
                  if (i > 0) _divider(context),
                  _row(
                    leading: AssistantAvatar(
                      assistant: assistants[i],
                      size: 30,
                    ),
                    label: assistants[i].name,
                    checked: _selected.contains(assistants[i].id),
                    onTap: () {
                      setState(() {
                        if (_selected.contains(assistants[i].id)) {
                          _selected.remove(assistants[i].id);
                        } else {
                          _selected.add(assistants[i].id);
                        }
                        _error = null;
                      });
                    },
                  ),
                ],
              _divider(context),
              _row(icon: Lucide.Plus, label: l10n.groupNewBot, onTap: _newBot),
            ],
          ),
          _header(l10n.groupModelSettingsTitle),
          SectionCard(
            children: [
              _row(
                label: l10n.groupModelModeIndividual,
                checked: _modelMode == GroupChatMeta.modelModeIndividual,
                onTap: () => setState(
                  () => _modelMode = GroupChatMeta.modelModeIndividual,
                ),
              ),
              _divider(context),
              _row(
                label: l10n.groupModelModeUnified,
                checked: _modelMode == GroupChatMeta.modelModeUnified,
                onTap: () =>
                    setState(() => _modelMode = GroupChatMeta.modelModeUnified),
              ),
              if (_modelMode == GroupChatMeta.modelModeUnified) ...[
                _divider(context),
                _row(
                  label: l10n.groupModelUnifiedLabel,
                  detail: _unifiedModel?.modelId ?? l10n.groupModelNotSet,
                  chevron: true,
                  onTap: _pickUnifiedModel,
                ),
              ],
              for (final id in _selected)
                if (byId[id] != null) ...[
                  _divider(context),
                  _row(
                    leading: AssistantAvatar(assistant: byId[id]!, size: 30),
                    label: byId[id]!.name,
                    detail: _memberModelDetail(id, l10n),
                    chevron: true,
                    onTap: () => _pickMemberModel(id),
                  ),
                ],
            ],
          ),
          if (_error != null)
            Padding(
              padding: const EdgeInsets.fromLTRB(12, 12, 12, 0),
              child: Text(
                _error!,
                style: TextStyle(fontSize: 13, color: cs.error),
              ),
            ),
        ],
      ),
    );
  }
}

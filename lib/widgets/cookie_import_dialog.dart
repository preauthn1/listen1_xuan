import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'dart:convert';

import '../funcs.dart';
import '../global_settings_animations.dart';
import '../provider/base.dart';

/// 直接导入网易云、QQ 音乐、哔哩哔哩等平台的 Cookie。
///
/// 支持粘贴请求头里的 `Cookie:` 行，或选择浏览器扩展导出的 JSON /
/// Netscape `cookies.txt` 文件。导入后立即校验登录状态。
Future<void> showCookieImportDialog(BuildContext context, BaseProvider provider) {
  return showDialog<void>(
    context: context,
    useRootNavigator: true,
    builder: (_) => _CookieImportDialog(provider: provider),
  );
}

class _CookieImportDialog extends StatefulWidget {
  const _CookieImportDialog({required this.provider});
  final BaseProvider provider;

  @override
  State<_CookieImportDialog> createState() => _CookieImportDialogState();
}

class _CookieImportDialogState extends State<_CookieImportDialog> {
  final _controller = TextEditingController();
  final _focusNode = FocusNode();
  late final bool _hotKeysEnabled;
  bool _saving = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    _hotKeysEnabled = enable_inapp_hotkey;
    // 输入时停用应用内快捷键，避免 W/S/空格 等被当成播放控制。
    _focusNode.addListener(() {
      setInAppHotKeyEnable(_focusNode.hasFocus ? false : _hotKeysEnabled);
    });
  }

  @override
  void dispose() {
    _focusNode.dispose();
    _controller.dispose();
    setInAppHotKeyEnable(_hotKeysEnabled);
    super.dispose();
  }

  Future<void> _paste() async {
    final data = await Clipboard.getData(Clipboard.kTextPlain);
    if (data?.text != null) {
      setState(() {
        _controller.text = data!.text!;
        _error = null;
      });
    }
  }

  Future<void> _pickFile() async {
    try {
      final file = await FilePicker.pickFile(
        type: FileType.custom,
        allowedExtensions: const ['txt', 'json'],
      );
      if (file == null) return;
      final bytes = await file.readAsBytes();
      if (bytes.length > 256 * 1024) {
        throw const FormatException('文件过大，请只导出目标站点的 Cookie');
      }
      setState(() {
        _controller.text = utf8.decode(bytes, allowMalformed: true);
        _error = null;
      });
    } catch (e) {
      setState(() => _error = _message(e));
    }
  }

  Future<void> _submit() async {
    if (_saving) return;
    setState(() {
      _saving = true;
      _error = null;
    });
    try {
      final count = await widget.provider.importCookies(_controller.text);
      if (!mounted) return;
      final user = widget.provider.currentUser.value;
      if (widget.provider.loginStatus.value == LoginStatus.loggedIn) {
        showSuccessSnackbar(
          '已导入 ${widget.provider.loginDisplayName} Cookie',
          user == null ? '共 $count 项' : '当前账号：${user.name}',
        );
      } else {
        showWarningSnackbar(
          '已保存 $count 项 Cookie',
          '但未能确认登录状态，Cookie 可能已过期',
        );
      }
      Navigator.of(context).pop();
    } catch (e) {
      if (mounted) setState(() => _error = _message(e));
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  String _message(Object e) => e is FormatException ? e.message : '$e';

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final required = widget.provider.requiredCookieNames;
    return AlertDialog(
      title: Text('导入${widget.provider.loginDisplayName} Cookie'),
      scrollable: true,
      content: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 480),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(
              '在浏览器登录后，从开发者工具复制请求头里的 Cookie，'
              '或选择 Cookie-Editor 等扩展导出的 JSON / cookies.txt 文件。'
              '只会保留该平台域名下的 Cookie。',
              style: theme.textTheme.bodySmall?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
              ),
            ),
            if (required.isNotEmpty) ...[
              const SizedBox(height: 6),
              Text(
                '必须包含：${required.join('、')}',
                style: theme.textTheme.bodySmall?.copyWith(
                  color: theme.colorScheme.onSurfaceVariant,
                ),
              ),
            ],
            const SizedBox(height: 12),
            TextField(
              controller: _controller,
              focusNode: _focusNode,
              minLines: 4,
              maxLines: 8,
              enableSuggestions: false,
              autocorrect: false,
              keyboardType: TextInputType.multiline,
              style: theme.textTheme.bodySmall?.copyWith(fontFamily: 'monospace'),
              decoration: InputDecoration(
                hintText: 'name=value; name2=value2',
                errorText: _error,
                errorMaxLines: 3,
                border: const OutlineInputBorder(),
              ),
              onChanged: (_) {
                if (_error != null) setState(() => _error = null);
              },
            ),
            const SizedBox(height: 8),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                OutlinedButton.icon(
                  onPressed: _saving ? null : _paste,
                  icon: const Icon(Icons.content_paste_rounded, size: 18),
                  label: const Text('粘贴'),
                ),
                OutlinedButton.icon(
                  onPressed: _saving ? null : _pickFile,
                  icon: const Icon(Icons.file_open_outlined, size: 18),
                  label: const Text('从文件导入'),
                ),
              ],
            ),
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: _saving ? null : () => Navigator.of(context).pop(),
          child: const Text('取消'),
        ),
        FilledButton(
          onPressed: _saving ? null : _submit,
          child: _saving
              ? const SizedBox.square(dimension: 18, child: CircularProgressIndicator(strokeWidth: 2))
              : const Text('导入并验证'),
        ),
      ],
    );
  }
}

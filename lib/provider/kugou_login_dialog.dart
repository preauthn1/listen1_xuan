import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:listen1_xuan/provider/kugou.dart';
import 'package:listen1_xuan/provider/kugou_gateway.dart';
import 'package:listen1_xuan/provider/kugou_sign.dart';

/// 酷狗扫码登录。二维码是官方服务返回的 PNG，轮询只携带二维码 key，确认后只保存
/// token/userid/dfid 这三个建立会话所需的 Cookie；不会记录二维码或用户资料。
class KugouLoginDialog extends StatefulWidget {
  const KugouLoginDialog({super.key, required this.provider, required this.gateway});
  final Kugou provider;
  final KugouGateway gateway;

  @override
  State<KugouLoginDialog> createState() => _KugouLoginDialogState();
}

class _KugouLoginDialogState extends State<KugouLoginDialog> {
  Timer? _timer;
  KugouQrCode? _code;
  Uint8List? _png;
  String _status = '正在获取二维码…';
  bool _busy = false;
  bool _done = false;
  int _generation = 0;

  @override
  void initState() {
    super.initState();
    _refresh();
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  Uint8List? _fromDataUri(String value) {
    final comma = value.indexOf(',');
    if (comma < 0 || !value.substring(0, comma).contains(';base64')) return null;
    try {
      return base64Decode(value.substring(comma + 1));
    } on FormatException {
      return null;
    }
  }

  Future<void> _refresh() async {
    if (_busy) return;
    final generation = ++_generation;
    _timer?.cancel();
    setState(() {
      _busy = true;
      _done = false;
      _code = null;
      _png = null;
      _status = '正在获取二维码…';
    });
    try {
      final code = await widget.gateway.createQr();
      if (!mounted || generation != _generation) return;
      final png = _fromDataUri(code.imageDataUri);
      if (png == null) throw const FormatException('二维码图片无效');
      setState(() {
        _code = code;
        _png = png;
        _busy = false;
        _status = '请使用酷狗音乐扫描二维码';
      });
      _timer = Timer.periodic(const Duration(seconds: 2), (_) => _poll(generation));
    } catch (_) {
      if (!mounted || generation != _generation) return;
      setState(() {
        _busy = false;
        _done = true;
        _status = '二维码获取失败，请刷新重试';
      });
    }
  }

  Future<void> _poll(int generation) async {
    final code = _code;
    if (_busy || _done || code == null) return;
    _busy = true;
    try {
      final result = await widget.gateway.checkQr(code.key, KugouSign.randomString(10));
      if (!mounted || generation != _generation) return;
      switch (result.code) {
        case 1:
          break;
        case 2:
          setState(() => _status = '已扫码，请在酷狗音乐中确认登录');
        case 4:
          final token = result.token ?? '';
          final userid = result.userid ?? '';
          if (token.isEmpty || userid.isEmpty) throw const FormatException('登录信息不完整');
          await widget.provider.saveToken('token=$token; userid=$userid; dfid=-');
          if (!mounted || generation != _generation) return;
          _done = true;
          _timer?.cancel();
          Navigator.of(context).pop();
        case 0:
          setState(() {
            _done = true;
            _status = '二维码已过期，请刷新';
          });
          _timer?.cancel();
        default:
          setState(() {
            _done = true;
            _status = '登录状态异常，请刷新重试';
          });
          _timer?.cancel();
      }
    } catch (_) {
      if (mounted && generation == _generation) setState(() => _status = '查询登录状态失败，正在重试…');
    } finally {
      _busy = false;
    }
  }

  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.fromLTRB(24, 24, 24, 16),
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          Text('酷狗音乐扫码登录', style: Theme.of(context).textTheme.titleLarge),
          const SizedBox(height: 20),
          SizedBox(
            height: 220,
            child: _png == null
                ? const Center(child: CircularProgressIndicator())
                : Container(color: Colors.white, padding: const EdgeInsets.all(10), child: Image.memory(_png!, gaplessPlayback: true)),
          ),
          const SizedBox(height: 16),
          Text(_status, textAlign: TextAlign.center),
          const SizedBox(height: 8),
          TextButton.icon(onPressed: _busy ? null : _refresh, icon: const Icon(Icons.refresh_rounded), label: const Text('刷新二维码')),
          const Text('请在酷狗音乐客户端确认登录。登录信息仅保存在本机。', textAlign: TextAlign.center),
        ]),
      );
}

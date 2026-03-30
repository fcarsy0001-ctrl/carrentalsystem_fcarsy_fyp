import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../services/support_ticket_service.dart';

class SupportChatPage extends StatefulWidget {
  const SupportChatPage({
    super.key,
    required this.ticketId,
    this.isAgentView = false,
  });

  final String ticketId;
  final bool isAgentView;

  @override
  State<SupportChatPage> createState() => _SupportChatPageState();
}

class _SupportChatPageState extends State<SupportChatPage> {
  final TextEditingController _messageCtrl = TextEditingController();
  final ScrollController _scrollCtrl = ScrollController();

  late final SupportTicketService _service;
  bool _sending = false;
  bool _busy = false;
  bool _loadingSavedReview = false;
  bool _submittingReview = false;
  bool _dismissingReview = false;
  bool _reviewDismissed = false;
  int? _savedStars;
  int _draftStars = 5;

  @override
  void initState() {
    super.initState();
    _service = SupportTicketService(Supabase.instance.client);
    _loadReviewState();
  }

  @override
  void dispose() {
    _messageCtrl.dispose();
    _scrollCtrl.dispose();
    super.dispose();
  }

  String _s(dynamic value) => value == null ? '' : value.toString().trim();

  int? _parseStars(dynamic value) {
    if (value == null) return null;
    if (value is num) {
      final n = value.toInt();
      return (n >= 1 && n <= 5) ? n : null;
    }
    final n = int.tryParse(_s(value));
    if (n == null || n < 1 || n > 5) return null;
    return n;
  }

  String _fmtDate(dynamic value) {
    final raw = _s(value);
    final dt = DateTime.tryParse(raw)?.toLocal();
    if (dt == null) return raw.isEmpty ? '-' : raw;
    final two = (int n) => n.toString().padLeft(2, '0');
    return '${two(dt.day)}/${two(dt.month)}/${dt.year} ${two(dt.hour)}:${two(dt.minute)}';
  }

  Color _statusColor(BuildContext context, String status) {
    final cs = Theme.of(context).colorScheme;
    switch (status.toLowerCase()) {
      case 'closed':
        return cs.error;
      case 'open':
      default:
        return Colors.green;
    }
  }

  Future<void> _loadReviewState() async {
    if (widget.isAgentView || _loadingSavedReview) return;
    setState(() => _loadingSavedReview = true);
    try {
      final stars = await _service.getTicketReview(widget.ticketId);
      final dismissed = await _service.isTicketReviewDismissed(widget.ticketId);
      if (!mounted) return;
      setState(() {
        _savedStars = stars;
        _reviewDismissed = dismissed && stars == null;
        if (stars != null) _draftStars = stars;
      });
    } catch (_) {
      // Keep UI smooth even if optional review storage is not ready yet.
    } finally {
      if (mounted) {
        setState(() => _loadingSavedReview = false);
      }
    }
  }

  Future<void> _send() async {
    if (_sending) return;
    final text = _messageCtrl.text.trim();
    if (text.isEmpty) return;

    setState(() => _sending = true);
    try {
      await _service.sendMessage(ticketId: widget.ticketId, message: text);
      _messageCtrl.clear();
      if (!mounted) return;
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (_scrollCtrl.hasClients) {
          _scrollCtrl.animateTo(
            _scrollCtrl.position.maxScrollExtent + 120,
            duration: const Duration(milliseconds: 250),
            curve: Curves.easeOut,
          );
        }
      });
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Send failed: $e'), backgroundColor: Colors.red),
      );
    } finally {
      if (mounted) setState(() => _sending = false);
    }
  }

  Future<void> _closeTicket() async {
    if (_busy) return;
    final isUserView = !widget.isAgentView;
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(isUserView ? 'Close case' : 'Close ticket'),
        content: Text(
          isUserView
              ? 'You sure want to close case?'
              : 'Close this support ticket? The user will be able to create a new ticket after this.',
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Cancel')),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: Text(isUserView ? 'Close case' : 'Close'),
          ),
        ],
      ),
    );
    if (ok != true) return;

    setState(() => _busy = true);
    try {
      await _service.closeTicket(widget.ticketId);
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(isUserView ? 'Case closed.' : 'Ticket closed.')),
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Close failed: $e'), backgroundColor: Colors.red),
      );
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _deleteTicket() async {
    if (_busy) return;
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Delete ticket'),
        content: const Text('Delete this support ticket and all chat messages permanently?'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Cancel')),
          FilledButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('Delete')),
        ],
      ),
    );
    if (ok != true) return;

    setState(() => _busy = true);
    try {
      await _service.deleteTicket(widget.ticketId);
      if (!mounted) return;
      Navigator.of(context).pop(true);
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Ticket deleted.')),
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Delete failed: $e'), backgroundColor: Colors.red),
      );
      setState(() => _busy = false);
    }
  }

  Future<void> _exportTicket() async {
    if (_busy) return;
    setState(() => _busy = true);
    try {
      final path = await _service.exportTicketChat(widget.ticketId);
      if (!mounted) return;
      await showDialog<void>(
        context: context,
        builder: (ctx) => AlertDialog(
          title: const Text('Chat exported'),
          content: SelectableText('Saved support chat file to:\n\n$path'),
          actions: [
            FilledButton(onPressed: () => Navigator.pop(ctx), child: const Text('OK')),
          ],
        ),
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Export failed: $e'), backgroundColor: Colors.red),
      );
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _submitReview() async {
    if (_submittingReview || _savedStars != null) return;

    setState(() => _submittingReview = true);
    try {
      await _service.submitTicketReview(ticketId: widget.ticketId, stars: _draftStars);
      if (!mounted) return;
      setState(() => _savedStars = _draftStars);
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Thanks for rating the staff.')),
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Review failed: $e'), backgroundColor: Colors.red),
      );
    } finally {
      if (mounted) setState(() => _submittingReview = false);
    }
  }


  Future<void> _dismissReviewPrompt() async {
    if (_dismissingReview || _savedStars != null) return;
    setState(() => _dismissingReview = true);
    try {
      await _service.dismissTicketReview(widget.ticketId);
    } catch (_) {
      // Keep dismiss action smooth even if storage fallback is unavailable.
    } finally {
      if (!mounted) return;
      setState(() {
        _reviewDismissed = true;
        _dismissingReview = false;
      });
    }
  }

  Widget _buildStarRow({
    required int stars,
    required bool readOnly,
    required ValueChanged<int>? onChanged,
  }) {
    return Wrap(
      spacing: 4,
      children: List.generate(5, (index) {
        final value = index + 1;
        final filled = value <= stars;
        return IconButton(
          onPressed: readOnly ? null : () => onChanged?.call(value),
          icon: Icon(
            filled ? Icons.star_rounded : Icons.star_border_rounded,
            color: Colors.amber.shade700,
            size: 30,
          ),
          tooltip: '$value star',
          visualDensity: VisualDensity.compact,
        );
      }),
    );
  }

  Widget _buildReviewCard({
    required Map<String, dynamic> ticket,
    required int? savedStars,
  }) {
    final assignedName = _s(ticket['assigned_admin_name']).isEmpty
        ? (_s(ticket['assigned_admin_role']).isEmpty ? 'Staff' : _s(ticket['assigned_admin_role']))
        : _s(ticket['assigned_admin_name']);

    return Container(
      width: double.infinity,
      margin: const EdgeInsets.fromLTRB(12, 0, 12, 12),
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: Colors.grey.shade300),
        color: Colors.white,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Expanded(
                child: Text(
                  'Staff review',
                  style: TextStyle(fontWeight: FontWeight.w900, fontSize: 15),
                ),
              ),
              if (savedStars == null)
                IconButton(
                  onPressed: _dismissingReview ? null : _dismissReviewPrompt,
                  tooltip: 'Close review',
                  visualDensity: VisualDensity.compact,
                  icon: _dismissingReview
                      ? const SizedBox(
                          height: 18,
                          width: 18,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        )
                      : const Icon(Icons.close_rounded),
                ),
            ],
          ),
          const SizedBox(height: 6),
          Text(
            savedStars == null
                ? 'How was $assignedName service? Give 1 to 5 star.'
                : 'You rated $assignedName service.',
            style: TextStyle(color: Colors.grey.shade700),
          ),
          const SizedBox(height: 8),
          _buildStarRow(
            stars: savedStars ?? _draftStars,
            readOnly: savedStars != null,
            onChanged: (value) => setState(() => _draftStars = value),
          ),
          if (savedStars == null) ...[
            const SizedBox(height: 8),
            Align(
              alignment: Alignment.centerRight,
              child: FilledButton(
                onPressed: _submittingReview ? null : _submitReview,
                child: _submittingReview
                    ? const SizedBox(
                        height: 18,
                        width: 18,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    : const Text('Submit review'),
              ),
            ),
          ] else
            Text(
              '$savedStars / 5 star',
              style: TextStyle(
                color: Colors.grey.shade700,
                fontWeight: FontWeight.w700,
              ),
            ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final currentAuthUid = Supabase.instance.client.auth.currentUser?.id ?? '';

    return Scaffold(
      appBar: AppBar(
        title: const Text('Support Chat'),
        actions: widget.isAgentView
            ? [
                PopupMenuButton<String>(
                  enabled: !_busy,
                  onSelected: (value) async {
                    if (value == 'close') await _closeTicket();
                    if (value == 'delete') await _deleteTicket();
                    if (value == 'export') await _exportTicket();
                  },
                  itemBuilder: (_) => const [
                    PopupMenuItem(value: 'export', child: Text('Export chat file')),
                    PopupMenuItem(value: 'close', child: Text('Close ticket')),
                    PopupMenuItem(value: 'delete', child: Text('Delete ticket')),
                  ],
                ),
              ]
            : [
                PopupMenuButton<String>(
                  enabled: !_busy,
                  onSelected: (value) async {
                    if (value == 'close') await _closeTicket();
                  },
                  itemBuilder: (_) => const [
                    PopupMenuItem(value: 'close', child: Text('Close case')),
                  ],
                ),
              ],
      ),
      body: StreamBuilder<Map<String, dynamic>?>(
        stream: _service.watchTicket(widget.ticketId),
        builder: (context, ticketSnap) {
          if (ticketSnap.connectionState != ConnectionState.active && !ticketSnap.hasData) {
            return const Center(child: CircularProgressIndicator());
          }

          final ticket = ticketSnap.data;
          if (ticket == null) {
            return const Center(child: Text('This support ticket no longer exists.'));
          }

          final status = _s(ticket['ticket_status']);
          final isClosed = status.toLowerCase() == SupportTicketService.statusClosed.toLowerCase();
          final storedRating = _savedStars ?? _parseStars(ticket['staff_rating']);

          return Column(
            children: [
              Container(
                width: double.infinity,
                margin: const EdgeInsets.fromLTRB(12, 12, 12, 0),
                padding: const EdgeInsets.all(14),
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(16),
                  border: Border.all(color: Colors.grey.shade300),
                  color: Colors.white,
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Expanded(
                          child: Text(
                            _s(ticket['title']).isEmpty ? 'Support Ticket' : _s(ticket['title']),
                            style: const TextStyle(fontWeight: FontWeight.w900, fontSize: 16),
                          ),
                        ),
                        Container(
                          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                          decoration: BoxDecoration(
                            color: _statusColor(context, status).withOpacity(0.12),
                            borderRadius: BorderRadius.circular(999),
                            border: Border.all(color: _statusColor(context, status).withOpacity(0.25)),
                          ),
                          child: Text(
                            status.isEmpty ? '-' : status,
                            style: TextStyle(
                              color: _statusColor(context, status),
                              fontWeight: FontWeight.w800,
                            ),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 8),
                    Text(
                      'Type: ${_s(ticket['ticket_type']).isEmpty ? '-' : _s(ticket['ticket_type'])}\n'
                      'Ticket ID: ${_s(ticket['ticket_id'])}\n'
                      'Created: ${_fmtDate(ticket['created_at'])}',
                      style: TextStyle(color: Colors.grey.shade700, fontSize: 12),
                    ),
                    const SizedBox(height: 8),
                    Text(
                      widget.isAgentView
                          ? 'User: ${_s(ticket['user_name']).isEmpty ? _s(ticket['user_id']) : _s(ticket['user_name'])} • ${_s(ticket['user_email']).isEmpty ? '-' : _s(ticket['user_email'])}'
                          : 'Assigned: ${_s(ticket['assigned_admin_name']).isEmpty ? 'Waiting for admin/staff' : _s(ticket['assigned_admin_name'])}',
                      style: TextStyle(color: Colors.grey.shade700, fontSize: 12),
                    ),
                    if (isClosed) ...[
                      const SizedBox(height: 8),
                      Text(
                        'This ticket is closed. Sending new messages is disabled.',
                        style: TextStyle(color: Colors.red.shade700, fontWeight: FontWeight.w700),
                      ),
                    ],
                  ],
                ),
              ),
              const SizedBox(height: 12),
              Expanded(
                child: StreamBuilder<List<Map<String, dynamic>>>(
                  stream: _service.watchMessages(widget.ticketId),
                  builder: (context, msgSnap) {
                    if (msgSnap.connectionState != ConnectionState.active && !msgSnap.hasData) {
                      return const Center(child: CircularProgressIndicator());
                    }
                    final messages = msgSnap.data ?? const <Map<String, dynamic>>[];
                    final hasStaffServed = _s(ticket['assigned_admin_uid']).isNotEmpty ||
                        _s(ticket['assigned_admin_name']).isNotEmpty ||
                        messages.any((m) => _s(m['sender_role']).toLowerCase() != 'user');

                    WidgetsBinding.instance.addPostFrameCallback((_) {
                      if (_scrollCtrl.hasClients) {
                        _scrollCtrl.jumpTo(_scrollCtrl.position.maxScrollExtent);
                      }
                    });

                    return Column(
                      children: [
                        Expanded(
                          child: messages.isEmpty
                              ? const Center(child: Text('No messages yet.'))
                              : ListView.builder(
                                  controller: _scrollCtrl,
                                  padding: const EdgeInsets.fromLTRB(12, 0, 12, 12),
                                  itemCount: messages.length,
                                  itemBuilder: (context, index) {
                                    final msg = messages[index];
                                    final isMine = _s(msg['sender_auth_uid']) == currentAuthUid;
                                    final bubbleColor = isMine
                                        ? Theme.of(context).colorScheme.primaryContainer
                                        : Colors.grey.shade200;
                                    final align = isMine ? CrossAxisAlignment.end : CrossAxisAlignment.start;
                                    final textAlign = isMine ? TextAlign.right : TextAlign.left;

                                    return Column(
                                      crossAxisAlignment: align,
                                      children: [
                                        Container(
                                          constraints: const BoxConstraints(maxWidth: 340),
                                          margin: const EdgeInsets.only(bottom: 10),
                                          padding: const EdgeInsets.all(12),
                                          decoration: BoxDecoration(
                                            color: bubbleColor,
                                            borderRadius: BorderRadius.circular(16),
                                          ),
                                          child: Column(
                                            crossAxisAlignment: align,
                                            children: [
                                              Text(
                                                '${_s(msg['sender_role'])} • ${_s(msg['sender_name'])}',
                                                textAlign: textAlign,
                                                style: TextStyle(
                                                  fontSize: 11,
                                                  color: Colors.grey.shade700,
                                                  fontWeight: FontWeight.w700,
                                                ),
                                              ),
                                              const SizedBox(height: 6),
                                              Text(
                                                _s(msg['message']),
                                                textAlign: textAlign,
                                              ),
                                              const SizedBox(height: 6),
                                              Text(
                                                _fmtDate(msg['created_at']),
                                                textAlign: textAlign,
                                                style: TextStyle(fontSize: 11, color: Colors.grey.shade700),
                                              ),
                                            ],
                                          ),
                                        ),
                                      ],
                                    );
                                  },
                                ),
                        ),
                        if (isClosed && !widget.isAgentView && hasStaffServed && !_reviewDismissed)
                          _buildReviewCard(ticket: ticket, savedStars: storedRating),
                      ],
                    );
                  },
                ),
              ),
              SafeArea(
                top: false,
                child: Container(
                  padding: const EdgeInsets.fromLTRB(12, 8, 12, 12),
                  decoration: BoxDecoration(
                    color: Colors.white,
                    border: Border(top: BorderSide(color: Colors.grey.shade300)),
                  ),
                  child: Row(
                    children: [
                      Expanded(
                        child: TextField(
                          controller: _messageCtrl,
                          enabled: !isClosed && !_sending,
                          minLines: 1,
                          maxLines: 4,
                          decoration: InputDecoration(
                            hintText: isClosed ? 'Ticket closed' : 'Type a message',
                            border: OutlineInputBorder(
                              borderRadius: BorderRadius.circular(14),
                            ),
                            isDense: true,
                          ),
                        ),
                      ),
                      const SizedBox(width: 8),
                      FilledButton(
                        onPressed: isClosed || _sending ? null : _send,
                        child: _sending
                            ? const SizedBox(
                                height: 18,
                                width: 18,
                                child: CircularProgressIndicator(strokeWidth: 2),
                              )
                            : const Text('Send'),
                      ),
                    ],
                  ),
                ),
              ),
            ],
          );
        },
      ),
    );
  }
}

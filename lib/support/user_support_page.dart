import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../services/support_ticket_service.dart';
import 'support_chat_page.dart';
import 'support_hidden_ticket_store.dart';

class UserSupportPage extends StatefulWidget {
  const UserSupportPage({super.key});

  @override
  State<UserSupportPage> createState() => _UserSupportPageState();
}

class _UserSupportPageState extends State<UserSupportPage> {
  late final SupportTicketService _service;
  late Future<_UserSupportData> _future;

  final _titleCtrl = TextEditingController();
  final _messageCtrl = TextEditingController();
  final _formKey = GlobalKey<FormState>();

  String _ticketType = SupportTicketService.ticketTypes.first;
  bool _submitting = false;

  @override
  void initState() {
    super.initState();
    _service = SupportTicketService(Supabase.instance.client);
    _future = _load();
  }

  @override
  void dispose() {
    _titleCtrl.dispose();
    _messageCtrl.dispose();
    super.dispose();
  }

  String _s(dynamic value) => value == null ? '' : value.toString().trim();

  String _fmtDate(dynamic value) {
    final raw = _s(value);
    final dt = DateTime.tryParse(raw)?.toLocal();
    if (dt == null) return raw.isEmpty ? '-' : raw;
    final two = (int n) => n.toString().padLeft(2, '0');
    return '${two(dt.day)}/${two(dt.month)}/${dt.year} ${two(dt.hour)}:${two(dt.minute)}';
  }

  String _ticketNumber(dynamic ticketId) {
    final id = _s(ticketId);
    final digits = id.replaceAll(RegExp(r'[^0-9]'), '');
    return digits.isEmpty ? id : digits;
  }

  Color _statusColor(String status) {
    switch (status.toLowerCase()) {
      case 'closed':
        return Colors.red;
      case 'open':
      default:
        return Colors.green;
    }
  }

  String _hiddenTicketUserKey() {
    return Supabase.instance.client.auth.currentUser?.id ?? 'guest';
  }

  Future<Set<String>> _readHiddenTicketIds() async {
    return readHiddenTicketIds(_hiddenTicketUserKey());
  }

  Future<void> _writeHiddenTicketIds(Set<String> ids) async {
    await writeHiddenTicketIds(_hiddenTicketUserKey(), ids);
  }

  Future<_UserSupportData> _load() async {
    final openTicket = await _service.getOpenTicketForCurrentUser();
    final tickets = await _service.getMyTickets();
    final hiddenTicketIds = await _readHiddenTicketIds();
    final visibleTickets = tickets
        .where((ticket) => !hiddenTicketIds.contains(_s(ticket['ticket_id'])))
        .toList();
    return _UserSupportData(openTicket: openTicket, tickets: visibleTickets);
  }

  Future<void> _refresh() async {
    setState(() {
      _future = _load();
    });
    await _future;
  }

  Future<void> _submit() async {
    if (_submitting) return;
    if (!_formKey.currentState!.validate()) return;

    setState(() => _submitting = true);
    try {
      final ticket = await _service.createTicket(
        title: _titleCtrl.text,
        ticketType: _ticketType,
        message: _messageCtrl.text,
      );
      _titleCtrl.clear();
      _messageCtrl.clear();
      if (!mounted) return;
      await Navigator.of(context).push(
        MaterialPageRoute(
          builder: (_) => SupportChatPage(ticketId: _s(ticket['ticket_id'])),
        ),
      );
      if (!mounted) return;
      await _refresh();
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Submit failed: $e'), backgroundColor: Colors.red),
      );
    } finally {
      if (mounted) {
        setState(() => _submitting = false);
      }
    }
  }

  Future<void> _openTicket(String ticketId) async {
    await Navigator.of(context).push(
      MaterialPageRoute(builder: (_) => SupportChatPage(ticketId: ticketId)),
    );
    if (!mounted) return;
    await _refresh();
  }

  Future<void> _deleteTicketLocally(Map<String, dynamic> ticket) async {
    final status = _s(ticket['ticket_status']).toLowerCase();
    if (status == 'open') {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Open ticket cannot be deleted locally. Please wait until admin/staff closes it.'),
        ),
      );
      return;
    }

    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Delete locally'),
        content: const Text(
          'Remove this ticket from your support inbox on this device only? It will still remain visible to admin/staff.',
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Cancel')),
          FilledButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('Delete')),
        ],
      ),
    );
    if (ok != true) return;

    try {
      final hiddenIds = await _readHiddenTicketIds();
      hiddenIds.add(_s(ticket['ticket_id']));
      await _writeHiddenTicketIds(hiddenIds);
      if (!mounted) return;
      await _refresh();
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Ticket removed from your inbox only.')),
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Local delete failed: $e'), backgroundColor: Colors.red),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Support'),
        actions: [
          IconButton(
            tooltip: 'Refresh',
            onPressed: _refresh,
            icon: const Icon(Icons.refresh_rounded),
          ),
        ],
      ),
      body: FutureBuilder<_UserSupportData>(
        future: _future,
        builder: (context, snap) {
          if (snap.connectionState != ConnectionState.done) {
            return const Center(child: CircularProgressIndicator());
          }
          if (snap.hasError) {
            return Center(
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: Text('Failed to load support: ${snap.error}'),
              ),
            );
          }

          final data = snap.data ?? const _UserSupportData();
          final openTicket = data.openTicket;
          final tickets = data.tickets;

          return RefreshIndicator(
            onRefresh: _refresh,
            child: ListView(
              padding: const EdgeInsets.fromLTRB(16, 12, 16, 24),
              children: [
                Container(
                  padding: const EdgeInsets.all(14),
                  decoration: BoxDecoration(
                    borderRadius: BorderRadius.circular(16),
                    border: Border.all(color: Colors.grey.shade300),
                    color: Colors.white,
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text(
                        'Open a support ticket',
                        style: TextStyle(fontWeight: FontWeight.w900, fontSize: 16),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        openTicket == null
                            ? 'Send one ticket to admin/staff. You can only keep 1 open ticket until it is solved.'
                            : 'You already have an open ticket. Please continue in the chatroom below until admin/staff closes it.',
                        style: TextStyle(color: Colors.grey.shade700),
                      ),
                      const SizedBox(height: 12),
                      if (openTicket == null)
                        Form(
                          key: _formKey,
                          child: Column(
                            children: [
                              TextFormField(
                                controller: _titleCtrl,
                                maxLength: 80,
                                decoration: const InputDecoration(
                                  labelText: 'Ticket title',
                                  hintText: 'Example: Payment deducted but booking failed',
                                  border: OutlineInputBorder(),
                                ),
                                validator: (value) {
                                  final v = (value ?? '').trim();
                                  if (v.isEmpty) return 'Please enter a title.';
                                  if (v.length < 4) return 'Title is too short.';
                                  return null;
                                },
                              ),
                              const SizedBox(height: 12),
                              DropdownButtonFormField<String>(
                                value: _ticketType,
                                items: SupportTicketService.ticketTypes
                                    .map((e) => DropdownMenuItem<String>(value: e, child: Text(e)))
                                    .toList(),
                                onChanged: (value) {
                                  if (value == null) return;
                                  setState(() => _ticketType = value);
                                },
                                decoration: const InputDecoration(
                                  labelText: 'Ticket type',
                                  border: OutlineInputBorder(),
                                ),
                              ),
                              const SizedBox(height: 12),
                              TextFormField(
                                controller: _messageCtrl,
                                minLines: 4,
                                maxLines: 6,
                                maxLength: 500,
                                decoration: const InputDecoration(
                                  labelText: 'Message',
                                  hintText: 'Tell admin/staff what happened and what help you need.',
                                  border: OutlineInputBorder(),
                                  alignLabelWithHint: true,
                                ),
                                validator: (value) {
                                  final v = (value ?? '').trim();
                                  if (v.isEmpty) return 'Please enter your message.';
                                  if (v.length < 8) return 'Message is too short.';
                                  return null;
                                },
                              ),
                              const SizedBox(height: 12),
                              SizedBox(
                                width: double.infinity,
                                child: FilledButton.icon(
                                  onPressed: _submitting ? null : _submit,
                                  icon: _submitting
                                      ? const SizedBox(
                                          height: 18,
                                          width: 18,
                                          child: CircularProgressIndicator(strokeWidth: 2),
                                        )
                                      : const Icon(Icons.support_agent_rounded),
                                  label: Text(_submitting ? 'Submitting...' : 'Submit to admin/staff'),
                                ),
                              ),
                            ],
                          ),
                        )
                      else
                        Container(
                          padding: const EdgeInsets.all(12),
                          decoration: BoxDecoration(
                            borderRadius: BorderRadius.circular(14),
                            color: Colors.green.withOpacity(0.08),
                            border: Border.all(color: Colors.green.withOpacity(0.20)),
                          ),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                _s(openTicket['title']).isEmpty ? 'Open ticket' : _s(openTicket['title']),
                                style: const TextStyle(fontWeight: FontWeight.w800),
                              ),
                              const SizedBox(height: 6),
                              Text(
                                'Type: ${_s(openTicket['ticket_type'])}\n'
                                'Ticket No: ${_ticketNumber(openTicket['ticket_id'])}\n'
                                'Ticket ID: ${_s(openTicket['ticket_id'])}',
                                style: TextStyle(color: Colors.grey.shade700, fontSize: 12),
                              ),
                              const SizedBox(height: 10),
                              FilledButton.tonalIcon(
                                onPressed: () => _openTicket(_s(openTicket['ticket_id'])),
                                icon: const Icon(Icons.chat_bubble_outline_rounded),
                                label: const Text('Open chatroom'),
                              ),
                            ],
                          ),
                        ),
                    ],
                  ),
                ),
                const SizedBox(height: 18),
                Row(
                  children: [
                    const Expanded(
                      child: Text(
                        'Inbox',
                        style: TextStyle(fontWeight: FontWeight.w900, fontSize: 16),
                      ),
                    ),
                    Text(
                      '${tickets.length} ticket(s)',
                      style: TextStyle(color: Colors.grey.shade700),
                    ),
                  ],
                ),
                const SizedBox(height: 10),
                if (tickets.isEmpty)
                  Container(
                    padding: const EdgeInsets.all(14),
                    decoration: BoxDecoration(
                      borderRadius: BorderRadius.circular(16),
                      border: Border.all(color: Colors.grey.shade300),
                      color: Colors.white,
                    ),
                    child: Text(
                      'No support tickets yet.',
                      style: TextStyle(color: Colors.grey.shade700),
                    ),
                  )
                else
                  ...tickets.map(
                    (ticket) => _UserTicketCard(
                      title: _s(ticket['title']).isEmpty ? _s(ticket['ticket_id']) : _s(ticket['title']),
                      ticketNumber: _ticketNumber(ticket['ticket_id']),
                      ticketId: _s(ticket['ticket_id']),
                      typeLine: _s(ticket['ticket_type']).isEmpty ? '-' : _s(ticket['ticket_type']),
                      previewLine: _s(ticket['last_message_preview']).isEmpty
                          ? 'No preview'
                          : _s(ticket['last_message_preview']),
                      timeLine: _fmtDate(ticket['last_message_at']),
                      status: _s(ticket['ticket_status']).isEmpty ? '-' : _s(ticket['ticket_status']),
                      statusColor: _statusColor(_s(ticket['ticket_status'])),
                      canDeleteLocally: _s(ticket['ticket_status']).toLowerCase() != 'open',
                      onTap: () => _openTicket(_s(ticket['ticket_id'])),
                      onDeleteLocally: () => _deleteTicketLocally(ticket),
                    ),
                  ),
              ],
            ),
          );
        },
      ),
    );
  }
}

class _UserSupportData {
  const _UserSupportData({
    this.openTicket,
    this.tickets = const <Map<String, dynamic>>[],
  });

  final Map<String, dynamic>? openTicket;
  final List<Map<String, dynamic>> tickets;
}

class _UserTicketCard extends StatelessWidget {
  const _UserTicketCard({
    required this.title,
    required this.ticketNumber,
    required this.ticketId,
    required this.typeLine,
    required this.previewLine,
    required this.timeLine,
    required this.status,
    required this.statusColor,
    required this.canDeleteLocally,
    required this.onTap,
    required this.onDeleteLocally,
  });

  final String title;
  final String ticketNumber;
  final String ticketId;
  final String typeLine;
  final String previewLine;
  final String timeLine;
  final String status;
  final Color statusColor;
  final bool canDeleteLocally;
  final VoidCallback onTap;
  final VoidCallback onDeleteLocally;

  @override
  Widget build(BuildContext context) {
    final captionStyle = TextStyle(color: Colors.grey.shade700, fontSize: 12);

    return Container(
      margin: const EdgeInsets.only(bottom: 10),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: Colors.grey.shade300),
        color: Colors.white,
      ),
      child: InkWell(
        borderRadius: BorderRadius.circular(16),
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(14, 14, 10, 12),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Padding(
                    padding: EdgeInsets.only(top: 2),
                    child: Icon(Icons.support_agent_outlined),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Text(
                      title,
                      style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 16),
                    ),
                  ),
                  const SizedBox(width: 8),
                  PopupMenuButton<String>(
                    tooltip: 'More',
                    onSelected: (value) {
                      if (value == 'delete_local') {
                        onDeleteLocally();
                      }
                    },
                    itemBuilder: (_) => [
                      PopupMenuItem<String>(
                        value: 'delete_local',
                        enabled: canDeleteLocally,
                        child: const Text('Delete locally'),
                      ),
                    ],
                  ),
                ],
              ),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(999),
                  color: statusColor.withOpacity(0.10),
                  border: Border.all(color: statusColor.withOpacity(0.24)),
                ),
                child: Text(
                  status,
                  style: TextStyle(
                    color: statusColor,
                    fontWeight: FontWeight.w800,
                    fontSize: 12,
                  ),
                ),
              ),
              const SizedBox(height: 8),
              Text('Ticket No: $ticketNumber', style: captionStyle.copyWith(fontWeight: FontWeight.w700)),
              const SizedBox(height: 2),
              Text('Ticket ID: $ticketId', style: captionStyle),
              const SizedBox(height: 2),
              Text('Type: $typeLine', style: captionStyle),
              const SizedBox(height: 8),
              Text(
                previewLine,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(fontSize: 15),
              ),
              const SizedBox(height: 8),
              Text(timeLine, style: captionStyle),
            ],
          ),
        ),
      ),
    );
  }
}

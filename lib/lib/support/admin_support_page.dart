import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../services/admin_access_service.dart';
import '../services/support_ticket_service.dart';
import 'support_chat_page.dart';

class AdminSupportPage extends StatefulWidget {
  const AdminSupportPage({super.key, this.embedded = false});

  final bool embedded;

  @override
  State<AdminSupportPage> createState() => _AdminSupportPageState();
}

class _AdminSupportPageState extends State<AdminSupportPage> {
  late final SupportTicketService _service;
  late Future<_AdminSupportData> _future;
  final TextEditingController _searchCtrl = TextEditingController();

  @override
  void initState() {
    super.initState();
    _service = SupportTicketService(Supabase.instance.client);
    _future = _load();
  }

  @override
  void dispose() {
    _searchCtrl.dispose();
    super.dispose();
  }

  Future<_AdminSupportData> _load() async {
    final ctx = await AdminAccessService(Supabase.instance.client).getAdminContext();
    final tickets = await _service.getInboxTickets();
    final openCount = tickets.where((e) => _s(e['ticket_status']).toLowerCase() == 'open').length;
    final solvedCount = tickets.where((e) => _s(e['ticket_status']).toLowerCase() == 'closed').length;
    return _AdminSupportData(
      ctx: ctx,
      tickets: tickets,
      openCount: openCount,
      solvedCount: solvedCount,
    );
  }

  Future<void> _refresh() async {
    setState(() {
      _future = _load();
    });
    await _future;
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

  bool _matchesSearch(Map<String, dynamic> ticket, String query) {
    final q = query.trim().toLowerCase();
    if (q.isEmpty) return true;

    final haystack = <String>[
      _s(ticket['ticket_id']),
      _ticketNumber(ticket['ticket_id']),
      _s(ticket['title']),
      _s(ticket['ticket_type']),
      _s(ticket['user_id']),
      _s(ticket['user_name']),
      _s(ticket['user_email']),
      _s(ticket['last_message_preview']),
      _s(ticket['assigned_admin_name']),
      _s(ticket['assigned_admin_role']),
    ].join(' ').toLowerCase();

    return haystack.contains(q);
  }

  Future<void> _openTicket(String ticketId) async {
    await Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => SupportChatPage(
          ticketId: ticketId,
          isAgentView: true,
        ),
      ),
    );
    await _refresh();
  }

  @override
  Widget build(BuildContext context) {
    final content = FutureBuilder<_AdminSupportData>(
      future: _future,
      builder: (context, snap) {
        if (snap.connectionState != ConnectionState.done) {
          return const Center(child: CircularProgressIndicator());
        }
        if (snap.hasError) {
          return Center(
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Text('Failed to load support inbox: ${snap.error}'),
            ),
          );
        }

        final data = snap.data;
        if (data == null || !data.ctx.isAdmin) {
          return const Center(child: Text('Access denied.'));
        }

        final roleText = data.ctx.isStaffAdmin ? 'Staff' : 'Admin';
        final query = _searchCtrl.text.trim();
        final filteredTickets = data.tickets.where((ticket) => _matchesSearch(ticket, query)).toList();

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
                    Text(
                      '$roleText Support Inbox',
                      style: const TextStyle(fontWeight: FontWeight.w900, fontSize: 16),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      'Receive user support requests, reply in the chatroom, close solved tickets, or delete them.',
                      style: TextStyle(color: Colors.grey.shade700),
                    ),
                    const SizedBox(height: 12),
                    Wrap(
                      spacing: 10,
                      runSpacing: 10,
                      children: [
                        _SummaryChip(
                          icon: Icons.support_agent_rounded,
                          label: 'Active Support',
                          value: data.openCount.toString(),
                        ),
                        _SummaryChip(
                          icon: Icons.check_circle_outline_rounded,
                          label: 'Solved Support',
                          value: data.solvedCount.toString(),
                        ),
                        _SummaryChip(
                          icon: Icons.inbox_outlined,
                          label: 'Total',
                          value: data.tickets.length.toString(),
                        ),
                      ],
                    ),
                    const SizedBox(height: 12),
                    TextField(
                      controller: _searchCtrl,
                      onChanged: (_) => setState(() {}),
                      decoration: InputDecoration(
                        hintText: 'Search by ticket number, title, user, email or type',
                        prefixIcon: const Icon(Icons.search_rounded),
                        suffixIcon: query.isEmpty
                            ? null
                            : IconButton(
                                tooltip: 'Clear',
                                onPressed: () {
                                  _searchCtrl.clear();
                                  setState(() {});
                                },
                                icon: const Icon(Icons.close_rounded),
                              ),
                        border: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(14),
                        ),
                        isDense: true,
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 18),
              if (data.tickets.isEmpty)
                _buildEmptyCard('No support tickets yet.')
              else if (filteredTickets.isEmpty)
                _buildEmptyCard('No support ticket matched your search.')
              else
                ...filteredTickets.map(
                  (ticket) => _AdminTicketCard(
                    title: _s(ticket['title']).isEmpty ? _s(ticket['ticket_id']) : _s(ticket['title']),
                    ticketNumber: _ticketNumber(ticket['ticket_id']),
                    ticketId: _s(ticket['ticket_id']),
                    userLine:
                        'User: ${_s(ticket['user_name']).isEmpty ? _s(ticket['user_id']) : _s(ticket['user_name'])}',
                    typeLine: 'Type: ${_s(ticket['ticket_type']).isEmpty ? '-' : _s(ticket['ticket_type'])}',
                    previewLine: _s(ticket['last_message_preview']).isEmpty
                        ? 'No preview'
                        : _s(ticket['last_message_preview']),
                    timeLine: _fmtDate(ticket['last_message_at']),
                    status: _s(ticket['ticket_status']).isEmpty ? '-' : _s(ticket['ticket_status']),
                    statusColor: _statusColor(_s(ticket['ticket_status'])),
                    assignee: _s(ticket['assigned_admin_name']).isEmpty
                        ? 'Unassigned'
                        : _s(ticket['assigned_admin_name']),
                    onTap: () => _openTicket(_s(ticket['ticket_id'])),
                  ),
                ),
            ],
          ),
        );
      },
    );

    if (widget.embedded) return content;

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
      body: content,
    );
  }

  Widget _buildEmptyCard(String text) {
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: Colors.grey.shade300),
        color: Colors.white,
      ),
      child: Text(
        text,
        style: TextStyle(color: Colors.grey.shade700),
      ),
    );
  }
}

class _AdminSupportData {
  const _AdminSupportData({
    required this.ctx,
    this.tickets = const <Map<String, dynamic>>[],
    this.openCount = 0,
    this.solvedCount = 0,
  });

  final AdminContext ctx;
  final List<Map<String, dynamic>> tickets;
  final int openCount;
  final int solvedCount;
}

class _SummaryChip extends StatelessWidget {
  const _SummaryChip({
    required this.icon,
    required this.label,
    required this.value,
  });

  final IconData icon;
  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(999),
        color: Theme.of(context).colorScheme.primary.withOpacity(0.08),
        border: Border.all(color: Theme.of(context).colorScheme.primary.withOpacity(0.20)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 18),
          const SizedBox(width: 8),
          Text('$label: $value', style: const TextStyle(fontWeight: FontWeight.w800)),
        ],
      ),
    );
  }
}

class _AdminTicketCard extends StatelessWidget {
  const _AdminTicketCard({
    required this.title,
    required this.ticketNumber,
    required this.ticketId,
    required this.userLine,
    required this.typeLine,
    required this.previewLine,
    required this.timeLine,
    required this.status,
    required this.statusColor,
    required this.assignee,
    required this.onTap,
  });

  final String title;
  final String ticketNumber;
  final String ticketId;
  final String userLine;
  final String typeLine;
  final String previewLine;
  final String timeLine;
  final String status;
  final Color statusColor;
  final String assignee;
  final VoidCallback onTap;

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
          padding: const EdgeInsets.fromLTRB(14, 14, 14, 12),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Padding(
                    padding: EdgeInsets.only(top: 2),
                    child: Icon(Icons.support_agent_rounded),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Text(
                      title,
                      style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 16),
                    ),
                  ),
                  const SizedBox(width: 10),
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
                ],
              ),
              const SizedBox(height: 8),
              Text('Ticket No: $ticketNumber', style: captionStyle.copyWith(fontWeight: FontWeight.w700)),
              const SizedBox(height: 2),
              Text('Ticket ID: $ticketId', style: captionStyle),
              const SizedBox(height: 2),
              Text(userLine, style: captionStyle),
              const SizedBox(height: 2),
              Text(typeLine, style: captionStyle),
              const SizedBox(height: 8),
              Text(
                previewLine,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(fontSize: 15),
              ),
              const SizedBox(height: 8),
              Row(
                children: [
                  Expanded(child: Text(timeLine, style: captionStyle)),
                  const SizedBox(width: 8),
                  Flexible(
                    child: Text(
                      assignee,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      textAlign: TextAlign.right,
                      style: captionStyle,
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}

import 'package:flutter/material.dart';
import 'package:android_sms_reader/android_sms_reader.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:flutter_contacts/flutter_contacts.dart';
import 'show_sms.dart';
import 'compose_sms.dart';
import 'spam_page.dart';
import 'services/spam_detection_service.dart';

class LandingPage extends StatefulWidget {
  const LandingPage({super.key});

  @override
  State<LandingPage> createState() => _LandingPageState();
}

class _LandingPageState extends State<LandingPage> {
  final TextEditingController _searchCtrl = TextEditingController();
  final FocusNode _searchFocus = FocusNode();

  List<AndroidSMSMessage> allMessages = [];
  Map<String, List<AndroidSMSMessage>> groupedMessages = {};
  Map<String, String> contactNames = {}; // Cache contact names
  Set<String> spamNumbers = {}; // Track spam phone numbers

  bool isLoading = true;
  bool hasPermission = false;
  bool showOnlyInbox = false; // quick filter toggle
  String errorText = '';

  @override
  void initState() {
    super.initState();
    _requestPermissionAndLoadSMS();
    _searchCtrl.addListener(() => setState(() {}));
  }

  @override
  void dispose() {
    _searchCtrl.dispose();
    _searchFocus.dispose();
    super.dispose();
  }

  Future<void> _requestPermissionAndLoadSMS() async {
    setState(() {
      errorText = '';
    });

    var status = await Permission.sms.status;
    if (!status.isGranted) {
      status = await Permission.sms.request();
    }

    if (status.isGranted) {
      setState(() => hasPermission = true);
      await _loadSMS();
    } else {
      setState(() {
        hasPermission = false;
        isLoading = false;
      });
    }
  }

  Future<void> _loadSMS() async {
    setState(() {
      isLoading = true;
      errorText = '';
    });

    try {
      final inboxMessages = await AndroidSMSReader.fetchMessages(
        type: AndroidSMSType.inbox,
        start: 0,
        count: 5000,
      );

      final sentMessages = await AndroidSMSReader.fetchMessages(
        type: AndroidSMSType.sent,
        start: 0,
        count: 5000,
      );

      final messages = [...inboxMessages, ...sentMessages];

      // Group by peer address (phone number)
      final Map<String, List<AndroidSMSMessage>> grouped = {};
      for (final m in messages) {
        final sender = m.address;
        if (sender.isEmpty) continue;
        (grouped[sender] ??= []).add(m);
      }

      // Sort each conversation by date desc
      grouped.forEach(
        (_, list) => list.sort((a, b) => b.date.compareTo(a.date)),
      );

      setState(() {
        allMessages = messages;
        groupedMessages = grouped;
        isLoading = false;
      });

      // Load contact names in the background
      _loadContactNames();
      
      // Check inbox messages for spam
      _checkMessagesForSpam(inboxMessages);
    } catch (e) {
      setState(() {
        errorText = 'Failed to load messages';
        isLoading = false;
      });
    }
  }

  Future<void> _checkMessagesForSpam(List<AndroidSMSMessage> inboxMessages) async {
    print('Starting spam check for ${inboxMessages.length} messages');
    
    // Only check recent messages (last 10) to avoid overwhelming the API
    final recentMessages = inboxMessages.take(10).toList();
    print('Checking ${recentMessages.length} recent messages for spam');
    
    // Check each inbox message for spam
    for (final message in recentMessages) {
      final phoneNumber = message.address;
      final messageText = message.body;
      
      print('Checking message from: $phoneNumber');
      
      // Skip if already marked as spam
      if (spamNumbers.contains(phoneNumber)) {
        print('Skipping $phoneNumber - already marked as spam');
        continue;
      }
      
      // Check for spam
      final isSpam = await SpamDetectionService.checkAndSaveIfSpam(
        messageText: messageText,
        phoneNumber: phoneNumber,
        contactName: contactNames[phoneNumber],
      );
      
      print('Result for $phoneNumber: ${isSpam ? "SPAM" : "HAM"}');
      
      if (isSpam && mounted) {
        setState(() {
          spamNumbers.add(phoneNumber);
        });
      }
    }
    
    print('Spam check completed');
  }

  Future<void> _loadContactNames() async {
    try {
      if (await FlutterContacts.requestPermission(readonly: true)) {
        final contacts = await FlutterContacts.getContacts(
          withProperties: true,
        );
        final Map<String, String> names = {};

        for (final phoneNumber in groupedMessages.keys) {
          final name = await _findContactName(phoneNumber, contacts);
          if (name != null) names[phoneNumber] = name;
        }
        if (mounted) {
          setState(() => contactNames = names);
        }
      }
    } catch (_) {
      // Silent fail; keep numbers if contacts can't load.
    }
  }

  Future<String?> _findContactName(
    String phoneNumber,
    List<Contact> contacts,
  ) async {
    final cleanPhone = phoneNumber.replaceAll(RegExp(r'[\s\-\(\)]'), '');
    for (final c in contacts) {
      for (final p in c.phones) {
        final clean = p.number.replaceAll(RegExp(r'[\s\-\(\)]'), '');
        if (clean.contains(cleanPhone) || cleanPhone.contains(clean)) {
          return c.displayName;
        }
      }
    }
    return null;
  }

  String _truncate(String text, int max) =>
      text.length <= max ? text : '${text.substring(0, max)}…';

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: () {
        // Unfocus search box when user taps elsewhere
        FocusScope.of(context).unfocus();
      },
      child: Scaffold(
        extendBody: true,
        appBar: AppBar(
          scrolledUnderElevation: 1,
          titleSpacing: 0,
          title: _SearchBar(
            controller: _searchCtrl,
            focusNode: _searchFocus,
            hint: 'Search name, number or text…',
            onClear: () => _searchCtrl.clear(),
          ),
          backgroundColor: const Color.fromARGB(255, 215, 215, 215), // Teal 700
          foregroundColor: const Color.fromARGB(255, 0, 0, 0),
          actions: [
            IconButton(
              tooltip: 'Refresh',
              onPressed: _loadSMS,
              icon: const Icon(Icons.refresh),
            ),
            PopupMenuButton<String>(
              tooltip: 'More',
              onSelected: (v) {
                if (v == 'toggle_inbox')
                  setState(() => showOnlyInbox = !showOnlyInbox);
                  else if (v == 'spam') {
                    Navigator.push(
                      context,
                      MaterialPageRoute(builder: (context) => const SpamPage()),
                    );
                  }
              },
              itemBuilder: (context) => [
              CheckedPopupMenuItem(
                value: 'toggle_inbox',
                checked: showOnlyInbox,
                child: const Text('Show only Inbox'),
              ),
                const PopupMenuItem(
                  value: 'spam',
                  child: Text('Spam'),
                ),
            ],
          ),
        ],
      ),
      body: SafeArea(
        child: AnimatedSwitcher(
          duration: const Duration(milliseconds: 250),
          child: _buildBody(context),
        ),
      ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () {
          Navigator.push(
            context,
            MaterialPageRoute(builder: (context) => const ComposeSmsPage()),
          );
        },
        icon: const Icon(Icons.edit),
        label: const Text('New message'),
      ),
      ),
    );
  }

  Widget _buildBody(BuildContext context) {
    if (!hasPermission)
      return _PermissionGate(onRequest: _requestPermissionAndLoadSMS);

    if (isLoading) {
      return const Center(child: _Loader());
    }

    if (errorText.isNotEmpty) {
      return _ErrorState(message: errorText, onRetry: _loadSMS);
    }

    if (groupedMessages.isEmpty) {
      return const _EmptyState(
        icon: Icons.sms_outlined,
        title: 'No messages yet',
        subtitle: 'Your SMS threads will appear here.',
      );
    }

    // Prepare conversation list
    final List<String> keys = groupedMessages.keys.toList();

    // Filter to inbox only if toggled
    if (showOnlyInbox) {
      keys.retainWhere(
        (k) =>
            groupedMessages[k]!.any((m) => m.type == 'inbox' || m.type == '1'),
      );
    }

    // Sort conversations by latest date desc
    keys.sort((a, b) {
      final da = groupedMessages[a]!.first.date;
      final db = groupedMessages[b]!.first.date;
      return db.compareTo(da);
    });

    // Apply search filter
    final q = _searchCtrl.text.trim().toLowerCase();
    if (q.isNotEmpty) {
      keys.retainWhere((k) {
        final name = (contactNames[k] ?? k).toLowerCase();
        final latest = groupedMessages[k]!.first.body.toLowerCase();
        return name.contains(q) ||
            k.toLowerCase().contains(q) ||
            latest.contains(q);
      });
    }

    if (keys.isEmpty) {
      return const _EmptyState(
        icon: Icons.search_off,
        title: 'No results',
        subtitle: 'Try a different name, number, or keyword.',
      );
    }

    return RefreshIndicator(
      onRefresh: _loadSMS,
      child: ListView.separated(
        padding: const EdgeInsets.fromLTRB(12, 8, 12, 100),
        itemCount: keys.length,
        separatorBuilder: (_, __) => const SizedBox(height: 8),
        itemBuilder: (context, i) {
          final id = keys[i];
          final messages = groupedMessages[id]!;
          final latest = messages.first;
          final isSent = latest.type == 'sent' || latest.type == '2';
          final displayName = contactNames[id] ?? id;

          return _ConversationTile(
            name: displayName,
            address: id,
            preview: isSent
                ? 'You: ${_truncate(latest.body, 60)}'
                : _truncate(latest.body, 64),
            isSent: isSent,
            count: messages.length,
            time: _formatDate(latest.date),
            colorSeed: id,
            onTap: () {
              Navigator.push(
                context,
                MaterialPageRoute(
                  builder: (_) => ShowSmsPage(sender: id, messages: messages),
                ),
              );
            },
          );
        },
      ),
    );
  }

  String _formatDate(int timestamp) {
    final date = DateTime.fromMillisecondsSinceEpoch(timestamp);
    final now = DateTime.now();
    final isToday =
        date.year == now.year && date.month == now.month && date.day == now.day;
    if (isToday) {
      final h = date.hour.toString().padLeft(2, '0');
      final m = date.minute.toString().padLeft(2, '0');
      return '$h:$m';
    }
    final dd = date.day.toString().padLeft(2, '0');
    final mm = date.month.toString().padLeft(2, '0');
    final yy = date.year.toString();
    return '$dd/$mm/$yy';
  }
}

// ——————————————————————————————————————————————————————————
// UI pieces
// ——————————————————————————————————————————————————————————

class _SearchBar extends StatelessWidget {
  const _SearchBar({
    required this.controller,
    required this.focusNode,
    required this.hint,
    required this.onClear,
  });

  final TextEditingController controller;
  final FocusNode focusNode;
  final String hint;
  final VoidCallback onClear;

  @override
  Widget build(BuildContext context) {
    final color = Theme.of(context).colorScheme;
    return Padding(
      padding: const EdgeInsets.only(right: 8),
      child: Container(
        margin: const EdgeInsets.symmetric(vertical: 8, horizontal: 12),
        decoration: BoxDecoration(
          color: color.surfaceContainerHigh,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: color.outlineVariant),
        ),
        child: Row(
          children: [
            const SizedBox(width: 12),
            const Icon(Icons.search),
            const SizedBox(width: 8),
            Expanded(
              child: TextField(
                controller: controller,
                focusNode: focusNode,
                decoration: InputDecoration(
                  hintText: hint,
                  border: InputBorder.none,
                ),
                textInputAction: TextInputAction.search,
              ),
            ),
            if (controller.text.isNotEmpty)
              IconButton(
                onPressed: onClear,
                icon: const Icon(Icons.close_rounded),
                tooltip: 'Clear',
              ),
          ],
        ),
      ),
    );
  }
}

class _Loader extends StatelessWidget {
  const _Loader();
  @override
  Widget build(BuildContext context) {
    return const SizedBox(
      height: 56,
      width: 56,
      child: CircularProgressIndicator(strokeWidth: 3),
    );
  }
}

class _PermissionGate extends StatelessWidget {
  const _PermissionGate({required this.onRequest});
  final VoidCallback onRequest;

  @override
  Widget build(BuildContext context) {
    final color = Theme.of(context).colorScheme;
    return Center(
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 24),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(Icons.sms_failed_outlined, size: 72, color: color.outline),
            const SizedBox(height: 16),
            const Text(
              'SMS Permission required',
              style: TextStyle(fontSize: 20, fontWeight: FontWeight.w700),
            ),
            const SizedBox(height: 8),
            Text(
              'Grant access to read your inbox and show conversations.',
              textAlign: TextAlign.center,
              style: TextStyle(color: color.onSurfaceVariant),
            ),
            const SizedBox(height: 16),
            FilledButton.icon(
              onPressed: onRequest,
              icon: const Icon(Icons.lock_open_rounded),
              label: const Text('Grant permission'),
            ),
          ],
        ),
      ),
    );
  }
}

class _EmptyState extends StatelessWidget {
  const _EmptyState({
    required this.icon,
    required this.title,
    required this.subtitle,
  });
  final IconData icon;
  final String title;
  final String subtitle;

  @override
  Widget build(BuildContext context) {
    final color = Theme.of(context).colorScheme;
    return Center(
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 24),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(icon, size: 72, color: color.outline),
            const SizedBox(height: 12),
            Text(
              title,
              style: const TextStyle(fontSize: 20, fontWeight: FontWeight.w700),
            ),
            const SizedBox(height: 6),
            Text(
              subtitle,
              textAlign: TextAlign.center,
              style: TextStyle(color: color.onSurfaceVariant),
            ),
          ],
        ),
      ),
    );
  }
}

class _ErrorState extends StatelessWidget {
  const _ErrorState({required this.message, required this.onRetry});
  final String message;
  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) {
    final color = Theme.of(context).colorScheme;
    return Center(
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 24),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(Icons.error_outline, size: 72, color: color.error),
            const SizedBox(height: 12),
            const Text(
              'Something went wrong',
              style: TextStyle(fontSize: 20, fontWeight: FontWeight.w700),
            ),
            const SizedBox(height: 6),
            Text(
              message,
              textAlign: TextAlign.center,
              style: TextStyle(color: color.onSurfaceVariant),
            ),
            const SizedBox(height: 16),
            OutlinedButton.icon(
              onPressed: onRetry,
              icon: const Icon(Icons.refresh),
              label: const Text('Try again'),
            ),
          ],
        ),
      ),
    );
  }
}

class _ConversationTile extends StatelessWidget {
  const _ConversationTile({
    required this.name,
    required this.address,
    required this.preview,
    required this.isSent,
    required this.count,
    required this.time,
    required this.colorSeed,
    required this.onTap,
  });

  final String name;
  final String address;
  final String preview;
  final bool isSent;
  final int count;
  final String time;
  final String colorSeed;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final color = Theme.of(context).colorScheme;
    final initials = _initialsOf(name);
    final bg = _colorFromSeed(colorSeed, color);

    return InkWell(
      borderRadius: BorderRadius.circular(20),
      onTap: onTap,
      child: Ink(
        decoration: BoxDecoration(
          color: color.surfaceContainerHigh,
          borderRadius: BorderRadius.circular(20),
          border: Border.all(color: color.outlineVariant),
        ),
        child: Padding(
          padding: const EdgeInsets.all(12),
          child: Row(
            children: [
              Container(
                width: 48,
                height: 48,
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    colors: [bg.withOpacity(.9), bg.withOpacity(.6)],
                    begin: Alignment.topLeft,
                    end: Alignment.bottomRight,
                  ),
                  borderRadius: BorderRadius.circular(16),
                ),
                alignment: Alignment.center,
                child: Text(
                  initials,
                  style: TextStyle(
                    fontWeight: FontWeight.w800,
                    color: color.onPrimary,
                    fontSize: 16,
                  ),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Expanded(
                          child: Text(
                            name,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(
                              fontSize: 16,
                              fontWeight: FontWeight.w700,
                            ),
                          ),
                        ),
                        const SizedBox(width: 8),
                        Text(
                          time,
                          style: TextStyle(
                            color: color.onSurfaceVariant,
                            fontSize: 12,
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 6),
                    Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        if (isSent)
                          Padding(
                            padding: const EdgeInsets.only(top: 2, right: 4),
                            child: Icon(
                              Icons.done_all,
                              size: 16,
                              color: color.primary,
                            ),
                          ),
                        Expanded(
                          child: Text(
                            preview,
                            maxLines: 2,
                            overflow: TextOverflow.ellipsis,
                            style: TextStyle(color: color.onSurfaceVariant),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 8),
                    Row(
                      children: [
                        _Chip(text: '$count message${count > 1 ? 's' : ''}'),
                        const Spacer(),
                        const Icon(Icons.chevron_right, size: 20),
                      ],
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  String _initialsOf(String value) {
    final trimmed = value.trim();
    if (trimmed.isEmpty) return '??';
    
    final parts = trimmed.split(RegExp(r'\s+'));
    
    // If multiple words, take first letter of first two words
    if (parts.length >= 2) {
      final first = parts[0].isNotEmpty ? parts[0][0].toUpperCase() : '';
      final second = parts[1].isNotEmpty ? parts[1][0].toUpperCase() : '';
      return first + second;
    }
    
    // If single word, take first two characters
    if (trimmed.length >= 2) {
      return trimmed.substring(0, 2).toUpperCase();
    }
    
    // If only one character, duplicate it
    return trimmed[0].toUpperCase() * 2;
  }

  Color _colorFromSeed(String seed, ColorScheme scheme) {
    final hash = seed.codeUnits.fold<int>(
      0,
      (p, e) => (p * 31 + e) & 0xFFFFFFFF,
    );
    final hue = (hash % 360).toDouble();
    return HSLColor.fromAHSL(
      1,
      hue,
      0.55,
      scheme.brightness == Brightness.dark ? 0.45 : 0.60,
    ).toColor();
  }
}

class _Chip extends StatelessWidget {
  const _Chip({required this.text});
  final String text;

  @override
  Widget build(BuildContext context) {
    final color = Theme.of(context).colorScheme;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: BoxDecoration(
        color: color.secondaryContainer,
        borderRadius: BorderRadius.circular(20),
      ),
      child: Text(
        text,
        style: TextStyle(
          color: color.onSecondaryContainer,
          fontSize: 12,
          fontWeight: FontWeight.w600,
        ),
      ),
    );
  }
}

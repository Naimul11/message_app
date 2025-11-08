import 'package:flutter/material.dart';
import 'package:android_sms_reader/android_sms_reader.dart';
import 'package:permission_handler/permission_handler.dart';
import 'show_sms.dart';
import 'compose_sms.dart';

class LandingPage extends StatefulWidget {
  const LandingPage({super.key});

  @override
  State<LandingPage> createState() => _LandingPageState();
}

class _LandingPageState extends State<LandingPage> {
  List<AndroidSMSMessage> allMessages = [];
  Map<String, List<AndroidSMSMessage>> groupedMessages = {};
  bool isLoading = true;
  bool hasPermission = false;

  @override
  void initState() {
    super.initState();
    _requestPermissionAndLoadSMS();
  }

  Future<void> _requestPermissionAndLoadSMS() async {
    // Request SMS permission
    var status = await Permission.sms.status;
    
    if (!status.isGranted) {
      status = await Permission.sms.request();
    }
    
    if (status.isGranted) {
      setState(() {
        hasPermission = true;
      });
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
    });

    try {
      // Read all SMS messages from inbox - fetch up to 5000 messages
      List<AndroidSMSMessage> messages = await AndroidSMSReader.fetchMessages(
        type: AndroidSMSType.inbox,
        start: 0,
        count: 5000,
      );
      
      // Group messages by sender (address)
      Map<String, List<AndroidSMSMessage>> grouped = {};
      for (var message in messages) {
        String sender = message.address;
        if (!grouped.containsKey(sender)) {
          grouped[sender] = [];
        }
        grouped[sender]!.add(message);
      }

      setState(() {
        allMessages = messages;
        groupedMessages = grouped;
        isLoading = false;
      });
    } catch (e) {
      print('Error reading SMS: $e');
      setState(() {
        isLoading = false;
      });
    }
  }

  String _truncateMessage(String message, int maxLength) {
    if (message.length <= maxLength) return message;
    return '${message.substring(0, maxLength)}...';
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Messages'),
        backgroundColor: Theme.of(context).colorScheme.inversePrimary,
        actions: [
          IconButton(
            icon: const Icon(Icons.refresh),
            onPressed: _loadSMS,
          ),
        ],
      ),
      body: _buildBody(),
      floatingActionButton: FloatingActionButton(
        onPressed: () {
          Navigator.push(
            context,
            MaterialPageRoute(
              builder: (context) => const ComposeSmsPage(),
            ),
          );
        },
        child: const Icon(Icons.add),
        tooltip: 'New Message',
      ),
    );
  }

  Widget _buildBody() {
    if (!hasPermission) {
      return Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            const Icon(Icons.sms_failed, size: 64, color: Colors.grey),
            const SizedBox(height: 16),
            const Text(
              'SMS Permission Required',
              style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 8),
            const Text('Please grant SMS permission to view messages'),
            const SizedBox(height: 16),
            ElevatedButton(
              onPressed: _requestPermissionAndLoadSMS,
              child: const Text('Grant Permission'),
            ),
          ],
        ),
      );
    }

    if (isLoading) {
      return const Center(
        child: CircularProgressIndicator(),
      );
    }

    if (groupedMessages.isEmpty) {
      return const Center(
        child: Text('No SMS messages found'),
      );
    }

    // Get unique senders (headers)
    List<String> senders = groupedMessages.keys.toList();

    return ListView.builder(
      padding: const EdgeInsets.all(8),
      itemCount: senders.length,
      itemBuilder: (context, index) {
        String sender = senders[index];
        List<AndroidSMSMessage> messages = groupedMessages[sender]!;
        
        // Get the latest message for preview
        AndroidSMSMessage latestMessage = messages.first;
        
        return Card(
          elevation: 2,
          margin: const EdgeInsets.symmetric(vertical: 4, horizontal: 8),
          child: ListTile(
            contentPadding: const EdgeInsets.all(12),
            leading: CircleAvatar(
              backgroundColor: Theme.of(context).colorScheme.primaryContainer,
              child: Text(
                sender.isNotEmpty ? sender[0].toUpperCase() : '?',
                style: TextStyle(
                  color: Theme.of(context).colorScheme.onPrimaryContainer,
                  fontWeight: FontWeight.bold,
                ),
              ),
            ),
            title: Text(
              sender,
              style: const TextStyle(
                fontWeight: FontWeight.bold,
                fontSize: 16,
              ),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
            subtitle: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const SizedBox(height: 4),
                Text(
                  _truncateMessage(latestMessage.body, 60),
                  style: TextStyle(
                    color: Colors.grey[700],
                    fontSize: 14,
                  ),
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                ),
                const SizedBox(height: 4),
                Text(
                  '${messages.length} message${messages.length > 1 ? 's' : ''}',
                  style: TextStyle(
                    color: Colors.grey[500],
                    fontSize: 12,
                  ),
                ),
              ],
            ),
            trailing: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
                Text(
                  _formatDate(latestMessage.date),
                  style: TextStyle(
                    color: Colors.grey[600],
                    fontSize: 12,
                  ),
                ),
                const SizedBox(height: 4),
                Icon(
                  Icons.chevron_right,
                  color: Colors.grey[400],
                ),
              ],
            ),
            onTap: () {
              // Navigate to conversation detail page
              Navigator.push(
                context,
                MaterialPageRoute(
                  builder: (context) => ShowSmsPage(
                    sender: sender,
                    messages: messages,
                  ),
                ),
              );
            },
          ),
        );
      },
    );
  }

  String _formatDate(int timestamp) {
    DateTime date = DateTime.fromMillisecondsSinceEpoch(timestamp);
    DateTime now = DateTime.now();
    
    if (date.year == now.year && date.month == now.month && date.day == now.day) {
      return '${date.hour.toString().padLeft(2, '0')}:${date.minute.toString().padLeft(2, '0')}';
    } else {
      return '${date.day}/${date.month}/${date.year}';
    }
  }
}

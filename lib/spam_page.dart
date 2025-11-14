import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';

class SpamPage extends StatelessWidget {
  const SpamPage({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Spam Messages'),
        backgroundColor: Colors.red[700],
        foregroundColor: Colors.white,
      ),
      body: StreamBuilder<QuerySnapshot>(
        stream: FirebaseFirestore.instance
            .collection('spam')
            .orderBy('timestamp', descending: true)
            .snapshots(),
        builder: (context, snapshot) {
          if (snapshot.hasError) {
            return Center(
              child: Text('Error: ${snapshot.error}'),
            );
          }

          if (snapshot.connectionState == ConnectionState.waiting) {
            return const Center(
              child: CircularProgressIndicator(),
            );
          }

          final spamDocs = snapshot.data?.docs ?? [];

          if (spamDocs.isEmpty) {
            return const Center(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Icon(
                    Icons.check_circle_outline,
                    size: 64,
                    color: Colors.green,
                  ),
                  SizedBox(height: 16),
                  Text(
                    'No spam detected',
                    style: TextStyle(fontSize: 18, fontWeight: FontWeight.w500),
                  ),
                ],
              ),
            );
          }

          return ListView.builder(
            itemCount: spamDocs.length,
            itemBuilder: (context, index) {
              final doc = spamDocs[index];
              final data = doc.data() as Map<String, dynamic>;
              final phoneNumber = data['phoneNumber'] ?? 'Unknown';
              final contactName = data['contactName'] ?? 'Unknown';
              final messageText = data['messageText'] ?? '';
              final detectedAt = data['detectedAt'] ?? '';

              return Card(
                margin: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                child: ListTile(
                  leading: CircleAvatar(
                    backgroundColor: Colors.red[700],
                    child: const Icon(Icons.warning, color: Colors.white),
                  ),
                  title: Text(
                    contactName != 'Unknown' ? contactName : phoneNumber,
                    style: const TextStyle(fontWeight: FontWeight.bold),
                  ),
                  subtitle: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      if (contactName != 'Unknown')
                        Text(phoneNumber, style: const TextStyle(fontSize: 12)),
                      const SizedBox(height: 4),
                      Text(
                        messageText.length > 100
                            ? '${messageText.substring(0, 100)}...'
                            : messageText,
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                      ),
                      const SizedBox(height: 4),
                      Text(
                        'Detected: ${_formatDate(detectedAt)}',
                        style: TextStyle(
                          fontSize: 11,
                          color: Colors.grey[600],
                        ),
                      ),
                    ],
                  ),
                  trailing: IconButton(
                    icon: const Icon(Icons.delete, color: Colors.red),
                    onPressed: () => _deleteSpamEntry(context, doc.id),
                  ),
                ),
              );
            },
          );
        },
      ),
    );
  }

  String _formatDate(String dateString) {
    try {
      final date = DateTime.parse(dateString);
      final now = DateTime.now();
      final diff = now.difference(date);

      if (diff.inDays == 0) {
        return 'Today ${date.hour}:${date.minute.toString().padLeft(2, '0')}';
      } else if (diff.inDays == 1) {
        return 'Yesterday';
      } else if (diff.inDays < 7) {
        return '${diff.inDays} days ago';
      } else {
        return '${date.day}/${date.month}/${date.year}';
      }
    } catch (e) {
      return dateString;
    }
  }

  Future<void> _deleteSpamEntry(BuildContext context, String docId) async {
    try {
      await FirebaseFirestore.instance.collection('spam').doc(docId).delete();
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Spam entry deleted')),
        );
      }
    } catch (e) {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Error deleting entry: $e')),
        );
      }
    }
  }
}

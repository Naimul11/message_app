import 'package:flutter/material.dart';
import 'package:android_sms_reader/android_sms_reader.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:telephony/telephony.dart';
import 'package:flutter_contacts/flutter_contacts.dart';

class ShowSmsPage extends StatefulWidget {
  final String sender;
  final List<AndroidSMSMessage> messages;

  const ShowSmsPage({
    super.key,
    required this.sender,
    required this.messages,
  });

  @override
  State<ShowSmsPage> createState() => _ShowSmsPageState();
}

class _ShowSmsPageState extends State<ShowSmsPage> {
  final ScrollController _scrollController = ScrollController();
  final TextEditingController _messageController = TextEditingController();
  final Telephony telephony = Telephony.instance;
  bool canSendSms = false;
  bool isValidPhoneNumber = false;
  int? selectedSimSlot;
  List<AndroidSMSMessage> allMessages = [];
  String displayName = '';

  @override
  void initState() {
    super.initState();
    allMessages = List.from(widget.messages);
    _loadContactName();
    _checkSendSmsPermission();
    _validatePhoneNumber();
    // Scroll to bottom after the frame is built
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _scrollToBottom();
    });
  }

  Future<void> _loadContactName() async {
    try {
      // Request contacts permission
      if (await FlutterContacts.requestPermission(readonly: true)) {
        // Search for contact with this phone number
        List<Contact> contacts = await FlutterContacts.getContacts(
          withProperties: true,
        );
        
        for (var contact in contacts) {
          for (var phone in contact.phones) {
            // Remove spaces and special characters for comparison
            String cleanContactPhone = phone.number.replaceAll(RegExp(r'[\s\-\(\)]'), '');
            String cleanSenderPhone = widget.sender.replaceAll(RegExp(r'[\s\-\(\)]'), '');
            
            if (cleanContactPhone.contains(cleanSenderPhone) || 
                cleanSenderPhone.contains(cleanContactPhone)) {
              setState(() {
                displayName = contact.displayName;
              });
              return;
            }
          }
        }
      }
      
      // If no contact found, use the phone number
      setState(() {
        displayName = widget.sender;
      });
    } catch (e) {
      print('Error loading contact name: $e');
      setState(() {
        displayName = widget.sender;
      });
    }
  }

  @override
  void dispose() {
    _scrollController.dispose();
    _messageController.dispose();
    super.dispose();
  }

  Future<void> _checkSendSmsPermission() async {
    var smsStatus = await Permission.sms.status;
    
    // Request permission if not granted
    if (!smsStatus.isGranted) {
      smsStatus = await Permission.sms.request();
    }
    
    setState(() {
      canSendSms = smsStatus.isGranted;
    });
  }

  void _validatePhoneNumber() {
    // Check if sender is a valid phone number (contains only digits, +, -, spaces, parentheses)
    String sender = widget.sender;
    RegExp phoneRegex = RegExp(r'^[\d\s\+\-\(\)]+$');
    setState(() {
      isValidPhoneNumber = phoneRegex.hasMatch(sender) && sender.replaceAll(RegExp(r'[^\d]'), '').length >= 7;
    });
  }

  void _scrollToBottom() {
    if (_scrollController.hasClients) {
      _scrollController.jumpTo(_scrollController.position.maxScrollExtent);
    }
  }

  Future<void> _sendSms() async {
    if (_messageController.text.trim().isEmpty) {
      return;
    }

    // Ask for SIM selection first
    int? simSlot = await _showSimSelectionDialog();
    
    if (simSlot == null) {
      return; // User cancelled
    }

    try {
      String messageText = _messageController.text.trim();
      String phoneNumber = widget.sender;
      
      print('Sending SMS to: $phoneNumber');
      print('Message: $messageText');
      
      // Request SMS permission first
      bool? permissionGranted = await telephony.requestSmsPermissions;
      
      if (permissionGranted != true) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text('SMS permission required'),
              backgroundColor: Colors.red,
            ),
          );
        }
        return;
      }
      
      // Send SMS directly using telephony
      await telephony.sendSms(
        to: phoneNumber,
        message: messageText,
        statusListener: (SendStatus status) {
          print('SMS Send Status: $status');
          if (mounted) {
            if (status == SendStatus.SENT) {
              // Add sent message to the list
              setState(() {
                allMessages.add(AndroidSMSMessage(
                  id: DateTime.now().millisecondsSinceEpoch,
                  address: phoneNumber,
                  body: messageText,
                  date: DateTime.now().millisecondsSinceEpoch,
                  type: "2", // TYPE_SENT
                ));
              });
              
              _messageController.clear();
              ScaffoldMessenger.of(context).showSnackBar(
                const SnackBar(
                  content: Text('Message sent successfully!'),
                  backgroundColor: Colors.green,
                ),
              );
              
              // Scroll to bottom to show new message
              WidgetsBinding.instance.addPostFrameCallback((_) {
                _scrollToBottom();
              });
            } else if (status == SendStatus.DELIVERED) {
              ScaffoldMessenger.of(context).showSnackBar(
                const SnackBar(
                  content: Text('Message delivered!'),
                  backgroundColor: Colors.green,
                ),
              );
            }
          }
        },
      );
      
    } catch (e) {
      print('Error sending SMS: $e');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Failed to send SMS: $e'),
            backgroundColor: Colors.red,
          ),
        );
      }
    }
  }

  Future<int?> _showSimSelectionDialog() async {
    return showDialog<int>(
      context: context,
      builder: (BuildContext context) {
        return AlertDialog(
          title: const Text('Select SIM Card'),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              ListTile(
                leading: const Icon(Icons.sim_card, color: Colors.blue),
                title: const Text('SIM 1'),
                onTap: () {
                  Navigator.pop(context, 0);
                },
              ),
              ListTile(
                leading: const Icon(Icons.sim_card, color: Colors.green),
                title: const Text('SIM 2'),
                onTap: () {
                  Navigator.pop(context, 1);
                },
              ),
            ],
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context),
              child: const Text('Cancel'),
            ),
          ],
        );
      },
    );
  }

  String _formatDate(int timestamp) {
    DateTime date = DateTime.fromMillisecondsSinceEpoch(timestamp);
    DateTime now = DateTime.now();
    
    if (date.year == now.year && date.month == now.month && date.day == now.day) {
      return 'Today ${date.hour.toString().padLeft(2, '0')}:${date.minute.toString().padLeft(2, '0')}';
    } else if (date.year == now.year && date.month == now.month && date.day == now.day - 1) {
      return 'Yesterday ${date.hour.toString().padLeft(2, '0')}:${date.minute.toString().padLeft(2, '0')}';
    } else {
      return '${date.day}/${date.month}/${date.year} ${date.hour.toString().padLeft(2, '0')}:${date.minute.toString().padLeft(2, '0')}';
    }
  }

  List<AndroidSMSMessage> _getSortedMessages() {
    // Sort messages by date in ascending order (oldest first, newest at bottom)
    List<AndroidSMSMessage> sorted = List.from(allMessages);
    sorted.sort((a, b) => a.date.compareTo(b.date));
    return sorted;
  }

  @override
  Widget build(BuildContext context) {
    List<AndroidSMSMessage> sortedMessages = _getSortedMessages();

    return Scaffold(
      appBar: AppBar(
        title: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              displayName.isNotEmpty ? displayName : widget.sender,
              style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
            ),
            Text(
              displayName.isNotEmpty ? widget.sender : '${sortedMessages.length} message${sortedMessages.length > 1 ? 's' : ''}',
              style: const TextStyle(fontSize: 12, fontWeight: FontWeight.normal),
            ),
          ],
        ),
        backgroundColor: Theme.of(context).colorScheme.inversePrimary,
      ),
      body: Column(
        children: [
          Expanded(
            child: sortedMessages.isEmpty
                ? const Center(
                    child: Text('No messages'),
                  )
                : ListView.builder(
                    controller: _scrollController,
                    padding: const EdgeInsets.all(8),
                    itemCount: sortedMessages.length,
                    itemBuilder: (context, index) {
                      AndroidSMSMessage message = sortedMessages[index];
                      bool isReceived = message.type == 'inbox' || message.type == '1';
                      
                      return Padding(
                        padding: const EdgeInsets.symmetric(vertical: 4),
                        child: Align(
                          alignment: isReceived ? Alignment.centerLeft : Alignment.centerRight,
                          child: Container(
                            constraints: BoxConstraints(
                              maxWidth: MediaQuery.of(context).size.width * 0.75,
                            ),
                            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                            decoration: BoxDecoration(
                              color: isReceived
                                  ? Colors.grey[300]
                                  : Theme.of(context).colorScheme.primaryContainer,
                              borderRadius: BorderRadius.circular(16),
                            ),
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  message.body,
                                  style: TextStyle(
                                    fontSize: 15,
                                    color: isReceived
                                        ? Colors.black87
                                        : Theme.of(context).colorScheme.onPrimaryContainer,
                                  ),
                                ),
                                const SizedBox(height: 4),
                                Text(
                                  _formatDate(message.date),
                                  style: TextStyle(
                                    fontSize: 11,
                                    color: isReceived
                                        ? Colors.black54
                                        : Theme.of(context).colorScheme.onPrimaryContainer.withOpacity(0.7),
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ),
                      );
                    },
                  ),
          ),
          if (canSendSms && isValidPhoneNumber)
            Container(
              padding: const EdgeInsets.all(8.0),
              decoration: BoxDecoration(
                color: Theme.of(context).colorScheme.surface,
                boxShadow: [
                  BoxShadow(
                    color: Colors.grey.withOpacity(0.3),
                    spreadRadius: 1,
                    blurRadius: 3,
                    offset: const Offset(0, -1),
                  ),
                ],
              ),
              child: Row(
                children: [
                  Expanded(
                    child: TextField(
                      controller: _messageController,
                      decoration: InputDecoration(
                        hintText: 'Type a message...',
                        border: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(24),
                        ),
                        contentPadding: const EdgeInsets.symmetric(
                          horizontal: 16,
                          vertical: 10,
                        ),
                      ),
                      maxLines: null,
                      textCapitalization: TextCapitalization.sentences,
                    ),
                  ),
                  const SizedBox(width: 8),
                  IconButton(
                    onPressed: _sendSms,
                    icon: Icon(
                      Icons.send,
                      color: Theme.of(context).colorScheme.primary,
                    ),
                    style: IconButton.styleFrom(
                      backgroundColor: Theme.of(context).colorScheme.primaryContainer,
                      padding: const EdgeInsets.all(12),
                    ),
                  ),
                ],
              ),
            ),
        ],
      ),
    );
  }
}

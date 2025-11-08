import 'package:flutter/material.dart';
import 'package:android_sms_reader/android_sms_reader.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:telephony/telephony.dart';
import 'package:flutter_contacts/flutter_contacts.dart';
import 'package:sim_reader/sim_reader.dart';
import 'services/dual_sim_sms_service.dart';

// Message status enum
enum MessageStatus { sending, sent, failed }

// Custom message class to track status
class MessageWithStatus {
  final String message;
  final DateTime timestamp;
  final MessageStatus status;
  final bool isSent; // true if sent by user, false if received

  MessageWithStatus({
    required this.message,
    required this.timestamp,
    required this.status,
    required this.isSent,
  });
}

class ShowSmsPage extends StatefulWidget {
  final String sender;
  final List<AndroidSMSMessage> messages;
  final String? pendingMessage;
  final int? pendingSimSlot;

  const ShowSmsPage({
    super.key,
    required this.sender,
    required this.messages,
    this.pendingMessage,
    this.pendingSimSlot,
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
  SimInfo? selectedSim;
  List<SimInfo> simCards = [];
  List<AndroidSMSMessage> allMessages = [];
  List<MessageWithStatus> pendingMessages = [];
  String displayName = '';

  @override
  void initState() {
    super.initState();
    allMessages = List.from(widget.messages);
    _loadContactName();
    _checkSendSmsPermission();
    _validatePhoneNumber();
    _loadSimCards();
    
    // Handle pending message if exists
    if (widget.pendingMessage != null && widget.pendingSimSlot != null) {
      selectedSimSlot = widget.pendingSimSlot;
      _sendPendingMessage(widget.pendingMessage!, widget.pendingSimSlot!);
    }
    
    // Scroll to bottom after the frame is built
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _scrollToBottom();
    });
  }

  Future<void> _loadSimCards() async {
    try {
      // Request phone permission for SIM info
      PermissionStatus permissionStatus = await Permission.phone.request();
      
      if (!permissionStatus.isGranted) {
        return;
      }

      // Get all SIM cards info
      List<SimInfo> sims = await SimReader.getAllSimInfo();
      
      setState(() {
        simCards = sims;
        // Auto-select the first SIM if available and no SIM is already selected
        if (simCards.isNotEmpty && selectedSim == null) {
          selectedSim = simCards[0];
          selectedSimSlot = selectedSim?.simSlotIndex ?? 0;
        }
      });
    } catch (e) {
      print('Error loading SIM cards: $e');
    }
  }

  Future<void> _sendPendingMessage(String message, int simSlot) async {
    // Add message to pending list with "sending" status
    setState(() {
      pendingMessages.add(MessageWithStatus(
        message: message,
        timestamp: DateTime.now(),
        status: MessageStatus.sending,
        isSent: true,
      ));
    });

    // Scroll to bottom to show the new message
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _scrollToBottom();
    });

    try {
      // Send SMS using the dual SIM service
      bool success = await DualSimSmsService.sendSmsBySim(
        phoneNumber: widget.sender,
        message: message,
        simSlot: simSlot,
      );

      // Update message status
      setState(() {
        int index = pendingMessages.indexWhere((m) => 
          m.message == message && m.status == MessageStatus.sending
        );
        if (index != -1) {
          pendingMessages[index] = MessageWithStatus(
            message: message,
            timestamp: pendingMessages[index].timestamp,
            status: success ? MessageStatus.sent : MessageStatus.failed,
            isSent: true,
          );
        }
      });
    } catch (e) {
      print('Error sending message: $e');
      // Update message status to failed
      setState(() {
        int index = pendingMessages.indexWhere((m) => 
          m.message == message && m.status == MessageStatus.sending
        );
        if (index != -1) {
          pendingMessages[index] = MessageWithStatus(
            message: message,
            timestamp: pendingMessages[index].timestamp,
            status: MessageStatus.failed,
            isSent: true,
          );
        }
      });
    }
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

    // Use selected SIM or first available
    int simSlot = selectedSimSlot ?? 0;
    
    try {
      String messageText = _messageController.text.trim();
      String phoneNumber = widget.sender;
      
      print('Sending SMS to: $phoneNumber');
      print('Message: $messageText');
      print('Using SIM Slot: $simSlot');
      
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

      // Add message to pending list with "sending" status
      setState(() {
        pendingMessages.add(MessageWithStatus(
          message: messageText,
          timestamp: DateTime.now(),
          status: MessageStatus.sending,
          isSent: true,
        ));
      });
      
      // Clear message input
      _messageController.clear();

      // Scroll to bottom to show the new message
      WidgetsBinding.instance.addPostFrameCallback((_) {
        _scrollToBottom();
      });
      
      // Send SMS using the dual SIM service
      bool success = await DualSimSmsService.sendSmsBySim(
        phoneNumber: phoneNumber,
        message: messageText,
        simSlot: simSlot,
      );

      // Update message status
      setState(() {
        int index = pendingMessages.indexWhere((m) => 
          m.message == messageText && m.status == MessageStatus.sending
        );
        
        if (index != -1) {
          pendingMessages[index] = MessageWithStatus(
            message: messageText,
            timestamp: pendingMessages[index].timestamp,
            status: success ? MessageStatus.sent : MessageStatus.failed,
            isSent: true,
          );
        }
      });
      
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

  String _formatDateTime(DateTime date) {
    DateTime now = DateTime.now();
    
    if (date.year == now.year && date.month == now.month && date.day == now.day) {
      return 'Today ${date.hour.toString().padLeft(2, '0')}:${date.minute.toString().padLeft(2, '0')}';
    } else if (date.year == now.year && date.month == now.month && date.day == now.day - 1) {
      return 'Yesterday ${date.hour.toString().padLeft(2, '0')}:${date.minute.toString().padLeft(2, '0')}';
    } else {
      return '${date.day}/${date.month}/${date.year} ${date.hour.toString().padLeft(2, '0')}:${date.minute.toString().padLeft(2, '0')}';
    }
  }

  Widget _buildStatusIcon(MessageStatus status) {
    switch (status) {
      case MessageStatus.sending:
        return const SizedBox(
          width: 16,
          height: 16,
          child: CircularProgressIndicator(
            strokeWidth: 2,
            valueColor: AlwaysStoppedAnimation<Color>(Colors.white70),
          ),
        );
      case MessageStatus.sent:
        return const Icon(
          Icons.check_circle,
          size: 16,
          color: Colors.green,
        );
      case MessageStatus.failed:
        return const Icon(
          Icons.watch_later,
          size: 16,
          color: Colors.red,
        );
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
        backgroundColor: const Color.fromARGB(255, 215, 215, 215), // Teal 700
          foregroundColor: const Color.fromARGB(255, 0, 0, 0),
      ),
      body: Column(
        children: [
          Expanded(
            child: (sortedMessages.isEmpty && pendingMessages.isEmpty)
                ? const Center(
                    child: Text('No messages'),
                  )
                : ListView.builder(
                    controller: _scrollController,
                    padding: const EdgeInsets.all(8),
                    itemCount: sortedMessages.length + pendingMessages.length,
                    itemBuilder: (context, index) {
                      // Show existing messages first, then pending messages
                      if (index < sortedMessages.length) {
                        // Existing message
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
                      } else {
                        // Pending message
                        MessageWithStatus pendingMsg = pendingMessages[index - sortedMessages.length];
                        
                        return Padding(
                          padding: const EdgeInsets.symmetric(vertical: 4),
                          child: Align(
                            alignment: Alignment.centerRight,
                            child: Container(
                              constraints: BoxConstraints(
                                maxWidth: MediaQuery.of(context).size.width * 0.75,
                              ),
                              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                              decoration: BoxDecoration(
                                color: Theme.of(context).colorScheme.primaryContainer,
                                borderRadius: BorderRadius.circular(16),
                              ),
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Row(
                                    mainAxisSize: MainAxisSize.min,
                                    children: [
                                      Flexible(
                                        child: Text(
                                          pendingMsg.message,
                                          style: TextStyle(
                                            fontSize: 15,
                                            color: Theme.of(context).colorScheme.onPrimaryContainer,
                                          ),
                                        ),
                                      ),
                                      const SizedBox(width: 8),
                                      // Status icon
                                      _buildStatusIcon(pendingMsg.status),
                                    ],
                                  ),
                                  const SizedBox(height: 4),
                                  Text(
                                    _formatDateTime(pendingMsg.timestamp),
                                    style: TextStyle(
                                      fontSize: 11,
                                      color: Theme.of(context).colorScheme.onPrimaryContainer.withOpacity(0.7),
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          ),
                        );
                      }
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
              child: Column(
                children: [
                  // SIM Selector - Show above message box
                  if (simCards.isNotEmpty)
                    Container(
                      margin: const EdgeInsets.only(bottom: 8),
                      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                      decoration: BoxDecoration(
                        color: Theme.of(context).colorScheme.surfaceContainerHighest,
                        borderRadius: BorderRadius.circular(8),
                      ),
                      child: Row(
                        mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                        children: simCards.map((sim) {
                          int slotIndex = sim.simSlotIndex ?? 0;
                          String simLabel = sim.carrierName ?? 'SIM ${slotIndex + 1}';
                          bool isSelected = selectedSim?.simSlotIndex == sim.simSlotIndex;
                          Color simColor = slotIndex == 0 ? Colors.blue : Colors.purple;
                          
                          return Expanded(
                            child: InkWell(
                              onTap: () {
                                setState(() {
                                  selectedSim = sim;
                                  selectedSimSlot = slotIndex;
                                });
                              },
                              borderRadius: BorderRadius.circular(8),
                              child: Container(
                                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                                child: Row(
                                  mainAxisAlignment: MainAxisAlignment.center,
                                  children: [
                                    CircleAvatar(
                                      radius: 10,
                                      backgroundColor: simColor,
                                      child: Text(
                                        '${slotIndex + 1}',
                                        style: const TextStyle(
                                          color: Colors.white,
                                          fontSize: 10,
                                          fontWeight: FontWeight.bold,
                                        ),
                                      ),
                                    ),
                                    const SizedBox(width: 8),
                                    Flexible(
                                      child: Text(
                                        simLabel,
                                        style: TextStyle(
                                          fontSize: 13,
                                          fontWeight: isSelected ? FontWeight.bold : FontWeight.normal,
                                          color: isSelected 
                                            ? Theme.of(context).colorScheme.primary
                                            : Theme.of(context).colorScheme.onSurface,
                                        ),
                                        overflow: TextOverflow.ellipsis,
                                      ),
                                    ),
                                    const SizedBox(width: 4),
                                    if (isSelected)
                                      Icon(
                                        Icons.check_circle,
                                        color: Theme.of(context).colorScheme.primary,
                                        size: 18,
                                      ),
                                  ],
                                ),
                              ),
                            ),
                          );
                        }).toList(),
                      ),
                    ),
                  Row(
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
                ],
              ),
            ),
        ],
      ),
    );
  }
}

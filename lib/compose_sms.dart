import 'package:flutter/material.dart';
import 'package:flutter_contacts/flutter_contacts.dart';
import 'package:telephony/telephony.dart';
import 'show_sms.dart';

class ComposeSmsPage extends StatefulWidget {
  const ComposeSmsPage({super.key});

  @override
  State<ComposeSmsPage> createState() => _ComposeSmsPageState();
}

class _ComposeSmsPageState extends State<ComposeSmsPage> {
  List<Contact> contacts = [];
  List<Contact> filteredContacts = [];
  bool isLoading = true;
  final TextEditingController _searchController = TextEditingController();

  @override
  void initState() {
    super.initState();
    _loadContacts();
  }

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  Future<void> _loadContacts() async {
    setState(() {
      isLoading = true;
    });

    // Request contacts permission
    bool hasPermission = await FlutterContacts.requestPermission(readonly: true);
    
    if (!hasPermission) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Contacts permission is required to select contacts'),
            duration: Duration(seconds: 3),
          ),
        );
      }
      setState(() {
        isLoading = false;
      });
      return;
    }

    try {
      // Get all contacts with phone numbers
      List<Contact> allContacts = await FlutterContacts.getContacts(
        withProperties: true,
        withPhoto: false,
      );

      print('Total contacts fetched: ${allContacts.length}');

      // Filter contacts with phone numbers
      List<Contact> contactsWithPhones = allContacts
          .where((contact) => contact.phones.isNotEmpty)
          .toList();

      print('Contacts with phones: ${contactsWithPhones.length}');

      setState(() {
        contacts = contactsWithPhones;
        filteredContacts = contactsWithPhones;
        isLoading = false;
      });
      
      if (contactsWithPhones.isEmpty && mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('No contacts with phone numbers found')),
        );
      }
    } catch (e) {
      print('Error loading contacts: $e');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Error loading contacts: $e')),
        );
      }
      setState(() {
        isLoading = false;
      });
    }
  }

  void _filterContacts(String query) {
    if (query.isEmpty) {
      setState(() {
        filteredContacts = contacts;
      });
      return;
    }

    setState(() {
      filteredContacts = contacts.where((contact) {
        String displayName = contact.displayName.toLowerCase();
        String searchQuery = query.toLowerCase();
        
        // Search in name
        if (displayName.contains(searchQuery)) {
          return true;
        }
        
        // Search in phone numbers
        for (var phone in contact.phones) {
          if (phone.number.contains(searchQuery)) {
            return true;
          }
        }
        
        return false;
      }).toList();
    });
  }

  void _selectContact(Contact contact) {
    if (contact.phones.length == 1) {
      // Navigate to SMS compose page
      Navigator.push(
        context,
        MaterialPageRoute(
          builder: (context) => SmsComposeScreen(
            contactName: contact.displayName,
            phoneNumber: contact.phones.first.number,
          ),
        ),
      );
    } else {
      // Show phone number selection dialog
      _showPhoneSelectionDialog(contact);
    }
  }

  void _showPhoneSelectionDialog(Contact contact) {
    showDialog(
      context: context,
      builder: (BuildContext context) {
        return AlertDialog(
          title: Text('Select phone number for ${contact.displayName}'),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: contact.phones.map((phone) {
              return ListTile(
                title: Text(phone.number),
                subtitle: Text(phone.label.name),
                onTap: () {
                  Navigator.pop(context);
                  Navigator.push(
                    context,
                    MaterialPageRoute(
                      builder: (context) => SmsComposeScreen(
                        contactName: contact.displayName,
                        phoneNumber: phone.number,
                      ),
                    ),
                  );
                },
              );
            }).toList(),
          ),
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Select Contact'),
        backgroundColor: Theme.of(context).colorScheme.inversePrimary,
      ),
      body: Column(
        children: [
          // Search bar
          Padding(
            padding: const EdgeInsets.all(8.0),
            child: TextField(
              controller: _searchController,
              decoration: InputDecoration(
                hintText: 'Search contacts...',
                prefixIcon: const Icon(Icons.search),
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(24),
                ),
                suffixIcon: _searchController.text.isNotEmpty
                    ? IconButton(
                        icon: const Icon(Icons.clear),
                        onPressed: () {
                          _searchController.clear();
                          _filterContacts('');
                        },
                      )
                    : null,
              ),
              onChanged: _filterContacts,
            ),
          ),
          
          // Contact list
          Expanded(
            child: isLoading
                ? const Center(child: CircularProgressIndicator())
                : filteredContacts.isEmpty
                    ? const Center(child: Text('No contacts found'))
                    : ListView.builder(
                        itemCount: filteredContacts.length,
                        itemBuilder: (context, index) {
                          Contact contact = filteredContacts[index];
                          String displayName = contact.displayName;
                          
                          return ListTile(
                            leading: CircleAvatar(
                              backgroundColor: Theme.of(context)
                                  .colorScheme
                                  .primaryContainer,
                              child: Text(
                                displayName.isNotEmpty
                                    ? displayName[0].toUpperCase()
                                    : '?',
                                style: TextStyle(
                                  color: Theme.of(context)
                                      .colorScheme
                                      .onPrimaryContainer,
                                ),
                              ),
                            ),
                            title: Text(displayName),
                            subtitle: Text(contact.phones.first.number),
                            onTap: () => _selectContact(contact),
                          );
                        },
                      ),
          ),
        ],
      ),
    );
  }
}

// SMS Compose Screen - Second page after selecting contact
class SmsComposeScreen extends StatefulWidget {
  final String contactName;
  final String phoneNumber;

  const SmsComposeScreen({
    super.key,
    required this.contactName,
    required this.phoneNumber,
  });

  @override
  State<SmsComposeScreen> createState() => _SmsComposeScreenState();
}

class _SmsComposeScreenState extends State<SmsComposeScreen> {
  final TextEditingController _messageController = TextEditingController();
  final Telephony telephony = Telephony.instance;
  List<Map<String, dynamic>> simCards = [];

  @override
  void initState() {
    super.initState();
    _loadSimCards();
  }

  @override
  void dispose() {
    _messageController.dispose();
    super.dispose();
  }

  Future<void> _loadSimCards() async {
    try {
      // Use default SIM names for now
      setState(() {
        simCards = [
          {'slot': 0, 'name': 'SIM 1', 'carrier': ''},
          {'slot': 1, 'name': 'SIM 2', 'carrier': ''},
        ];
      });
    } catch (e) {
      print('Error loading SIM cards: $e');
    }
  }

  Future<void> _sendSms() async {
    if (_messageController.text.trim().isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Please enter a message')),
      );
      return;
    }

    // Show SIM selection dialog
    _showSimSelectionDialog();
  }

  void _showSimSelectionDialog() {
    showDialog(
      context: context,
      builder: (BuildContext context) {
        return AlertDialog(
          title: const Text('Select SIM'),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: simCards.map((sim) {
              return ListTile(
                leading: const Icon(Icons.sim_card),
                title: Text(sim['name'] ?? 'SIM ${sim['slot'] + 1}'),
                subtitle: sim['carrier'] != null && sim['carrier'].toString().isNotEmpty
                    ? Text(sim['carrier'].toString())
                    : null,
                onTap: () {
                  Navigator.pop(context);
                  _sendDirectSms(sim['slot'] as int);
                },
              );
            }).toList(),
          ),
        );
      },
    );
  }

  Future<void> _sendDirectSms(int simSlot) async {
    try {
      String phoneNumber = widget.phoneNumber;
      String message = _messageController.text;
      
      print('Sending SMS to: $phoneNumber');
      print('Message: $message');
      print('SIM Slot: $simSlot');
      
      // Request SMS permission first
      bool? permissionGranted = await telephony.requestSmsPermissions;
      
      if (permissionGranted != true) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('SMS permission required')),
          );
        }
        return;
      }
      
      // Send SMS directly using telephony
      await telephony.sendSms(
        to: phoneNumber,
        message: message,
        statusListener: (SendStatus status) {
          print('SMS Send Status: $status');
          if (mounted) {
            if (status == SendStatus.SENT) {
              ScaffoldMessenger.of(context).showSnackBar(
                const SnackBar(content: Text('Message sent successfully!')),
              );
              // Navigate to show_sms page with the conversation
              Navigator.pushReplacement(
                context,
                MaterialPageRoute(
                  builder: (context) => ShowSmsPage(
                    sender: widget.phoneNumber, // Pass phone number
                    messages: [], // Will be loaded in ShowSmsPage from device
                  ),
                ),
              );
            } else if (status == SendStatus.DELIVERED) {
              ScaffoldMessenger.of(context).showSnackBar(
                const SnackBar(content: Text('Message delivered!')),
              );
            }
          }
        },
      );
      
      // Clear message after sending attempt
      _messageController.clear();
      
    } catch (e) {
      print('Error sending SMS: $e');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Failed to send SMS: $e')),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text(widget.contactName),
        backgroundColor: Theme.of(context).colorScheme.inversePrimary,
      ),
      body: Column(
        children: [
          // Contact info header
          Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: Theme.of(context).colorScheme.surfaceContainerHighest,
              border: Border(
                bottom: BorderSide(
                  color: Theme.of(context).colorScheme.outline.withOpacity(0.2),
                ),
              ),
            ),
            child: Row(
              children: [
                const Text(
                  'To: ',
                  style: TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.w500,
                  ),
                ),
                CircleAvatar(
                  backgroundColor: Theme.of(context).colorScheme.primaryContainer,
                  child: Text(
                    widget.contactName.isNotEmpty
                        ? widget.contactName[0].toUpperCase()
                        : '?',
                    style: TextStyle(
                      color: Theme.of(context).colorScheme.onPrimaryContainer,
                    ),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        widget.contactName,
                        style: const TextStyle(
                          fontSize: 16,
                          fontWeight: FontWeight.w500,
                        ),
                      ),
                      Text(
                        widget.phoneNumber,
                        style: TextStyle(
                          fontSize: 14,
                          color: Theme.of(context).colorScheme.onSurfaceVariant,
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
          
          // Spacer
          const Expanded(child: SizedBox()),
          
          // Message input area
          Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: Theme.of(context).colorScheme.surface,
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withOpacity(0.1),
                  blurRadius: 4,
                  offset: const Offset(0, -2),
                ),
              ],
            ),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
                Expanded(
                  child: TextField(
                    controller: _messageController,
                    maxLines: 5,
                    minLines: 1,
                    decoration: InputDecoration(
                      hintText: 'Message',
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(24),
                      ),
                      contentPadding: const EdgeInsets.symmetric(
                        horizontal: 16,
                        vertical: 12,
                      ),
                    ),
                  ),
                ),
                const SizedBox(width: 8),
                FloatingActionButton(
                  onPressed: _sendSms,
                  child: const Icon(Icons.send),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

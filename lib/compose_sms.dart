import 'package:flutter/material.dart';
import 'package:flutter_contacts/flutter_contacts.dart';
import 'package:telephony/telephony.dart';
import 'package:sim_reader/sim_reader.dart';
import 'package:permission_handler/permission_handler.dart';
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
  List<SimInfo> simCards = [];
  SimInfo? selectedSim;
  bool isLoadingSims = true;

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
      setState(() {
        isLoadingSims = true;
      });

      // Request phone permission for SIM info
      PermissionStatus permissionStatus = await Permission.phone.request();
      
      if (!permissionStatus.isGranted) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('Phone permission is required to read SIM information')),
          );
        }
        setState(() {
          isLoadingSims = false;
        });
        return;
      }

      // Get all SIM cards info
      List<SimInfo> sims = await SimReader.getAllSimInfo();
      
      setState(() {
        simCards = sims;
        // Auto-select the first SIM if available
        if (simCards.isNotEmpty) {
          selectedSim = simCards[0];
        }
        isLoadingSims = false;
      });

      print('Loaded ${simCards.length} SIM cards');
      for (var sim in simCards) {
        print('SIM: ${sim.carrierName}, Slot: ${sim.simSlotIndex}, Number: ${sim.phoneNumber}');
      }
    } catch (e) {
      print('Error loading SIM cards: $e');
      setState(() {
        isLoadingSims = false;
      });
      
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Error loading SIM cards: $e')),
        );
      }
    }
  }

  Future<void> _sendSms() async {
    if (_messageController.text.trim().isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Please enter a message')),
      );
      return;
    }

    if (simCards.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('No SIM cards detected')),
      );
      return;
    }

    // If multiple SIMs, show selection dialog, otherwise send directly
    if (simCards.length > 1) {
      _showSimSelectionDialog();
    } else if (selectedSim != null) {
      _sendDirectSms(selectedSim!.simSlotIndex ?? 0);
    }
  }

  void _showSimSelectionDialog() {
    showDialog(
      context: context,
      builder: (BuildContext context) {
        return AlertDialog(
          title: const Text('Select SIM card'),
          contentPadding: const EdgeInsets.symmetric(vertical: 16),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: simCards.map((sim) {
              int slotIndex = sim.simSlotIndex ?? 0;
              String simLabel = sim.carrierName ?? 'SIM ${slotIndex + 1}';
              String? simNumber = sim.phoneNumber;
              
              return ListTile(
                leading: CircleAvatar(
                  backgroundColor: _getSimColor(slotIndex),
                  child: Text(
                    '${slotIndex + 1}',
                    style: const TextStyle(
                      color: Colors.white,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ),
                title: Text(simLabel),
                subtitle: simNumber != null && simNumber.isNotEmpty
                    ? Text(simNumber)
                    : const Text('No number'),
                trailing: selectedSim?.simSlotIndex == sim.simSlotIndex
                    ? const Icon(Icons.check_circle, color: Colors.green)
                    : null,
                onTap: () {
                  Navigator.pop(context);
                  setState(() {
                    selectedSim = sim;
                  });
                  _sendDirectSms(slotIndex);
                },
              );
            }).toList(),
          ),
        );
      },
    );
  }

  Color _getSimColor(int slotIndex) {
    // Different colors for different SIM slots (like Google Messages)
    switch (slotIndex) {
      case 0:
        return Colors.blue;
      case 1:
        return Colors.purple;
      default:
        return Colors.grey;
    }
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
          
          // SIM selection indicator (like Google Messages)
          if (simCards.length > 1 && selectedSim != null)
            Container(
              width: double.infinity,
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
              decoration: BoxDecoration(
                color: Theme.of(context).colorScheme.surfaceContainerHigh,
                border: Border(
                  bottom: BorderSide(
                    color: Theme.of(context).colorScheme.outline.withOpacity(0.1),
                  ),
                ),
              ),
              child: InkWell(
                onTap: _showSimSelectionDialog,
                child: Row(
                  children: [
                    CircleAvatar(
                      radius: 12,
                      backgroundColor: _getSimColor(selectedSim!.simSlotIndex ?? 0),
                      child: Text(
                        '${(selectedSim!.simSlotIndex ?? 0) + 1}',
                        style: const TextStyle(
                          color: Colors.white,
                          fontSize: 12,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    ),
                    const SizedBox(width: 8),
                    Text(
                      selectedSim!.carrierName ?? 'SIM ${(selectedSim!.simSlotIndex ?? 0) + 1}',
                      style: TextStyle(
                        fontSize: 13,
                        color: Theme.of(context).colorScheme.onSurface,
                      ),
                    ),
                    const Spacer(),
                    Icon(
                      Icons.arrow_drop_down,
                      color: Theme.of(context).colorScheme.onSurfaceVariant,
                    ),
                  ],
                ),
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
            child: Column(
              children: [
                // Show loading or SIM count
                if (isLoadingSims)
                  const Padding(
                    padding: EdgeInsets.only(bottom: 8.0),
                    child: Row(
                      children: [
                        SizedBox(
                          width: 16,
                          height: 16,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        ),
                        SizedBox(width: 8),
                        Text('Loading SIM information...', style: TextStyle(fontSize: 12)),
                      ],
                    ),
                  )
                else if (simCards.isEmpty)
                  Padding(
                    padding: const EdgeInsets.only(bottom: 8.0),
                    child: Row(
                      children: [
                        Icon(Icons.warning, size: 16, color: Colors.orange),
                        const SizedBox(width: 8),
                        const Text('No SIM cards detected', style: TextStyle(fontSize: 12)),
                      ],
                    ),
                  ),
                Row(
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
              ],
            ),
          ),
        ],
      ),
    );
  }
}

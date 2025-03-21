import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../providers/task_provider.dart';

class NotificationSettingsDialog extends StatefulWidget {
  const NotificationSettingsDialog({super.key});

  @override
  State<NotificationSettingsDialog> createState() =>
      _NotificationSettingsDialogState();
}

class _NotificationSettingsDialogState
    extends State<NotificationSettingsDialog> {
  late TimeOfDay _selectedTime;
  late int _selectedDaysBefore;

  @override
  void initState() {
    super.initState();
    final taskProvider = Provider.of<TaskProvider>(context, listen: false);
    _selectedTime = TimeOfDay(
      hour: taskProvider.notificationHour,
      minute: taskProvider.notificationMinute,
    );
    _selectedDaysBefore = taskProvider.notificationDaysBefore;
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('Notification Settings'),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          ListTile(
            title: const Text('Notification Time'),
            trailing: TextButton(
              child: Text(
                _selectedTime.format(context),
                style: const TextStyle(fontSize: 16),
              ),
              onPressed: () async {
                final TimeOfDay? picked = await showTimePicker(
                  context: context,
                  initialTime: _selectedTime,
                );
                if (picked != null && mounted) {
                  setState(() {
                    _selectedTime = picked;
                  });
                }
              },
            ),
          ),
          ListTile(
            title: const Text('Days Before Due Date'),
            trailing: DropdownButton<int>(
              value: _selectedDaysBefore,
              items: List.generate(7, (index) => index + 1)
                  .map((days) => DropdownMenuItem(
                        value: days,
                        child: Text(days.toString()),
                      ))
                  .toList(),
              onChanged: (value) {
                if (value != null) {
                  setState(() {
                    _selectedDaysBefore = value;
                  });
                }
              },
            ),
          ),
        ],
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('Cancel'),
        ),
        TextButton(
          onPressed: () {
            final taskProvider =
                Provider.of<TaskProvider>(context, listen: false);
            taskProvider.updateNotificationTime(
              _selectedTime.hour,
              _selectedTime.minute,
              _selectedDaysBefore,
            );
            Navigator.pop(context);
          },
          child: const Text('Save'),
        ),
      ],
    );
  }
}

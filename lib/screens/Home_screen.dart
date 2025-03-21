import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:provider/provider.dart';
import '../providers/task_provider.dart';
import '../models/task.dart';

class TaskFormScreen extends StatefulWidget {
  final Task? task;

  const TaskFormScreen({super.key, this.task});

  @override
  State<TaskFormScreen> createState() => _TaskFormScreenState();
}

class _TaskFormScreenState extends State<TaskFormScreen> {
  final _formKey = GlobalKey<FormState>();
  final _titleController = TextEditingController();
  final _descriptionController = TextEditingController();
  DateTime? _selectedDate;
  TimeOfDay? _selectedNotificationTime;
  int _selectedDaysBefore = 1;
  bool _isLoading = false;

  @override
  void initState() {
    super.initState();
    if (widget.task != null) {
      _titleController.text = widget.task!.title;
      _descriptionController.text = widget.task!.description ?? '';
      _selectedDate = widget.task!.dueDate;
      _selectedNotificationTime = widget.task!.notificationTime;
      _selectedDaysBefore = widget.task!.notificationDaysBefore;
    } else {
      // Default notification time for new tasks
      final taskProvider = Provider.of<TaskProvider>(context, listen: false);
      _selectedNotificationTime = TimeOfDay(
        hour: taskProvider.notificationHour,
        minute: taskProvider.notificationMinute,
      );
      _selectedDaysBefore = taskProvider.notificationDaysBefore;
    }
  }

  @override
  void dispose() {
    _titleController.dispose();
    _descriptionController.dispose();
    super.dispose();
  }

  //  tắt bàn phím
  void _dismissKeyboard() {
    FocusScope.of(context).unfocus();
  }

  Future<void> _selectDate(BuildContext context) async {
    _dismissKeyboard(); // Tắt bàn phím khi mở date picker
    final DateTime? picked = await showDatePicker(
      context: context,
      initialDate: _selectedDate ?? DateTime.now(),
      firstDate: DateTime.now(),
      lastDate: DateTime(2100),
    );
    if (picked != null && mounted) {
      setState(() {
        _selectedDate = picked;
      });
    }
  }

  void _showTimePicker() async {
    final picked = await showTimePicker(
      context: context,
      initialTime:
          _selectedNotificationTime ?? const TimeOfDay(hour: 9, minute: 0),
    );
    if (picked != null) {
      setState(() => _selectedNotificationTime = picked);
    }
  }

  Future<void> _saveTask(TaskProvider taskProvider) async {
    if (_formKey.currentState!.validate()) {
      setState(() => _isLoading = true);

      try {
        final task = Task(
          id: widget.task?.id,
          title: _titleController.text,
          description: _descriptionController.text.isEmpty
              ? null
              : _descriptionController.text,
          dueDate: _selectedDate,
          status: widget.task?.status ?? 0,
          notificationTime: _selectedNotificationTime,
          notificationDaysBefore: _selectedDaysBefore,
        );

        widget.task == null
            ? await taskProvider.addTask(task)
            : await taskProvider.updateTask(task);
        if (mounted) Navigator.pop(context);
      } catch (e) {
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text('Error: ${e.toString()}')));
      } finally {
        setState(() => _isLoading = false);
      }
    }
  }

  void _showConfirmDialog(TaskProvider taskProvider) {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        title: Text(widget.task == null ? 'Add Task' : 'Update Task',
            textAlign: TextAlign.center),
        content: const Text('Are you sure you want to save this task?',
            textAlign: TextAlign.center),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Cancel', style: TextStyle(color: Colors.red)),
          ),
          ElevatedButton(
            style: ElevatedButton.styleFrom(backgroundColor: Colors.green),
            onPressed: () {
              Navigator.pop(context);
              _saveTask(taskProvider);
            },
            child: const Text('Confirm'),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final taskProvider = Provider.of<TaskProvider>(context, listen: false);

    return Scaffold(
      appBar:
          AppBar(title: Text(widget.task == null ? 'Add Task' : 'Edit Task')),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(16),
        child: Form(
          key: _formKey,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              TextFormField(
                controller: _titleController,
                decoration: InputDecoration(
                    labelText: 'Title',
                    border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(10))),
                validator: (value) =>
                    value!.isEmpty ? 'Please enter a title' : null,
              ),
              const SizedBox(height: 16),
              TextFormField(
                controller: _descriptionController,
                maxLines: 3,
                decoration: InputDecoration(
                    labelText: 'Description',
                    border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(10))),
              ),
              const SizedBox(height: 16),
              ListTile(
                title: const Text('Due Date'),
                subtitle: Text(_selectedDate == null
                    ? 'Select a date'
                    : DateFormat('dd/MM/yyyy').format(_selectedDate!)),
                trailing: const Icon(Icons.calendar_today),
                onTap: () => _selectDate(context),
              ),
              if (_selectedDate != null) ...[
                ListTile(
                  title: const Text('Notification Time'),
                  subtitle: Text(_selectedNotificationTime?.format(context) ??
                      'Select a time'),
                  trailing: const Icon(Icons.access_time),
                  onTap: _showTimePicker,
                ),
                ListTile(
                  title: const Text('Notify Days Before'),
                  trailing: DropdownButton<int>(
                    value: _selectedDaysBefore,
                    items: List.generate(7, (index) => index + 1)
                        .map((days) => DropdownMenuItem(
                            value: days, child: Text('$days days')))
                        .toList(),
                    onChanged: (value) =>
                        setState(() => _selectedDaysBefore = value!),
                  ),
                ),
              ],
              const SizedBox(height: 32),
              ElevatedButton(
                style:
                    ElevatedButton.styleFrom(padding: const EdgeInsets.all(16)),
                onPressed:
                    _isLoading ? null : () => _showConfirmDialog(taskProvider),
                child: _isLoading
                    ? const CircularProgressIndicator(color: Colors.white)
                    : Text(widget.task == null ? 'Add Task' : 'Update Task',
                        style: const TextStyle(fontSize: 18)),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

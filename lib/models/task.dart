import 'package:flutter/material.dart';

class Task {
  int? id;
  String title;
  String? description;
  int status;
  DateTime? dueDate;
  DateTime? createdAt;
  DateTime? updatedAt;
  TimeOfDay? notificationTime;
  int notificationDaysBefore;

  Task({
    this.id,
    required this.title,
    this.description,
    this.status = 0,
    this.dueDate,
    this.createdAt,
    this.updatedAt,
    this.notificationTime,
    this.notificationDaysBefore = 1,
  });

  Map<String, dynamic> toMap() {
    return {
      'id': id,
      'title': title,
      'description': description,
      'status': status,
      'due_date': dueDate?.toIso8601String(),
      'created_at': createdAt?.toIso8601String(),
      'updated_at': updatedAt?.toIso8601String(),
      'notification_hour': notificationTime?.hour ?? 9,
      'notification_minute': notificationTime?.minute ?? 0,
      'notification_days_before': notificationDaysBefore,
    };
  }

  factory Task.fromMap(Map<String, dynamic> map) {
    return Task(
      id: map['id'],
      title: map['title'],
      description: map['description'],
      status: map['status'],
      dueDate: map['due_date'] != null ? DateTime.parse(map['due_date']) : null,
      createdAt:
          map['created_at'] != null ? DateTime.parse(map['created_at']) : null,
      updatedAt:
          map['updated_at'] != null ? DateTime.parse(map['updated_at']) : null,
      notificationTime: map['notification_hour'] != null
          ? TimeOfDay(
              hour: map['notification_hour'],
              minute: map['notification_minute'] ?? 0)
          : null,
      notificationDaysBefore: map['notification_days_before'] ?? 1,
    );
  }

  Task copyWith({
    int? id,
    String? title,
    String? description,
    int? status,
    DateTime? dueDate,
    DateTime? createdAt,
    DateTime? updatedAt,
    TimeOfDay? notificationTime,
    int? notificationDaysBefore,
  }) {
    return Task(
      id: id ?? this.id,
      title: title ?? this.title,
      description: description ?? this.description,
      status: status ?? this.status,
      dueDate: dueDate ?? this.dueDate,
      createdAt: createdAt ?? this.createdAt,
      updatedAt: updatedAt ?? this.updatedAt,
      notificationTime: notificationTime ?? this.notificationTime,
      notificationDaysBefore:
          notificationDaysBefore ?? this.notificationDaysBefore,
    );
  }
}

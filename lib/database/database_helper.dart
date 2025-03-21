import 'package:sqflite/sqflite.dart';
import 'package:path/path.dart';

class DatabaseHelper {
  static final DatabaseHelper _instance = DatabaseHelper._internal();
  static Database? _database;

  factory DatabaseHelper() => _instance;

  DatabaseHelper._internal();

  Future<Database> get database async {
    if (_database != null) return _database!;
    _database = await _initDatabase();
    return _database!;
  }

  Future<Database> _initDatabase() async {
    String path = join(await getDatabasesPath(), 'task_manager.db');
    return await openDatabase(
      path,
      version: 2,
      onCreate: _onCreate,
      onUpgrade: _onUpgrade,
    );
  }

  Future<void> _onCreate(Database db, int version) async {
    await db.execute('''
      CREATE TABLE tasks(
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        title TEXT NOT NULL,
        description TEXT,
        status INTEGER DEFAULT 0,
        due_date TEXT,
        created_at TEXT,
        updated_at TEXT,
        notification_hour INTEGER DEFAULT 9,
        notification_minute INTEGER DEFAULT 0,
        notification_days_before INTEGER DEFAULT 1
      )
    ''');
  }

  Future<void> _onUpgrade(Database db, int oldVersion, int newVersion) async {
    if (oldVersion < 2) {
      await db.execute('''
        ALTER TABLE tasks ADD COLUMN notification_hour INTEGER DEFAULT 9
      ''');
      await db.execute('''
        ALTER TABLE tasks ADD COLUMN notification_minute INTEGER DEFAULT 0
      ''');
      await db.execute('''
        ALTER TABLE tasks ADD COLUMN notification_days_before INTEGER DEFAULT 1
      ''');
    }
  }

  Future<int> insertTask(Map<String, dynamic> task) async {
    Database db = await database;
    task['created_at'] = DateTime.now().toIso8601String();
    task['updated_at'] = DateTime.now().toIso8601String();
    return await db.insert('tasks', task);
  }

  Future<List<Map<String, dynamic>>> getTasks() async {
    Database db = await database;
    return await db.query('tasks', orderBy: 'created_at DESC');
  }

  Future<int> updateTask(Map<String, dynamic> task) async {
    Database db = await database;
    task['updated_at'] = DateTime.now().toIso8601String();
    return await db.update(
      'tasks',
      task,
      where: 'id = ?',
      whereArgs: [task['id']],
    );
  }

  Future<int> deleteTask(int id) async {
    Database db = await database;
    return await db.delete(
      'tasks',
      where: 'id = ?',
      whereArgs: [id],
    );
  }

  Future<int> toggleTaskStatus(int id, int status) async {
    Database db = await database;
    return await db.update(
      'tasks',
      {
        'status': status,
        'updated_at': DateTime.now().toIso8601String(),
      },
      where: 'id = ?',
      whereArgs: [id],
    );
  }
}

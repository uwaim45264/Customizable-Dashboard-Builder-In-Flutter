import 'package:flutter/material.dart';
import 'package:sqflite/sqflite.dart';
import 'package:path/path.dart';
import 'package:webfeed/webfeed.dart';
import 'package:http/http.dart' as http;
import 'dart:convert';
import 'package:flutter_colorpicker/flutter_colorpicker.dart';
import 'package:undo/undo.dart';
import 'CalendarWidget.dart';
import 'ClockWidget.dart';
import 'WidgetModel.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  runApp(DashboardApp());
}

class DashboardApp extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      debugShowCheckedModeBanner: false,
      title: 'Customizable Dashboard',
      theme: ThemeData.light(),
      darkTheme: ThemeData.dark(),
      themeMode: ThemeMode.system,
      home: DashboardScreen(),
    );
  }
}

class DashboardScreen extends StatefulWidget {
  @override
  _DashboardScreenState createState() => _DashboardScreenState();
}

class _DashboardScreenState extends State<DashboardScreen> with SingleTickerProviderStateMixin {
  List<WidgetModel> widgets = [];
  Database? _database;
  AnimationController? _animationController;
  ChangeStack _undoStack = ChangeStack(limit: 20);
  bool _isGridSnapEnabled = false;
  bool _isAutoSaveEnabled = true;
  bool _isDarkMode = false;

  @override
  void initState() {
    super.initState();
    _initDatabase();
    _animationController = AnimationController(
      duration: Duration(milliseconds: 300),
      vsync: this,
    );
    _loadWidgets();
  }

  @override
  void dispose() {
    _animationController?.dispose();
    _database?.close();
    super.dispose();
  }

  Future<void> _initDatabase() async {
    _database = await openDatabase(
      join(await getDatabasesPath(), 'dashboard.db'),
      onCreate: (db, version) {
        return db.execute(
          'CREATE TABLE widgets(id INTEGER PRIMARY KEY, type TEXT, x REAL, y REAL, width REAL, height REAL, content TEXT, bgColor TEXT, fontSize REAL, rotation REAL)',
        );
      },
      version: 1,
    );
  }

  Future<void> _loadWidgets() async {
    final List<Map<String, dynamic>> maps = await _database!.query('widgets');
    setState(() {
      widgets = List.generate(maps.length, (i) => WidgetModel.fromMap(maps[i]));
    });
  }

  Future<void> _saveWidget(WidgetModel widget) async {
    if (_isAutoSaveEnabled) {
      await _database!.insert(
        'widgets',
        widget.toMap(),
        conflictAlgorithm: ConflictAlgorithm.replace,
      );
    }
  }

  void _addWidget(String type, String content, {Offset? position, double? width, double? height, Color? bgColor, double? fontSize, double? rotation}) {
    _undoStack.add(Change(
      widgets.length,
          () {
        final newWidget = WidgetModel(
          id: DateTime.now().millisecondsSinceEpoch,
          type: type,
          position: position ?? Offset(50, 50),
          width: width ?? 150,
          height: height ?? 150,
          content: content,
          bgColor: bgColor ?? Colors.blue,
          fontSize: fontSize ?? 14,
          rotation: rotation ?? 0,
        );
        setState(() {
          widgets.add(newWidget);
          _saveWidget(newWidget);
          _animationController?.forward(from: 0);
        });
      },
          (index) => setState(() {
        widgets.removeAt(index);
      }),
    ));
  }

  void _updateWidgetPosition(int id, Offset newPosition) {
    final widget = widgets.firstWhere((w) => w.id == id);
    final oldPosition = widget.position;
    Offset snappedPosition = _isGridSnapEnabled
        ? Offset((newPosition.dx / 20).round() * 20, (newPosition.dy / 20).round() * 20)
        : newPosition;

    _undoStack.add(Change(
      oldPosition,
          () {
        setState(() {
          widget.position = snappedPosition;
          _saveWidget(widget);
        });
      },
          (oldValue) => setState(() {
        widget.position = oldValue;
        _saveWidget(widget);
      }),
    ));
  }

  void _updateWidgetSize(int id, double width, double height) {
    final widget = widgets.firstWhere((w) => w.id == id);
    final oldSize = {'width': widget.width, 'height': widget.height};
    _undoStack.add(Change(
      oldSize,
          () {
        setState(() {
          widget.width = width;
          widget.height = height;
          _saveWidget(widget);
        });
      },
          (oldValue) => setState(() {
        widget.width = (oldValue as Map)['width']!;
        widget.height = oldValue['height']!;
        _saveWidget(widget);
      }),
    ));
  }

  void _updateWidgetRotation(int id, double rotation) {
    final widget = widgets.firstWhere((w) => w.id == id);
    final oldRotation = widget.rotation;
    _undoStack.add(Change(
      oldRotation,
          () {
        setState(() {
          widget.rotation = rotation;
          _saveWidget(widget);
        });
      },
          (oldValue) => setState(() {
        widget.rotation = oldValue;
        _saveWidget(widget);
      }),
    ));
  }

  void _deleteWidget(int id) {
    final widget = widgets.firstWhere((w) => w.id == id);
    final index = widgets.indexOf(widget);
    _undoStack.add(Change(
      {'widget': widget, 'index': index},
          () {
        setState(() {
          widgets.removeAt(index);
          _database!.delete('widgets', where: 'id = ?', whereArgs: [id]);
        });
      },
          (oldValue) => setState(() {
        widgets.insert((oldValue as Map)['index']!, oldValue['widget'] as WidgetModel);
        _saveWidget(oldValue['widget'] as WidgetModel);
      }),
    ));
  }

  void _importLayout(String json) {
    try {
      final List<dynamic> imported = jsonDecode(json);
      setState(() {
        widgets.clear();
        widgets.addAll(imported.map((w) => WidgetModel.fromMap(w)).toList());
        for (var widget in widgets) {
          _saveWidget(widget);
        }
      });
      ScaffoldMessenger.of(context as BuildContext).showSnackBar(SnackBar(content: Text('Layout imported successfully')));
    } catch (e) {
      ScaffoldMessenger.of(context as BuildContext).showSnackBar(SnackBar(content: Text('Invalid layout format')));
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text('Customizable Dashboard'),
        actions: [
          IconButton(
            icon: Icon(Icons.add),
            onPressed: () => _showAddWidgetDialog(context),
          ),
          IconButton(
            icon: Icon(Icons.save),
            onPressed: _exportLayout,
          ),
          IconButton(
            icon: Icon(Icons.undo),
            onPressed: _undoStack.canUndo ? () => setState(() => _undoStack.undo()) : null,
          ),
          IconButton(
            icon: Icon(Icons.redo),
            onPressed: _undoStack.canRedo ? () => setState(() => _undoStack.redo()) : null,
          ),
        ],
      ),
      drawer: Drawer(
        child: ListView(
          children: [
            DrawerHeader(
              child: Text('Dashboard Settings', style: TextStyle(fontSize: 20)),
              decoration: BoxDecoration(color: Theme.of(context).primaryColor),
            ),
            SwitchListTile(
              title: Text('Dark Mode'),
              value: _isDarkMode,
              onChanged: (value) => setState(() => _isDarkMode = value),
            ),
            SwitchListTile(
              title: Text('Grid Snap'),
              value: _isGridSnapEnabled,
              onChanged: (value) => setState(() => _isGridSnapEnabled = value),
            ),
            SwitchListTile(
              title: Text('Auto Save'),
              value: _isAutoSaveEnabled,
              onChanged: (value) => setState(() => _isAutoSaveEnabled = value),
            ),
            ListTile(
              title: Text('Import Layout'),
              onTap: () => _showImportDialog(context),
            ),
            ListTile(
              title: Text('Clear All Widgets'),
              onTap: () {
                setState(() {
                  widgets.clear();
                  _database!.delete('widgets');
                });
                Navigator.pop(context);
              },
            ),
          ],
        ),
      ),
      body: Stack(
        children: widgets.map((widget) {
          return Positioned(
            left: widget.position.dx,
            top: widget.position.dy,
            child: GestureDetector(
              onPanUpdate: (details) {
                _updateWidgetPosition(
                  widget.id,
                  Offset(
                    widget.position.dx + details.delta.dx,
                    widget.position.dy + details.delta.dy,
                  ),
                );
              },
              onLongPress: () => _showWidgetOptions(context, widget),
              child: Transform.rotate(
                angle: widget.rotation * 3.14159 / 180,
                child: ScaleTransition(
                  scale: _animationController!.drive(Tween(begin: 0.8, end: 1.0)),
                  child: FadeTransition(
                    opacity: _animationController!.drive(Tween(begin: 0.0, end: 1.0)),
                    child: _buildWidget(widget),
                  ),
                ),
              ),
            ),
          );
        }).toList(),
      ),
    );
  }

  Widget _buildWidget(WidgetModel widget) {
    switch (widget.type) {
      case 'clock':
        return ClockWidget(size: Size(widget.width, widget.height));
      case 'calendar':
        return CalendarWidget(size: Size(widget.width, widget.height));
      case 'rss':
        return RSSWidget(size: Size(widget.width, widget.height), key: ValueKey(widget.id));
      case 'note':
        return NoteWidget(content: widget.content, bgColor: widget.bgColor, fontSize: widget.fontSize, size: Size(widget.width, widget.height));
      case 'weather':
        return WeatherWidget(size: Size(widget.width, widget.height));
      case 'todo':
        return TodoWidget(size: Size(widget.width, widget.height));
      case 'image':
        return ImageWidget(content: widget.content, size: Size(widget.width, widget.height));
      default:
        return Container();
    }
  }

  void _showAddWidgetDialog(BuildContext context) {
    String selectedType = 'clock';
    String content = '';
    double width = 150;
    double height = 150;
    Color bgColor = Colors.blue;
    double fontSize = 14;
    double rotation = 0;

    showDialog(
      context: context,
      builder: (BuildContext ctx) {
        return StatefulBuilder(
          builder: (context, setDialogState) {
            return AlertDialog(
              title: Text('Add Widget'),
              content: SingleChildScrollView(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    DropdownButton<String>(
                      value: selectedType,
                      items: ['clock', 'calendar', 'rss', 'note', 'weather', 'todo', 'image']
                          .map((type) => DropdownMenuItem(value: type, child: Text(type)))
                          .toList(),
                      onChanged: (value) => setDialogState(() => selectedType = value!),
                    ),
                    if (selectedType == 'note') ...[
                      TextField(
                        onChanged: (value) => content = value,
                        decoration: InputDecoration(labelText: 'Note Content'),
                      ),
                      Text('Background Color'),
                      ColorPicker(
                        pickerColor: bgColor,
                        onColorChanged: (color) => setDialogState(() => bgColor = color),
                        showLabel: false,
                        pickerAreaHeightPercent: 0.4,
                      ),
                      TextField(
                        keyboardType: TextInputType.number,
                        onChanged: (value) => fontSize = double.tryParse(value) ?? 14,
                        decoration: InputDecoration(labelText: 'Font Size'),
                      ),
                    ],
                    if (selectedType == 'image') ...[
                      TextField(
                        onChanged: (value) => content = value,
                        decoration: InputDecoration(labelText: 'Image URL'),
                      ),
                    ],
                    TextField(
                      keyboardType: TextInputType.number,
                      onChanged: (value) => width = double.tryParse(value) ?? 150,
                      decoration: InputDecoration(labelText: 'Width'),
                    ),
                    TextField(
                      keyboardType: TextInputType.number,
                      onChanged: (value) => height = double.tryParse(value) ?? 150,
                      decoration: InputDecoration(labelText: 'Height'),
                    ),
                    TextField(
                      keyboardType: TextInputType.number,
                      onChanged: (value) => rotation = double.tryParse(value) ?? 0,
                      decoration: InputDecoration(labelText: 'Rotation (degrees)'),
                    ),
                  ],
                ),
              ),
              actions: [
                TextButton(
                  onPressed: () {
                    _addWidget(selectedType, content, width: width, height: height, bgColor: bgColor, fontSize: fontSize, rotation: rotation);
                    Navigator.pop(ctx);
                  },
                  child: Text('Add'),
                ),
              ],
            );
          },
        );
      },
    );
  }

  void _showWidgetOptions(BuildContext context, WidgetModel widget) {
    showModalBottomSheet(
      context: context,
      builder: (BuildContext ctx) {
        return Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ListTile(
              leading: Icon(Icons.delete),
              title: Text('Delete Widget'),
              onTap: () {
                _deleteWidget(widget.id);
                Navigator.pop(ctx);
              },
            ),
            ListTile(
              leading: Icon(Icons.aspect_ratio),
              title: Text('Resize Widget'),
              onTap: () {
                Navigator.pop(ctx);
                _showResizeDialog(context, widget);
              },
            ),
            ListTile(
              leading: Icon(Icons.rotate_right),
              title: Text('Rotate Widget'),
              onTap: () {
                Navigator.pop(ctx);
                _showRotateDialog(context, widget);
              },
            ),
            if (widget.type == 'note')
              ListTile(
                leading: Icon(Icons.color_lens),
                title: Text('Change Background Color'),
                onTap: () {
                  Navigator.pop(ctx);
                  _showColorPickerDialog(context, widget);
                },
              ),
            if (widget.type == 'image')
              ListTile(
                leading: Icon(Icons.image),
                title: Text('Change Image URL'),
                onTap: () {
                  Navigator.pop(ctx);
                  _showImageUrlDialog(context, widget);
                },
              ),
          ],
        );
      },
    );
  }

  void _showResizeDialog(BuildContext context, WidgetModel widget) {
    double width = widget.width;
    double height = widget.height;
    showDialog(
      context: context,
      builder: (BuildContext ctx) {
        return AlertDialog(
          title: Text('Resize Widget'),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              TextField(
                keyboardType: TextInputType.number,
                onChanged: (value) => width = double.tryParse(value) ?? widget.width,
                decoration: InputDecoration(labelText: 'Width'),
              ),
              TextField(
                keyboardType: TextInputType.number,
                onChanged: (value) => height = double.tryParse(value) ?? widget.height,
                decoration: InputDecoration(labelText: 'Height'),
              ),
            ],
          ),
          actions: [
            TextButton(
              onPressed: () {
                _updateWidgetSize(widget.id, width, height);
                Navigator.pop(ctx);
              },
              child: Text('Apply'),
            ),
          ],
        );
      },
    );
  }

  void _showRotateDialog(BuildContext context, WidgetModel widget) {
    double rotation = widget.rotation;
    showDialog(
      context: context,
      builder: (BuildContext ctx) {
        return AlertDialog(
          title: Text('Rotate Widget'),
          content: TextField(
            keyboardType: TextInputType.number,
            onChanged: (value) => rotation = double.tryParse(value) ?? widget.rotation,
            decoration: InputDecoration(labelText: 'Rotation (degrees)'),
          ),
          actions: [
            TextButton(
              onPressed: () {
                _updateWidgetRotation(widget.id, rotation);
                Navigator.pop(ctx);
              },
              child: Text('Apply'),
            ),
          ],
        );
      },
    );
  }

  void _showColorPickerDialog(BuildContext context, WidgetModel widget) {
    Color pickerColor = widget.bgColor;
    showDialog(
      context: context,
      builder: (BuildContext ctx) {
        return AlertDialog(
          title: Text('Pick Background Color'),
          content: ColorPicker(
            pickerColor: pickerColor,
            onColorChanged: (color) => pickerColor = color,
          ),
          actions: [
            TextButton(
              onPressed: () {
                setState(() {
                  widget.bgColor = pickerColor;
                  _saveWidget(widget);
                });
                Navigator.pop(ctx);
              },
              child: Text('Apply'),
            ),
          ],
        );
      },
    );
  }

  void _showImageUrlDialog(BuildContext context, WidgetModel widget) {
    String newUrl = widget.content;
    showDialog(
      context: context,
      builder: (BuildContext ctx) {
        return AlertDialog(
          title: Text('Change Image URL'),
          content: TextField(
            onChanged: (value) => newUrl = value,
            decoration: InputDecoration(labelText: 'Image URL'),
            controller: TextEditingController(text: widget.content),
          ),
          actions: [
            TextButton(
              onPressed: () {
                setState(() {
                  widget.content = newUrl;
                  _saveWidget(widget);
                });
                Navigator.pop(ctx);
              },
              child: Text('Apply'),
            ),
          ],
        );
      },
    );
  }

  void _showImportDialog(BuildContext context) {
    String jsonInput = '';
    showDialog(
      context: context,
      builder: (BuildContext ctx) {
        return AlertDialog(
          title: Text('Import Layout'),
          content: TextField(
            onChanged: (value) => jsonInput = value,
            decoration: InputDecoration(labelText: 'Paste JSON Layout'),
            maxLines: 5,
          ),
          actions: [
            TextButton(
              onPressed: () {
                _importLayout(jsonInput);
                Navigator.pop(ctx);
              },
              child: Text('Import'),
            ),
          ],
        );
      },
    );
  }

  void _exportLayout() {
    final layout = jsonEncode(widgets.map((w) => w.toMap()).toList());
    ScaffoldMessenger.of(context as BuildContext).showSnackBar(
      SnackBar(content: Text('Layout exported: $layout')),
    );
  }
}






class RSSWidget extends StatelessWidget {
  final Size size;
  final String rssUrl = 'https://rss.app/feeds/9L0kIwr6M0dtgHJu.xml';
  final Key key;

  RSSWidget({required this.size, required this.key});

  @override
  Widget build(BuildContext context) {
    return Container(
      key: key,
      width: size.width,
      height: size.height,
      decoration: BoxDecoration(
        gradient: LinearGradient(colors: [Colors.orange, Colors.red]),
        borderRadius: BorderRadius.circular(10),
        boxShadow: [BoxShadow(color: Colors.black26, blurRadius: 5)],
      ),
      child: FutureBuilder<RssFeed?>(
        future: http.get(Uri.parse(rssUrl)).then((response) {
          if (response.statusCode == 200) return RssFeed.parse(response.body);
          throw Exception('Failed to load RSS');
        }).catchError((e) => null),
        builder: (BuildContext context, snapshot) {
          if (snapshot.hasData && snapshot.data != null) {
            return ListView.builder(
              itemCount: snapshot.data!.items!.length,
              itemBuilder: (context, index) {
                return ListTile(
                  title: Text(
                    snapshot.data!.items![index].title ?? '',
                    style: TextStyle(color: Colors.white, fontSize: size.height * 0.08),
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                  ),
                );
              },
            );
          } else if (snapshot.hasError || snapshot.data == null) {
            return Center(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Text('Error loading RSS', style: TextStyle(color: Colors.white)),
                  TextButton(
                    onPressed: () {
                      context.findAncestorStateOfType<_DashboardScreenState>()?.setState(() {});
                    },
                    child: Text('Retry', style: TextStyle(color: Colors.white)),
                  ),
                ],
              ),
            );
          }
          return Center(child: CircularProgressIndicator());
        },
      ),
    );
  }
}

class NoteWidget extends StatelessWidget {
  final String content;
  final Color bgColor;
  final double fontSize;
  final Size size;

  NoteWidget({required this.content, required this.bgColor, required this.fontSize, required this.size});

  @override
  Widget build(BuildContext context) {
    return Container(
      width: size.width,
      height: size.height,
      decoration: BoxDecoration(
        color: bgColor,
        borderRadius: BorderRadius.circular(10),
        boxShadow: [BoxShadow(color: Colors.black26, blurRadius: 5)],
      ),
      child: Center(
        child: Padding(
          padding: EdgeInsets.all(8.0),
          child: Text(
            content.isEmpty ? 'Enter note' : content,
            style: TextStyle(color: Colors.white, fontSize: fontSize),
            textAlign: TextAlign.center,
          ),
        ),
      ),
    );
  }
}

class WeatherWidget extends StatelessWidget {
  final Size size;
  final String apiKey = 'YOUR_OPENWEATHERMAP_API_KEY'; // Replace with your API key
  final String city = 'Lahore';

  WeatherWidget({required this.size});

  Future<Map<String, dynamic>?> _fetchWeather() async {
    try {
      final response = await http.get(Uri.parse('https://api.openweathermap.org/data/2.5/weather?q=$city&appid=$apiKey&units=metric'));
      if (response.statusCode == 200) {
        return jsonDecode(response.body);
      }
      return null;
    } catch (e) {
      return null;
    }
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      width: size.width,
      height: size.height,
      decoration: BoxDecoration(
        gradient: LinearGradient(colors: [Colors.cyan, Colors.blueAccent]),
        borderRadius: BorderRadius.circular(10),
        boxShadow: [BoxShadow(color: Colors.black26, blurRadius: 5)],
      ),
      child: FutureBuilder<Map<String, dynamic>?>(
        future: _fetchWeather(),
        builder: (BuildContext context, snapshot) {
          if (snapshot.hasData && snapshot.data != null) {
            final weather = snapshot.data!;
            return Center(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Text(
                    '${weather['main']['temp']}°C',
                    style: TextStyle(color: Colors.white, fontSize: size.height * 0.15),
                  ),
                  Text(
                    weather['weather'][0]['description'],
                    style: TextStyle(color: Colors.white, fontSize: size.height * 0.1),
                  ),
                ],
              ),
            );
          } else if (snapshot.hasError || snapshot.data == null) {
            return Center(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Text('Error loading weather', style: TextStyle(color: Colors.white)),
                  TextButton(
                    onPressed: () {
                      context.findAncestorStateOfType<_DashboardScreenState>()?.setState(() {});
                    },
                    child: Text('Retry', style: TextStyle(color: Colors.white)),
                  ),
                ],
              ),
            );
          }
          return Center(child: CircularProgressIndicator());
        },
      ),
    );
  }
}

class TodoWidget extends StatefulWidget {
  final Size size;

  TodoWidget({required this.size});

  @override
  _TodoWidgetState createState() => _TodoWidgetState();
}

class _TodoWidgetState extends State<TodoWidget> {
  List<String> todos = [];
  TextEditingController _controller = TextEditingController();

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      width: widget.size.width,
      height: widget.size.height,
      decoration: BoxDecoration(
        gradient: LinearGradient(colors: [Colors.pink, Colors.purple]),
        borderRadius: BorderRadius.circular(10),
        boxShadow: [BoxShadow(color: Colors.black26, blurRadius: 5)],
      ),
      child: Column(
          children: [
            Padding(
              padding: EdgeInsets.all(8.0),
              child: Row(
                children: [
                  Expanded(
                    child: TextField(
                      controller: _controller,
                      decoration: InputDecoration(
                        hintText: 'Add task',
                        hintStyle: TextStyle(color: Colors.white70),
                        border: OutlineInputBorder(),
                      ),
                      style: TextStyle(color: Colors.white),
                      onSubmitted: (value) {
                        if (value.isNotEmpty) {
                          setState(() {
                            todos.add(value);
                            _controller.clear();
                          });
                        }
                      },
                    ),
                  ),
                  IconButton(
                    icon: Icon(Icons.add, color: Colors.white),
                    onPressed: () {
                      if (_controller.text.isNotEmpty) {
                        setState(() {
                          todos.add(_controller.text);
                          _controller.clear();
                        });
                      }
                    },
                  ),
                ],
              ),
            ),
            Expanded(
              child: ListView.builder(
                itemCount: todos.length,
                itemBuilder: (context, index) {
                  return ListTile(
                    title: Text(
                      todos[index],
                      style: TextStyle(color: Colors.white, fontSize: widget.size.height * 0.08),
                    ),
                    trailing: IconButton(
                      icon: Icon(Icons.delete, color: Colors.white),
                      onPressed: () => setState(() => todos.removeAt(index)),
                    ),
                  );
                },
              ),
            ),
          ]
      ),
    );
  }
}

class ImageWidget extends StatelessWidget {
  final String content;
  final Size size;

  ImageWidget({required this.content, required this.size});

  @override
  Widget build(BuildContext context) {
    return Container(
      width: size.width,
      height: size.height,
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(10),
        boxShadow: [BoxShadow(color: Colors.black26, blurRadius: 5)],
      ),
      child: content.isNotEmpty
          ? Image.network(
        content,
        fit: BoxFit.cover,
        errorBuilder: (context, error, stackTrace) => _placeholderImage(),
      )
          : _placeholderImage(),
    );
  }

  Widget _placeholderImage() {
    return Container(
      decoration: BoxDecoration(
        image: DecorationImage(
          image: NetworkImage('https://via.placeholder.com/150'),
          fit: BoxFit.cover,
        ),
      ),
      child: Center(
        child: Text(
          'No image URL provided',
          style: TextStyle(color: Colors.white, fontSize: 14),
          textAlign: TextAlign.center,
        ),
      ),
    );
  }
}
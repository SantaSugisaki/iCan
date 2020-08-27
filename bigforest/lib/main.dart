//import 'dart:ffi';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'dart:typed_data';
import 'dart:ui';
//import 'package:http/http.dart' as http;
import 'package:flutter/cupertino.dart';
import 'package:rxdart/subjects.dart';
import 'dart:convert';
import 'package:flutter_bluetooth_serial/flutter_bluetooth_serial.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:charts_flutter/flutter.dart' as charts;
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:table_calendar/table_calendar.dart';
import 'package:intl/date_symbol_data_local.dart';
import 'package:url_launcher/url_launcher.dart';

final FlutterLocalNotificationsPlugin flutterLocalNotificationsPlugin =
    FlutterLocalNotificationsPlugin();

// Streams are created so that app can respond to notification-related events since the plugin is initialised in the `main` function
final BehaviorSubject<ReceivedNotification> didReceiveLocalNotificationSubject =
    BehaviorSubject<ReceivedNotification>();

final BehaviorSubject<String> selectNotificationSubject =
    BehaviorSubject<String>();

class ReceivedNotification {
  final int id;
  final String title;
  final String body;
  final String payload;

  ReceivedNotification(
      {@required this.id,
      @required this.title,
      @required this.body,
      @required this.payload});
}

Future<void> main() async {
  // needed if you intend to initialize in the `main` function
  WidgetsFlutterBinding.ensureInitialized();
  // NOTE: if you want to find out if the app was launched via notification then you could use the following call and then do something like
  // change the default route of the app
  // var notificationAppLaunchDetails =
  //     await flutterLocalNotificationsPlugin.getNotificationAppLaunchDetails();

  var initializationSettingsAndroid = AndroidInitializationSettings('app_icon');
  var initializationSettingsIOS = IOSInitializationSettings(
      onDidReceiveLocalNotification:
          (int id, String title, String body, String payload) async {
    didReceiveLocalNotificationSubject.add(ReceivedNotification(
        id: id, title: title, body: body, payload: payload));
  });
  var initializationSettings = InitializationSettings(
      initializationSettingsAndroid, initializationSettingsIOS);
  await flutterLocalNotificationsPlugin.initialize(initializationSettings,
      onSelectNotification: (String payload) async {
    if (payload != null) {
      debugPrint('notification payload: ' + payload);
    }
    selectNotificationSubject.add(payload);
  });
  initializeDateFormatting().then((_) => runApp(MyApp()));
}

class MyApp extends StatelessWidget {
  MyApp({Key key}) : super(key: key);
  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'doz',
      home: ChartScreen(),
    );
  }
}

class ChartScreen extends StatefulWidget {
  ChartScreen({Key key}) : super(key: key);
  @override
  ChartScreenState createState() => ChartScreenState();
}

class ChartScreenState extends State<ChartScreen>
    with TickerProviderStateMixin {
  bool isConnected = false;
  BluetoothConnection connection;
  IconData bluetoothIcon = Icons.bluetooth;
  final String address = '24:6F:28:5F:05:86';
  List<DozingPerHour> dozingData;
  CalendarController _controller;
  Future connectDevice() async {
    if (isConnected) {
      connection.finish();
    }
    isConnected = !isConnected;
    if (isConnected) {
      connection = await BluetoothConnection.toAddress(address);
      connection.output.add(Uint8List.fromList([0]));
    }
    setState(() {
      if (isConnected) {
        bluetoothIcon = Icons.bluetooth_connected;
      } else {
        bluetoothIcon = Icons.bluetooth;
      }
      print('更新');
    }); // bluetoothのアイコンを更新
  }

  bluetooth() {
    if (isConnected) {
      bluetoothIcon = Icons.bluetooth_connected;
    } else {
      bluetoothIcon = Icons.bluetooth;
    }
    print('更新');
  }

  Future getData(int year, int month, int day) async {
    dozingData = [];
    SharedPreferences prefs = await SharedPreferences.getInstance();
    setState(() {
      for (int i = 1; i <= 24; i++) {
        dozingData.add(DozingPerHour(i.toString(),
            prefs.getInt('${year}/${month}/${day}/${i}') ?? 0, Colors.blue));
      }
    });
  }

  @override
  void initState() {
    super.initState();
    _controller = CalendarController();
    DateTime _now = DateTime.now();
    dozingData = [];
    getData(_now.year, _now.month, _now.day);
    assert(_controller != null);
  }

  @override
  void dispose() {
    _controller.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text('寝落ち状況'),
        actions: <Widget>[
          IconButton(
              icon: Icon(Icons.lightbulb_outline),
              onPressed: () async {
                const url = 'https://mezame-project.jp/awake/';
                if (await canLaunch(url)) {
                  await launch(url);
                }
              }),
          IconButton(
            icon: Icon(bluetoothIcon),
            onPressed: () async {
              await connectDevice(); // デバイスに接続
              if (isConnected) {
                connection.input.listen((Uint8List data) async {
                  showNotification();
                  SharedPreferences prefs =
                      await SharedPreferences.getInstance();
                  bool doz = await Navigator.of(context).push(
                    MaterialPageRoute(
                      builder: (context) => ConfirmScreen(),
                    ),
                  );
                  if (doz == true) {
                    setState(() {
                      DateTime _now = DateTime.now();
                      dozingData[_now.hour - 1] = DozingPerHour(
                          _now.hour.toString(),
                          (prefs.getInt(
                                      '${_now.year}/${_now.month}/${_now.day}/${_now.hour}') ??
                                  0) +
                              1,
                          Colors.blue);
                      saveData(
                          _now.year,
                          _now.month,
                          _now.day,
                          _now.hour,
                          (prefs.getInt(
                                      '${_now.year}/${_now.month}/${_now.day}/${_now.hour}') ??
                                  0) +
                              1);
                    });
                  }
                  //接続を解除
                  if (ascii.decode(data).contains('!')) {
                    connection.finish();
                  }
                }).onDone(() {
                  // 接続を解除したら
                });
              }
            },
          ),
        ],
      ),
      body: SingleChildScrollView(
        child: Center(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.center,
            children: <Widget>[
              TableCalendar(
                calendarController: _controller,
                onDaySelected: (date, events) async {
                  dozingData = [];
                  SharedPreferences prefs =
                      await SharedPreferences.getInstance();
                  setState(() {
                    for (int i = 1; i <= 24; i++) {
                      dozingData.add(DozingPerHour(
                          i.toString(),
                          prefs.getInt(
                                  '${date.year}/${date.month}/${date.day}/${i}') ??
                              0,
                          Colors.blue));
                    }
                  });
                },
              ),
              Padding(
                padding: EdgeInsets.all(32.0),
                child: SizedBox(
                  height: 200.0,
                  child: charts.BarChart(
                    [
                      charts.Series(
                        id: 'Dozed Time',
                        domainFn: (dynamic dozingData, _) => dozingData.day,
                        measureFn: (dynamic dozingData, _) =>
                            dozingData.dozingTime,
                        colorFn: (dynamic dozingData, _) => dozingData.color,
                        data: dozingData,
                      ),
                    ],
                    animate: false,
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
      floatingActionButton: FloatingActionButton(
        child: Icon(Icons.add),
        onPressed: () async {
          SharedPreferences prefs = await SharedPreferences.getInstance();
          bool doz = await Navigator.of(context).push(
            MaterialPageRoute(
              builder: (context) => ConfirmScreen(),
            ),
          );
          if (doz == true) {
            DateTime _now = DateTime.now();
            setState(() {
              if (_now.year == _controller.selectedDay.year &&
                  _now.month == _controller.selectedDay.month &&
                  _now.day == _controller.selectedDay.day) {
                dozingData[_now.hour - 1] = DozingPerHour(_now.hour.toString(),
                    dozingData[_now.hour - 1].dozingTime + 1, Colors.blue);
              }
            });
            saveData(
                _now.year,
                _now.month,
                _now.day,
                _now.hour,
                (prefs.getInt(
                            '${_now.year}/${_now.month}/${_now.day}/${_now.hour}') ??
                        0) +
                    1);
          }
        }
        /*() async {
          SharedPreferences prefs = await SharedPreferences.getInstance();
          DateTime _now = DateTime.now();
          if(_now.year == _controller.selectedDay.year && _now.month == _controller.selectedDay.month && _now.day == _controller.selectedDay.day){
            setState((){
              dozingData[_now.hour - 1] = DozingPerHour(_now.hour.toString(), dozingData[_now.hour - 1].dozingTime + 1, Colors.blue);
            });
          }
          saveData(_now.year, _now.month, _now.day, _now.hour, (prefs.getInt('${_now.year}/${_now.month}/${_now.day}/${_now.hour}')??0) + 1);
        }*/
        ,
      ),
    );
  }
}

class ConfirmScreen extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text('確認'),
        leading: IconButton(
          icon: Icon(Icons.arrow_back),
          onPressed: () {
            Navigator.of(context).pop(false);
          },
        ),
      ),
      body: Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          crossAxisAlignment: CrossAxisAlignment.center,
          children: <Widget>[
            Text('寝落ちしましたか？'),
            Row(
              mainAxisAlignment: MainAxisAlignment.center,
              crossAxisAlignment: CrossAxisAlignment.center,
              children: <Widget>[
                Center(
                  widthFactor: 1.5,
                  child: RaisedButton(
                    child: Text('はい'),
                    onPressed: () {
                      Navigator.of(context).pop(true);
                    },
                  ),
                ),
                Center(
                  widthFactor: 1.5,
                  child: RaisedButton(
                    child: Text('いいえ'),
                    onPressed: () {
                      Navigator.of(context).pop(false);
                    },
                  ),
                ),
              ],
            )
          ],
        ),
      ),
    );
  }
}

Future<void> saveData(int year, int month, int day, int hour, int value) async {
  SharedPreferences prefs = await SharedPreferences.getInstance();
  prefs.setInt('${year}/${month}/${day}/${hour}', value);
}

class DozingPerHour extends ChangeNotifier {
  final String day;
  final int dozingTime;
  final charts.Color color;

  DozingPerHour(this.day, this.dozingTime, Color color)
      : this.color = charts.Color(
            r: color.red, g: color.green, b: color.blue, a: color.alpha);
}

Future<void> showNotification() async {
  var androidPlatformChannelSpecifics = AndroidNotificationDetails(
      'your channel id', 'your channel name', 'your channel description',
      importance: Importance.Max, priority: Priority.High, ticker: 'ticker');
  var iOSPlatformChannelSpecifics = IOSNotificationDetails();
  var platformChannelSpecifics = NotificationDetails(
      androidPlatformChannelSpecifics, iOSPlatformChannelSpecifics);
  await flutterLocalNotificationsPlugin.show(
      0, 'bigforest', '寝落ちしたかもしれません。起きてください。', platformChannelSpecifics,
      payload: 'Default_Sound');
}

import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/cupertino.dart';

import 'dart:async';
import 'dart:math';
import 'dart:io';

import 'package:google_sign_in/google_sign_in.dart';
import 'package:firebase_analytics/firebase_analytics.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_database/firebase_database.dart';
import 'package:firebase_database/ui/firebase_animated_list.dart';
import 'package:firebase_storage/firebase_storage.dart';
import 'package:image_picker/image_picker.dart';

/// Resources:
/// https://codelabs.developers.google.com/codelabs/flutter/index.html?index=..%2F..index#8

void main() {
  runApp(FriendlyChatApp());
}

final ThemeData kIOSTheme = ThemeData(
  primarySwatch: Colors.orange,
  primaryColor: Colors.grey[100],
  primaryColorBrightness: Brightness.light,
);

final ThemeData kDefaultTheme = ThemeData(
  primarySwatch: Colors.purple,
  accentColor: Colors.orangeAccent[400],
);

final googleSignIn = GoogleSignIn();

final analytics = FirebaseAnalytics();
final auth = FirebaseAuth.instance;

class FriendlyChatApp extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: "FriendlyChat",
      theme: defaultTargetPlatform == TargetPlatform.iOS
          ? kIOSTheme
          : kDefaultTheme,
      home: ChatScreen(),
    );
  }
}

class ChatScreen extends StatefulWidget {
  @override
  State<StatefulWidget> createState() {
    return _ChatScreenState();
  }
}

class _ChatScreenState extends State<ChatScreen> {
  final TextEditingController _textController = TextEditingController();
  bool _isComposing = false;
  final reference = FirebaseDatabase.instance.reference().child('messages');

  void _sendMessage({String text, String imageUrl}) {
    reference.push().set({
      'text': text,
      'imageUrl': imageUrl,
      'senderName': googleSignIn.currentUser.displayName,
      'senderPhotoUrl': googleSignIn.currentUser.photoUrl,
    });
    analytics.logEvent(name: 'send_message');
  }

  Future<Null> _ensureLoggedIn() async {
    GoogleSignInAccount user = googleSignIn.currentUser;

    if (user == null) user = await googleSignIn.signInSilently();
    if (user == null) {
      await googleSignIn.signIn();
      analytics.logLogin();
    }

    if (await auth.currentUser() == null) {
      GoogleSignInAuthentication credentials =
          await googleSignIn.currentUser.authentication;
      await auth.signInWithGoogle(
        idToken: credentials.idToken,
        accessToken: credentials.accessToken,
      );
    }
  }

  Future<Null> _handleSubmitted(String text) async {
    _textController.clear();

    setState(() {
      _isComposing = false;
    });

    await _ensureLoggedIn();
    _sendMessage(text: text);
  }

  Widget _buildTextComposer() {
    return IconTheme(
      data: IconThemeData(color: Theme.of(context).accentColor),
      child: Container(
        margin: const EdgeInsets.symmetric(horizontal: 8.0),
        child: Row(
          children: <Widget>[
            Container(
              margin: EdgeInsets.symmetric(horizontal: 4.0),
              child: IconButton(
                icon: Icon(Icons.photo_camera),
                onPressed: () async {
                  await _ensureLoggedIn();
                  File imageFile =
                      await ImagePicker.pickImage(source: ImageSource.gallery);
                  int random = new Random().nextInt(100000);
                  StorageReference ref =
                      FirebaseStorage.instance.ref().child("image_$random.jpg");
                  StorageUploadTask uploadTask = ref.putFile(imageFile);
                  StorageTaskSnapshot taskSnapshot =
                      await uploadTask.onComplete;
//                  ref.putFile(imageFile);
//                  Uri downloadUrl = (await uploadTask.future).downloadUrl;
                  String downloadUrl = await taskSnapshot.ref.getDownloadURL();
                  _sendMessage(imageUrl: downloadUrl);
                },
              ),
            ),
            Flexible(
              child: TextField(
                controller: _textController,
                onChanged: (String text) {
                  setState(() {
                    _isComposing = text.length > 0;
                  });
                },
                onSubmitted: _handleSubmitted,
                decoration:
                    InputDecoration.collapsed(hintText: "Send a message"),
              ),
            ),
            Container(
              margin: EdgeInsets.symmetric(horizontal: 4.0),
              child: Theme.of(context).platform == TargetPlatform.iOS
                  ? CupertinoButton(
                      child: Text("Send"),
                      onPressed: _isComposing
                          ? () => _handleSubmitted(_textController.text)
                          : null,
                    )
                  : IconButton(
                      icon: Icon(Icons.send),
                      onPressed: _isComposing
                          ? () => _handleSubmitted(_textController.text)
                          : null,
                    ),
            ),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text("FriendlyChat"),
        elevation: Theme.of(context).platform == TargetPlatform.iOS ? 0.0 : 4.0,
      ),
      body: Container(
        child: Column(
          children: <Widget>[
            Flexible(
              child: FirebaseAnimatedList(
                query: reference,
                sort: (a, b) => b.key.compareTo(a.key),
                padding: EdgeInsets.all(8.0),
                reverse: true,
                itemBuilder: (_, DataSnapshot snapshot,
                    Animation<double> animation, __) {
                  return ChatMessage(
                    snapshot: snapshot,
                    animation: animation,
                  );
                },
              ),
            ),
            Divider(height: 1.0),
            Container(
              child: SafeArea(child: _buildTextComposer()),
              decoration: BoxDecoration(color: Theme.of(context).cardColor),
            ),
          ],
        ),
        decoration: Theme.of(context).platform == TargetPlatform.iOS
            ? BoxDecoration(
                border: Border(
                  top: BorderSide(color: Colors.grey[200]),
                ),
              )
            : null,
      ),
    );
  }
}

class ChatMessage extends StatelessWidget {
  final DataSnapshot snapshot;
  final Animation animation;

  ChatMessage({this.snapshot, this.animation});

  @override
  Widget build(BuildContext context) {
    return SizeTransition(
      sizeFactor: CurvedAnimation(parent: animation, curve: Curves.bounceOut),
      axisAlignment: 0.0,
      child: Container(
        margin: const EdgeInsets.symmetric(vertical: 10.0),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[
            Container(
              margin: const EdgeInsets.only(right: 16.0),
              child: CircleAvatar(
                backgroundImage: NetworkImage(
                  snapshot.value['senderPhotoUrl'],
                ),
              ),
            ),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: <Widget>[
                  Text(
                    snapshot.value['senderName'],
                    style: Theme.of(context).textTheme.subhead,
                  ),
                  Container(
                    margin: const EdgeInsets.only(top: 5.0),
                    child: snapshot.value['imageUrl'] != null
                        ? Image.network(
                            snapshot.value['imageUrl'],
                            width: 250.0,
                          )
                        : Text(snapshot.value['text']),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

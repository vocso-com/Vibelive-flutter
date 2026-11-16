import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:vibelive/app/callscreen/helper/push/local_notifier.dart';
import 'package:vibelive/app/callscreen/helper/push/push_envelope.dart';

/// A push with a picture (a campaign's, or an admin test from Push
/// reachability): the app keeps the picture to draw it when it shows the
/// notification itself (app open).
void main() {
  test('the picture comes from FCM notification.image (Android or iOS)', () {
    final android = PushEnvelope.fromRemote(
      const RemoteMessage(
        notification: RemoteNotification(
          title: 'New offer',
          body: 'Look',
          android: AndroidNotification(
            imageUrl: 'https://media.example.com/a.jpg',
          ),
        ),
        data: {'deeplink': 'vibecalling://wallet'},
      ),
    );
    expect(android.imageUrl, 'https://media.example.com/a.jpg');
    expect(android.deeplink, 'vibecalling://wallet');

    final ios = PushEnvelope.fromRemote(
      const RemoteMessage(
        notification: RemoteNotification(
          title: 't',
          body: 'b',
          apple: AppleNotification(imageUrl: 'https://media.example.com/b.png'),
        ),
      ),
    );
    expect(ios.imageUrl, 'https://media.example.com/b.png');
  });

  test('or from the data; never a non-https link; kept through copyWith', () {
    final fromData = PushEnvelope.fromRemote(
      const RemoteMessage(data: {'image': 'https://media.example.com/c.jpg'}),
    );
    expect(fromData.imageUrl, 'https://media.example.com/c.jpg');
    expect(fromData.copyWith(notificationId: 'x').imageUrl, fromData.imageUrl);

    final insecure = PushEnvelope.fromRemote(
      const RemoteMessage(data: {'imageUrl': 'http://insecure/a.jpg'}),
    );
    expect(insecure.imageUrl, isNull);
    expect(PushEnvelope.fromRemote(const RemoteMessage()).imageUrl, isNull);
  });

  test('the download refuses anything but https, without a request', () async {
    expect(await LocalNotifier.fetchImage('http://insecure/a.jpg'), isNull);
    expect(await LocalNotifier.fetchImage('not a link'), isNull);
  });
}

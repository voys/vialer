import 'package:vialer/data/models/user/client.dart';
import 'package:vialer/data/models/user/user.dart';
import 'package:vialer/data/models/voipgrid/app_account.dart';
import 'package:vialer/data/models/voipgrid/client_voip_config.dart';

const testApiToken = 'api-token';
const testSipPassword = 'sip-password';

final testUser = User(
  uuid: 'user-uuid',
  email: 'user@example.com',
  firstName: 'First',
  lastName: 'Last',
  token: testApiToken,
  client: Client(
    id: 1,
    uuid: 'client-uuid',
    name: 'Client',
    url: Uri.parse('https://example.com/client/1/'),
    voip: ClientVoipConfig(
      middlewareUrl: Uri.parse('https://middleware.example.com'),
      sipUrl: Uri.parse('sip.example.com'),
    ),
  ),
  appAccount: const AppAccount(
    sipUserId: '123456789',
    password: testSipPassword,
    useEncryption: true,
    useOpus: true,
  ),
);

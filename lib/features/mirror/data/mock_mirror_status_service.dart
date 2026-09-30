import '../domain/mirror_status.dart';

class MockMirrorStatusService {
  const MockMirrorStatusService();

  MirrorStatus currentStatus() {
    return MirrorStatus.ready;
  }
}

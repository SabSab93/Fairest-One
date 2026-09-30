enum MirrorStatus {
  offline,
  ready,
  cardDetected,
  countdown,
  takingPhoto,
  photoUploaded,
  error,
}

extension MirrorStatusLabel on MirrorStatus {
  String get label {
    return switch (this) {
      MirrorStatus.offline => 'Mirror offline',
      MirrorStatus.ready => 'Mirror ready',
      MirrorStatus.cardDetected => 'Card detected',
      MirrorStatus.countdown => 'Countdown',
      MirrorStatus.takingPhoto => 'Taking photo',
      MirrorStatus.photoUploaded => 'Photo uploaded',
      MirrorStatus.error => 'Mirror error',
    };
  }
}

enum BehaviorEventType {
  blockedAppAttempt,
  vpnDisabled,
  sleepViolation,
  exitAttempt,
  protectionActivated,
}

String behaviorEventTypeToStorageValue(BehaviorEventType type) {
  switch (type) {
    case BehaviorEventType.blockedAppAttempt:
      return 'blockedAppAttempt';
    case BehaviorEventType.vpnDisabled:
      return 'vpnDisabled';
    case BehaviorEventType.sleepViolation:
      return 'sleepViolation';
    case BehaviorEventType.exitAttempt:
      return 'exitAttempt';
    case BehaviorEventType.protectionActivated:
      return 'protectionActivated';
  }
}

BehaviorEventType behaviorEventTypeFromStorageValue(String value) {
  switch (value) {
    case 'blockedAppAttempt':
      return BehaviorEventType.blockedAppAttempt;
    case 'vpnDisabled':
      return BehaviorEventType.vpnDisabled;
    case 'sleepViolation':
      return BehaviorEventType.sleepViolation;
    case 'exitAttempt':
      return BehaviorEventType.exitAttempt;
    case 'protectionActivated':
    default:
      return BehaviorEventType.protectionActivated;
  }
}

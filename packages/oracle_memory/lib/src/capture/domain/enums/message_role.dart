enum MessageRole {
  user('user'),
  assistant('assistant'),
  tool('tool'),
  system('system');

  final String code;
  const MessageRole(this.code);

  static MessageRole parse(String code) =>
      values.firstWhere((e) => e.code == code, orElse: () => MessageRole.user);
}

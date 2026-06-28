enum AgentEventKind {
  step('step'),
  reasoning('reasoning'),
  query('query'),
  decision('decision'),
  action('action');

  final String code;
  const AgentEventKind(this.code);

  static AgentEventKind parse(String code) =>
      values.firstWhere((e) => e.code == code, orElse: () => AgentEventKind.step);
}
